use std::{env, time::Duration};

use reqwest::{Client, Method, RequestBuilder, Response, StatusCode, Url};
use serde::{de::DeserializeOwned, Deserialize};
use serde_json::{json, Value};

use super::{model::EmpresaDocumento, EmpresaError};

#[derive(Clone)]
pub struct EmpresaRepository {
    client: Client,
    database_url: Url,
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
struct FindResponse {
    docs: Vec<Value>,
    bookmark: String,
}

impl EmpresaRepository {
    pub fn from_connection(
        db: &crate::database::connection::CouchDb,
    ) -> Result<Self, EmpresaError> {
        Self::with_client(
            &db.url,
            db.username.clone(),
            db.password.clone(),
            db.client.clone(),
        )
    }
    #[allow(dead_code)] // Constructor independiente para pruebas y herramientas.
    pub fn from_env() -> Result<Self, EmpresaError> {
        let url = env::var("COUCHDB_URL").map_err(|_| EmpresaError::Configuration)?;
        let username = env::var("COUCHDB_USERNAME").map_err(|_| EmpresaError::Configuration)?;
        let password = env::var("COUCHDB_PASSWORD").map_err(|_| EmpresaError::Configuration)?;
        Self::new(&url, username, password)
    }

    #[allow(dead_code)]
    pub(super) fn new(url: &str, username: String, password: String) -> Result<Self, EmpresaError> {
        let client = Client::builder()
            .connect_timeout(Duration::from_secs(3))
            .timeout(Duration::from_secs(10))
            .redirect(reqwest::redirect::Policy::none())
            .build()
            .map_err(|_| EmpresaError::Configuration)?;
        Self::with_client(url, username, password, client)
    }

    fn with_client(
        url: &str,
        username: String,
        password: String,
        client: Client,
    ) -> Result<Self, EmpresaError> {
        let mut database_url = Url::parse(url).map_err(|_| EmpresaError::Configuration)?;
        if !matches!(database_url.scheme(), "http" | "https")
            || database_url.host_str().is_none()
            || !database_url.username().is_empty()
            || database_url.password().is_some()
            || database_url.query().is_some()
            || database_url.fragment().is_some()
            || username.trim().is_empty()
            || password.is_empty()
        {
            return Err(EmpresaError::Configuration);
        }
        database_url
            .path_segments_mut()
            .map_err(|_| EmpresaError::Configuration)?
            .pop_if_empty()
            .push("empresas");
        Ok(Self {
            client,
            database_url,
            username,
            password,
        })
    }

    fn request(&self, method: Method, segment: Option<&str>) -> RequestBuilder {
        let mut url = self.database_url.clone();
        if let Some(segment) = segment {
            // Un ID es un segmento, nunca una ruta CouchDB ni una URL arbitraria.
            url.path_segments_mut()
                .expect("URL HTTP validada")
                .push(segment);
        }
        self.client
            .request(method, url)
            .basic_auth(&self.username, Some(&self.password))
    }

    async fn send(
        request: RequestBuilder,
        document_lookup: bool,
    ) -> Result<Response, EmpresaError> {
        let response = request.send().await.map_err(|error| {
            tracing::warn!(
                etapa = "transporte",
                timeout = error.is_timeout(),
                conexion = error.is_connect(),
                "Solicitud a CouchDB fallida"
            );
            if error.is_connect() || error.is_timeout() {
                EmpresaError::Unavailable
            } else {
                EmpresaError::Upstream
            }
        })?;
        if !response.status().is_success() {
            tracing::warn!(
                etapa = "http",
                status = response.status().as_u16(),
                "CouchDB devolvió un estado de error"
            );
        }
        match response.status() {
            StatusCode::OK | StatusCode::CREATED => Ok(response),
            StatusCode::BAD_REQUEST => {
                let body: Value = Self::decode(response, "error_http").await?;
                if body.get("error").and_then(Value::as_str) == Some("no_usable_index") {
                    tracing::error!(
                        etapa = "indice_mango",
                        codigo = "no_usable_index",
                        "La consulta requiere el índice empresas-nit/por-nit; crear o revisar su definición"
                    );
                    Err(EmpresaError::IndexUnavailable)
                } else {
                    // Nunca registrar reason: CouchDB puede incluir datos de la consulta.
                    Err(EmpresaError::Upstream)
                }
            }
            StatusCode::NOT_FOUND if document_lookup => {
                // CouchDB distingue documento ausente y base ausente por reason.
                let body: Value = Self::decode(response, "error_http").await?;
                if body.get("reason").and_then(Value::as_str) == Some("missing")
                    || body.get("reason").and_then(Value::as_str) == Some("deleted")
                {
                    Err(EmpresaError::NotFound)
                } else {
                    Err(EmpresaError::Unavailable)
                }
            }
            StatusCode::NOT_FOUND
            | StatusCode::TOO_MANY_REQUESTS
            | StatusCode::SERVICE_UNAVAILABLE
            | StatusCode::GATEWAY_TIMEOUT => Err(EmpresaError::Unavailable),
            StatusCode::UNAUTHORIZED | StatusCode::FORBIDDEN => Err(EmpresaError::Configuration),
            StatusCode::CONFLICT => Err(EmpresaError::Conflict),
            _ => Err(EmpresaError::Upstream),
        }
    }

