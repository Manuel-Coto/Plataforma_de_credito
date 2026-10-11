use super::{model::CreditoDocumento, CreditoError};
use crate::database::connection::CouchDb;
use reqwest::{Method, StatusCode, Url};
use serde::{de::DeserializeOwned, Deserialize};
use serde_json::{json, Value};

#[derive(Clone)]
pub struct CreditoRepository {
    client: reqwest::Client,
    url: Url,
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
    bookmark: String,
}

impl CreditoRepository {
    pub fn from_connection(db: &CouchDb) -> Result<Self, CreditoError> {
        let url = Url::parse(&db.url).map_err(|_| CreditoError::Unavailable)?;
        if url.cannot_be_a_base() {
            return Err(CreditoError::Unavailable);
        }
        Ok(Self {
            client: db.client.clone(),
            url,
            username: db.username.clone(),
            password: db.password.clone(),
        })
    }

    fn request(
        &self,
        base: &str,
        method: Method,
        id: &str,
    ) -> Result<reqwest::RequestBuilder, CreditoError> {
        let mut url = self.url.clone();
        url.path_segments_mut()
            .map_err(|_| CreditoError::Unavailable)?
            .pop_if_empty()
            .push(base)
            .push(id);
        Ok(self
            .client
            .request(method, url)
            .basic_auth(&self.username, Some(&self.password)))
    }

    fn error(status: StatusCode) -> CreditoError {
        match status {
            StatusCode::NOT_FOUND => CreditoError::NotFound,
            StatusCode::CONFLICT => CreditoError::Conflict,
            StatusCode::SERVICE_UNAVAILABLE
            | StatusCode::TOO_MANY_REQUESTS
            | StatusCode::GATEWAY_TIMEOUT => CreditoError::Unavailable,
            _ => CreditoError::Upstream,
        }
    }

    pub(super) async fn get<T: DeserializeOwned>(
        &self,
        base: &str,
        id: &str,
    ) -> Result<T, CreditoError> {
        let response = self
            .request(base, Method::GET, id)?
            .send()
            .await
            .map_err(|_| CreditoError::Unavailable)?;
        if !response.status().is_success() {
            return Err(Self::error(response.status()));
        }
        response.json().await.map_err(|_| CreditoError::Upstream)
    }

    pub(super) async fn put<T: serde::Serialize>(
        &self,
        base: &str,
        id: &str,
        document: &T,
    ) -> Result<String, CreditoError> {
        let response = self
            .request(base, Method::PUT, id)?
            .json(document)
            .send()
            .await
            .map_err(|_| CreditoError::Unavailable)?;
        if !response.status().is_success() {
            return Err(Self::error(response.status()));
        }
        let result: WriteResponse = response.json().await.map_err(|_| CreditoError::Upstream)?;
        if !result.ok || result.id != id || result.rev.is_empty() {
            return Err(CreditoError::Upstream);
        }
        Ok(result.rev)
    }

    pub(super) async fn find<T: DeserializeOwned>(
        &self,
        base: &str,
        selector: Value,
        limit: u32,
        bookmark: Option<String>,
    ) -> Result<(Vec<T>, String), CreditoError> {
        let mut query = json!({"selector": selector, "limit": limit});
        if let Some(bookmark) = bookmark {
            query["bookmark"] = json!(bookmark);
        }
        let response = self
            .request(base, Method::POST, "_find")?
            .json(&query)
            .send()
            .await
            .map_err(|_| CreditoError::Unavailable)?;
        if !response.status().is_success() {
            return Err(Self::error(response.status()));
        }
        let found: FindResponse<T> = response.json().await.map_err(|_| CreditoError::Upstream)?;
        Ok((found.docs, found.bookmark))
    }

    pub(super) async fn all<T: DeserializeOwned>(
        &self,
        base: &str,
        selector: Value,
    ) -> Result<Vec<T>, CreditoError> {
        let mut output = Vec::new();
        let mut bookmark = None;
        let mut seen = std::collections::HashSet::new();
        loop {
            let (docs, next) = self.find(base, selector.clone(), 200, bookmark).await?;
            let count = docs.len();
            output.extend(docs);
            if count == 0 {
                return Ok(output);
            }
            if next.is_empty() || !seen.insert(next.clone()) {
                return Err(CreditoError::Upstream);
            }
            bookmark = Some(next);
        }
    }

    pub(super) async fn credito(&self, id: &str) -> Result<CreditoDocumento, CreditoError> {
        let doc: Value = self.get("operaciones", id).await?;
        if doc["tipo"] != "credito" {
            return Err(CreditoError::NotFound);
        }
        let credit: CreditoDocumento =
            serde_json::from_value(doc).map_err(|_| CreditoError::Upstream)?;
        if credit.id != id {
            return Err(CreditoError::Upstream);
        }
        Ok(credit)
    }

    pub(super) async fn save(
        &self,
        mut doc: CreditoDocumento,
    ) -> Result<CreditoDocumento, CreditoError> {
        doc.revision = Some(self.put("operaciones", &doc.id, &doc).await?);
        Ok(doc)
    }

    /// Cada evento tiene una clave estable; repetir la publicación es seguro.
    pub(super) async fn audit(&self, event: Value) -> Result<(), CreditoError> {
        let id = event["_id"].as_str().ok_or(CreditoError::Upstream)?;
        match self.put("auditoria", id, &event).await {
            Ok(_) => Ok(()),
            Err(CreditoError::Conflict) => {
                let mut existing: Value = self.get("auditoria", id).await?;
                existing
                    .as_object_mut()
                    .ok_or(CreditoError::Upstream)?
                    .remove("_rev");
                if existing == event {
                    Ok(())
                } else {
                    Err(CreditoError::Conflict)
                }
            }
            Err(error) => Err(error),
        }
    }

    /// Proyecciones recuperables. Una revisión antigua nunca revierte una nueva.
    pub(super) async fn project(
        &self,
        base: &str,
        id: &str,
        tipo: &str,
        credit: &CreditoDocumento,
        changes: Value,
    ) -> Result<(), CreditoError> {
        for _ in 0..3 {
            let mut doc: Value = self.get(base, id).await?;
            if doc["tipo"] != tipo || doc["_id"] != id {
                return Err(CreditoError::Upstream);
            }
            if let Some(owner) = doc["credito_id"].as_str() {
                if owner != credit.id {
                    return Err(CreditoError::Conflict);
                }
                if doc["credito_version"].as_u64().unwrap_or(0) >= credit.version {
                    return Ok(());
                }
            }
            for (key, value) in changes.as_object().ok_or(CreditoError::Upstream)? {
                doc[key] = value.clone();
            }
            doc["credito_id"] = json!(credit.id);
            doc["credito_version"] = json!(credit.version);
            match self.put(base, id, &doc).await {
                Ok(_) => return Ok(()),
                Err(CreditoError::Conflict) => continue,
                Err(error) => return Err(error),
            }
        }
        Err(CreditoError::Conflict)
    }
}
