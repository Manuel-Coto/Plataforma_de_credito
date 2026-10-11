use reqwest::{Method, StatusCode, Url};
use serde::de::DeserializeOwned;
use serde::Deserialize;
use serde_json::{json, Value};

use crate::database::connection::CouchDb;

use super::{
    model::{Inversion, Oferta},
    InversionError,
};

#[derive(Clone)]
pub struct InversionRepository {
    client: reqwest::Client,
    ofertas_url: Url,
    operaciones_url: Url,
    facturas_url: Url,
    username: String,
    password: String,
}

#[derive(Deserialize)]
struct WriteResponse {
    ok: bool,
    id: String,
    rev: String,
}

#[derive(Deserialize)]
struct FindResponse<T> {
    docs: Vec<T>,
    #[serde(default)]
    bookmark: String,
}

impl InversionRepository {
    pub fn from_connection(db: &CouchDb) -> Result<Self, InversionError> {
        fn database_url(base: &str, name: &str) -> Result<Url, InversionError> {
            let mut url = Url::parse(base).map_err(|_| InversionError::Unavailable)?;

            url.path_segments_mut()
                .map_err(|_| InversionError::Unavailable)?
                .pop_if_empty()
                .push(name);

            Ok(url)
        }

        Ok(Self {
            client: db.client.clone(),
            ofertas_url: database_url(&db.url, "ofertas")?,
            operaciones_url: database_url(&db.url, "operaciones")?,
            facturas_url: database_url(&db.url, "facturas")?,
            username: db.username.clone(),
            password: db.password.clone(),
        })
    }

    fn request(&self, base: &Url, method: Method, id: Option<&str>) -> reqwest::RequestBuilder {
        let mut url = base.clone();

        if let Some(id) = id {
            url.path_segments_mut()
                .expect("URL CouchDB validada")
                .push(id);
        }

        self.client
            .request(method, url)
            .basic_auth(&self.username, Some(&self.password))
    }

    async fn map_error(response: reqwest::Response, lookup: bool) -> InversionError {
        match response.status() {
            StatusCode::NOT_FOUND if lookup => InversionError::NotFound,
            StatusCode::CONFLICT => InversionError::Conflict,
            StatusCode::NOT_FOUND
            | StatusCode::TOO_MANY_REQUESTS
            | StatusCode::SERVICE_UNAVAILABLE
            | StatusCode::GATEWAY_TIMEOUT => InversionError::Unavailable,
            StatusCode::BAD_REQUEST => {
                let body: Value = response.json().await.unwrap_or(Value::Null);

                if body["error"] == "no_usable_index" {
                    InversionError::IndexUnavailable
                } else {
                    InversionError::Upstream
                }
            }
            _ => InversionError::Upstream,
        }
    }

    async fn get_document<T: DeserializeOwned>(
        &self,
        base: &Url,
        id: &str,
    ) -> Result<T, InversionError> {
        let response = self
            .request(base, Method::GET, Some(id))
            .send()
            .await
            .map_err(|_| InversionError::Unavailable)?;

        if !response.status().is_success() {
            return Err(Self::map_error(response, true).await);
        }

        response.json().await.map_err(|_| InversionError::Upstream)
    }

    async fn save_document<T: serde::Serialize>(
        &self,
        base: &Url,
        id: &str,
        document: &T,
    ) -> Result<String, InversionError> {
        let response = self
            .request(base, Method::PUT, Some(id))
            .json(document)
            .send()
            .await
            .map_err(|_| InversionError::Unavailable)?;

        if !response.status().is_success() {
            return Err(Self::map_error(response, false).await);
        }

        let result: WriteResponse = response
            .json()
            .await
            .map_err(|_| InversionError::Upstream)?;

        if !result.ok || result.id != id {
            return Err(InversionError::Upstream);
        }

        Ok(result.rev)
    }

    pub async fn get_factura(&self, id: &str) -> Result<Value, InversionError> {
        self.get_document(&self.facturas_url, id).await
    }

    pub async fn get_oferta(&self, id: &str) -> Result<Oferta, InversionError> {
        self.get_document(&self.ofertas_url, id).await
    }

    pub async fn save_oferta(&self, mut oferta: Oferta) -> Result<Oferta, InversionError> {
        let id = oferta.id.clone();

        oferta.revision = Some(self.save_document(&self.ofertas_url, &id, &oferta).await?);

        Ok(oferta)
    }

    pub async fn save_inversion(&self, inversion: &Inversion) -> Result<(), InversionError> {
        self.save_document(&self.operaciones_url, &inversion.id, inversion)
            .await?;

        Ok(())
    }

    pub async fn listar_ofertas(
        &self,
        limit: u32,
        bookmark: Option<String>,
        estado: Option<super::model::EstadoOferta>,
    ) -> Result<(Vec<Oferta>, String), InversionError> {
        let mut selector = json!({ "tipo": "oferta" });

        if let Some(estado) = estado {
            selector["estado"] =
                serde_json::to_value(estado).map_err(|_| InversionError::Upstream)?;
        }

        let mut body = json!({
            "selector": selector,
            "limit": limit
        });

        if let Some(bookmark) = bookmark {
            body["bookmark"] = json!(bookmark);
        }

        let mut url = self.ofertas_url.clone();
        url.path_segments_mut()
            .map_err(|_| InversionError::Unavailable)?
            .push("_find");

        let response = self
            .client
            .post(url)
            .basic_auth(&self.username, Some(&self.password))
            .json(&body)
            .send()
            .await
            .map_err(|_| InversionError::Unavailable)?;

        if !response.status().is_success() {
            return Err(Self::map_error(response, false).await);
        }

        let found: FindResponse<Oferta> = response
            .json()
            .await
            .map_err(|_| InversionError::Upstream)?;

        Ok((found.docs, found.bookmark))
    }

    pub async fn listar_inversiones(
        &self,
        limit: u32,
        bookmark: Option<String>,
        inversionista_id: Option<&str>,
    ) -> Result<(Vec<Inversion>, String), InversionError> {
        let mut selector = json!({ "tipo": "inversion" });

        if let Some(id) = inversionista_id {
            selector["inversionista_id"] = json!(id);
        }

        let mut body = json!({
            "selector": selector,
            "limit": limit
        });

        if let Some(bookmark) = bookmark {
            body["bookmark"] = json!(bookmark);
        }

        let mut url = self.operaciones_url.clone();
        url.path_segments_mut()
            .map_err(|_| InversionError::Unavailable)?
            .push("_find");

        let response = self
            .client
            .post(url)
            .basic_auth(&self.username, Some(&self.password))
            .json(&body)
            .send()
            .await
            .map_err(|_| InversionError::Unavailable)?;

        if !response.status().is_success() {
            return Err(Self::map_error(response, false).await);
        }

        let found: FindResponse<Inversion> = response
            .json()
            .await
            .map_err(|_| InversionError::Upstream)?;

        Ok((found.docs, found.bookmark))
    }
}