    async fn decode<T: DeserializeOwned>(
        response: Response,
        stage: &'static str,
    ) -> Result<T, EmpresaError> {
        response.json().await.map_err(|error| {
            // No formatear el error: puede contener URL o valores del documento.
            tracing::error!(
                etapa = stage,
                timeout = error.is_timeout(),
                "Respuesta JSON de CouchDB incompatible"
            );
            if error.is_timeout() {
                EmpresaError::Unavailable
            } else {
                EmpresaError::Upstream
            }
        })
    }

    async fn find(&self, query: Value) -> Result<FindResponse, EmpresaError> {
        let response = Self::send(
            self.request(Method::POST, Some("_find")).json(&query),
            false,
        )
        .await?;
        Self::decode(response, "respuesta_mango").await
    }

    pub async fn nit_exists(
        &self,
        nit: &str,
        except_id: Option<&str>,
    ) -> Result<bool, EmpresaError> {
        let mut selector = json!({"nit": {"$eq": nit}});
        if let Some(id) = except_id {
            selector["_id"] = json!({"$ne": id});
        }
        let response = self
            .find(json!({
                "selector": selector, "limit": 1,
                "fields": ["_id"],
                "use_index": ["empresas-nit", "por-nit"]
            }))
            .await?;
        Ok(!response.docs.is_empty())
    }

    pub async fn list(
        &self,
        limit: u32,
        bookmark: Option<String>,
    ) -> Result<(Vec<EmpresaDocumento>, String), EmpresaError> {
        let mut query = json!({
            "selector": {"nit": {"$gte": ""}},
            "sort": [{"nit": "asc"}], "limit": limit,
            "use_index": ["empresas-nit", "por-nit"]
        });
        if let Some(bookmark) = bookmark {
            query["bookmark"] = json!(bookmark);
        }
        let result = self.find(query).await?;
        let documents = result
            .docs
            .into_iter()
            .enumerate()
            .map(|(position, value)| {
                serde_json::from_value(value).map_err(|error| {
                    tracing::error!(
                        etapa = "documento_mango", posicion = position,
                        categoria = ?error.classify(),
                        "Documento incompatible con el modelo Empresa; revisar esquema en Fauxton"
                    );
                    EmpresaError::Upstream
                })
            })
            .collect::<Result<_, _>>()?;
        Ok((documents, result.bookmark))
    }

    pub async fn get(&self, id: &str) -> Result<EmpresaDocumento, EmpresaError> {
        let response = Self::send(self.request(Method::GET, Some(id)), true).await?;
        let document: EmpresaDocumento = Self::decode(response, "documento_individual").await?;
        if document.id.as_deref() != Some(id) || document.rev.as_deref().is_none_or(str::is_empty) {
            return Err(EmpresaError::Upstream);
        }
        Ok(document)
    }

    pub async fn save(
        &self,
        mut document: EmpresaDocumento,
    ) -> Result<EmpresaDocumento, EmpresaError> {
        let request = match document.id.as_deref() {
            Some(id) => self.request(Method::PUT, Some(id)),
            None => self.request(Method::POST, None),
        };
        let response = Self::send(request.json(&document), false).await?;
        let result: WriteResponse = Self::decode(response, "respuesta_escritura").await?;
        if !result.ok
            || result.id.is_empty()
            || result.rev.is_empty()
            || document.id.as_ref().is_some_and(|id| id != &result.id)
        {
            return Err(EmpresaError::Upstream);
        }
        document.id = Some(result.id);
        document.rev = Some(result.rev);
        Ok(document)
    }
}
