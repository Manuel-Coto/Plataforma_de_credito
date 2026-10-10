use super::{model::UsuarioDocumento, UsuarioError};
use reqwest::{Client, Method, RequestBuilder, Response, StatusCode, Url};
use serde::{de::DeserializeOwned, Deserialize};
use serde_json::{json, Value};
use sha2::{Digest, Sha256};
use std::{env, time::Duration};

#[derive(Clone)]
pub struct UsuarioRepository {
    client: Client,
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
struct FindResponse {
    docs: Vec<UsuarioDocumento>,
}

/// Una sola clave por correo canónico: PUT sin _rev crea de forma atómica.
pub(super) fn email_id(email: &str) -> String {
    format!("usuario:{:x}", Sha256::digest(email.as_bytes()))
}

impl UsuarioRepository {
    pub fn from_connection(
        db: &crate::database::connection::CouchDb,
    ) -> Result<Self, UsuarioError> {
        Self::with_client(
            &db.url,
            db.username.clone(),
            db.password.clone(),
            db.client.clone(),
        )
    }
    #[allow(dead_code)]
    pub fn from_env() -> Result<Self, UsuarioError> {
        Self::new(
            &env::var("COUCHDB_URL").map_err(|_| UsuarioError::Unavailable)?,
            env::var("COUCHDB_USERNAME").map_err(|_| UsuarioError::Unavailable)?,
            env::var("COUCHDB_PASSWORD").map_err(|_| UsuarioError::Unavailable)?,
        )
    }
    #[allow(dead_code)]
    pub(super) fn new(url: &str, username: String, password: String) -> Result<Self, UsuarioError> {
        let client = Client::builder()
            .connect_timeout(Duration::from_secs(3))
            .timeout(Duration::from_secs(10))
            .redirect(reqwest::redirect::Policy::none())
            .build()
            .map_err(|_| UsuarioError::Unavailable)?;
        Self::with_client(url, username, password, client)
    }

    fn with_client(
        url: &str,
        username: String,
        password: String,
        client: Client,
    ) -> Result<Self, UsuarioError> {
        let mut url = Url::parse(url).map_err(|_| UsuarioError::Unavailable)?;
        if !matches!(url.scheme(), "http" | "https")
            || url.host_str().is_none()
            || !url.username().is_empty()
            || url.password().is_some()
            || url.query().is_some()
            || url.fragment().is_some()
            || username.trim().is_empty()
            || password.is_empty()
        {
            return Err(UsuarioError::Unavailable);
        }
        url.path_segments_mut()
            .map_err(|_| UsuarioError::Unavailable)?
            .pop_if_empty()
            .push("usuarios");
        Ok(Self {
            client,
            url,
            username,
            password,
        })
    }
    fn request(&self, method: Method, id: &str) -> RequestBuilder {
        let mut url = self.url.clone();
        url.path_segments_mut().expect("URL HTTP validada").push(id);
        self.client
            .request(method, url)
            .basic_auth(&self.username, Some(&self.password))
    }
    async fn send(request: RequestBuilder, lookup: bool) -> Result<Response, UsuarioError> {
        let response = request.send().await.map_err(|e| {
            tracing::warn!(
                modulo = "usuarios",
                etapa = "transporte",
                timeout = e.is_timeout(),
                "Solicitud CouchDB fallida"
            );
            if e.is_timeout() || e.is_connect() {
                UsuarioError::Unavailable
            } else {
                UsuarioError::Upstream
            }
        })?;
        let status = response.status();
        if !status.is_success() {
            tracing::warn!(
                modulo = "usuarios",
                status = status.as_u16(),
                "CouchDB devolvió error"
            );
        }
        match status {
            StatusCode::OK | StatusCode::CREATED => Ok(response),
            StatusCode::CONFLICT => Err(UsuarioError::Conflict),
            StatusCode::NOT_FOUND if lookup => {
                let value: Value = Self::decode(response).await?;
                match value["reason"].as_str() {
                    Some("missing" | "deleted") => Err(UsuarioError::NotFound),
                    _ => Err(UsuarioError::Unavailable),
                }
            }
            StatusCode::NOT_FOUND
            | StatusCode::UNAUTHORIZED
            | StatusCode::FORBIDDEN
            | StatusCode::TOO_MANY_REQUESTS
            | StatusCode::SERVICE_UNAVAILABLE
            | StatusCode::GATEWAY_TIMEOUT => Err(UsuarioError::Unavailable),
            _ => Err(UsuarioError::Upstream),
        }
    }
    async fn decode<T: DeserializeOwned>(response: Response) -> Result<T, UsuarioError> {
        response.json().await.map_err(|e| {
            tracing::error!(
                modulo = "usuarios",
                etapa = "json",
                "Respuesta CouchDB incompatible"
            );
            if e.is_timeout() {
                UsuarioError::Unavailable
            } else {
                UsuarioError::Upstream
            }
        })
    }
    pub async fn get(&self, id: &str) -> Result<UsuarioDocumento, UsuarioError> {
        let response = Self::send(self.request(Method::GET, id), true).await?;
        let document: UsuarioDocumento = Self::decode(response).await?;
        if document.id != id || document.rev.as_deref().is_none_or(str::is_empty) {
            return Err(UsuarioError::Upstream);
        }
        Ok(document)
    }
    pub async fn by_email(&self, email: &str) -> Result<Option<UsuarioDocumento>, UsuarioError> {
        // Mango también detecta documentos antiguos con ID distinto; requiere correo canónico.
        let response = Self::send(
            self.request(Method::POST, "_find").json(&json!({
                "selector": {"correo": {"$eq": email}}, "limit": 2,
                "use_index": ["usuarios-correo", "por-correo"]
            })),
            false,
        )
        .await?;
        let mut result: FindResponse = Self::decode(response).await?;
        if result.docs.len() > 1 {
            return Err(UsuarioError::Upstream);
        }
        let document = result.docs.pop();
        if document.as_ref().is_some_and(|d| {
            d.correo != email || d.id.is_empty() || d.rev.as_deref().is_none_or(str::is_empty)
        }) {
            return Err(UsuarioError::Upstream);
        }
        Ok(document)
    }
    pub async fn save(
        &self,
        mut document: UsuarioDocumento,
    ) -> Result<UsuarioDocumento, UsuarioError> {
        let creating = document.rev.is_none();
        let response = Self::send(
            self.request(Method::PUT, &document.id).json(&document),
            false,
        )
        .await
        .map_err(|e| {
            if creating && matches!(e, UsuarioError::Conflict) {
                UsuarioError::Duplicate
            } else {
                e
            }
        })?;
        let result: WriteResponse = Self::decode(response).await?;
        if !result.ok || result.id != document.id || result.rev.is_empty() {
            return Err(UsuarioError::Upstream);
        }
        document.rev = Some(result.rev);
        Ok(document)
    }
}
