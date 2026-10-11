use std::collections::HashSet;

use reqwest::{Client, StatusCode, Url};
use serde::Deserialize;
use serde_json::{json, Value};

use super::{
    model::{AuditoriaQuery, Modulo},
    AdministracionError,
};
use crate::database::connection::CouchDb;

const REPORT_PAGE_SIZE: u32 = 100;

#[derive(Clone)]
pub struct AdministracionRepository {
    client: Client,
    root_url: Url,
    username: String,
    password: String,
}

#[derive(Deserialize)]
pub(super) struct FindResponse {
    pub docs: Vec<Value>,
    pub bookmark: String,
}

impl AdministracionRepository {
    pub fn from_connection(db: &CouchDb) -> Result<Self, AdministracionError> {
        let root_url = Url::parse(&db.url).map_err(|_| AdministracionError::Configuration)?;
        if !matches!(root_url.scheme(), "http" | "https")
            || root_url.host_str().is_none()
            || !root_url.username().is_empty()
            || root_url.password().is_some()
            || root_url.query().is_some()
            || root_url.fragment().is_some()
            || db.username.trim().is_empty()
            || db.password.is_empty()
        {
            return Err(AdministracionError::Configuration);
        }
        Ok(Self {
            client: db.client.clone(),
            root_url,
            username: db.username.clone(),
            password: db.password.clone(),
        })
    }

    async fn find(
        &self,
        database: &str,
        query: Value,
    ) -> Result<FindResponse, AdministracionError> {
        let mut url = self.root_url.clone();
        url.path_segments_mut()
            .map_err(|_| AdministracionError::Configuration)?
            .pop_if_empty()
            .push(database)
            .push("_find");
        let response = self
            .client
            .post(url)
            .basic_auth(&self.username, Some(&self.password))
            .json(&query)
            .send()
            .await
            .map_err(|error| {
                if error.is_timeout() || error.is_connect() {
                    AdministracionError::Unavailable
                } else {
                    AdministracionError::Upstream
                }
            })?;
        match response.status() {
            StatusCode::OK => response
                .json()
                .await
                .map_err(|_| AdministracionError::Upstream),
            StatusCode::UNAUTHORIZED | StatusCode::FORBIDDEN => {
                Err(AdministracionError::Configuration)
            }
            StatusCode::NOT_FOUND
            | StatusCode::TOO_MANY_REQUESTS
            | StatusCode::SERVICE_UNAVAILABLE
            | StatusCode::GATEWAY_TIMEOUT => Err(AdministracionError::Unavailable),
            _ => Err(AdministracionError::Upstream),
        }
    }

    /// Sigue bookmarks hasta una página vacía, incluso si CouchDB devuelve páginas cortas.
    /// El callback permite agregar sin acumular los documentos completos en memoria.
    pub(super) async fn scan(
        &self,
        modulo: Modulo,
        mut consume: impl FnMut(Value) -> Result<(), AdministracionError>,
    ) -> Result<(), AdministracionError> {
        let mut query = json!({
            "selector": {"_id": {"$gte": ""}}, "limit": REPORT_PAGE_SIZE,
            "fields": ["_id", "tipo", "estado", "rol", "moneda", "monto_total_centavos", "monto_financiado_centavos", "monto_objetivo", "monto_recaudado", "monto", "capital_centavos", "interes_centavos", "total_centavos", "pagado_centavos", "fecha_vencimiento", "pagos"]
        });
        if let Some(tipo) = modulo.document_type() {
            query["selector"]["tipo"] = json!(tipo);
        }
        let mut seen = HashSet::new();
        loop {
            let page = self.find(modulo.database(), query.clone()).await?;
            if page.docs.is_empty() {
                break;
            }
            if page.bookmark.is_empty() || !seen.insert(page.bookmark.clone()) {
                return Err(AdministracionError::Upstream);
            }
            for document in page.docs {
                let id = document
                    .get("_id")
                    .and_then(Value::as_str)
                    .ok_or(AdministracionError::Upstream)?;
                if id.starts_with("_design/") {
                    continue;
                }
                if id.is_empty()
                    || modulo
                        .document_type()
                        .is_some_and(|tipo| document["tipo"] != tipo)
                {
                    return Err(AdministracionError::Upstream);
                }
                consume(document)?;
            }
            query["bookmark"] = json!(page.bookmark);
        }
        Ok(())
    }

    pub(super) async fn auditoria(
        &self,
        input: &AuditoriaQuery,
        limit: u32,
    ) -> Result<FindResponse, AdministracionError> {
        let mut query = json!({
            "selector": {"tipo": "evento"}, "limit": limit,
            "fields": ["_id", "tipo", "actor_id", "accion", "recurso_tipo", "recurso_id", "fecha", "detalles"]
        });
        if let Some(id) = &input.actor_id {
            query["selector"]["actor_id"] = json!(id);
        }
        if let Some(id) = &input.recurso_id {
            query["selector"]["recurso_id"] = json!(id);
        }
        if let Some(bookmark) = &input.bookmark {
            query["bookmark"] = json!(bookmark);
        }
        self.find("auditoria", query).await
    }
}
