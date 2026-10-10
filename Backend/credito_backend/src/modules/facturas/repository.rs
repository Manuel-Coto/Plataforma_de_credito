use reqwest::{Client, Method, StatusCode, Url};
use serde::Deserialize;
use serde_json::{json, Value};
use super::{model::FacturaDocumento, FacturaError};

#[derive(Clone)]
pub struct FacturaRepository { client: Client, url: Url, empresas_url: Url, username: String, password: String }
#[derive(Deserialize)] struct WriteResponse { ok: bool, id: String, rev: String }
#[derive(Deserialize)] struct FindResponse { docs: Vec<FacturaDocumento>, #[serde(default)] bookmark: String }
impl FacturaRepository {
    pub fn from_connection(db: &crate::database::connection::CouchDb) -> Result<Self, FacturaError> {
        let mut url = Url::parse(&db.url).map_err(|_| FacturaError::Configuration)?;
        url.path_segments_mut().map_err(|_| FacturaError::Configuration)?.pop_if_empty().push("facturas");
        let mut empresas_url = Url::parse(&db.url).map_err(|_| FacturaError::Configuration)?;
        empresas_url.path_segments_mut().map_err(|_| FacturaError::Configuration)?.pop_if_empty().push("empresas");
        Ok(Self { client: db.client.clone(), url, empresas_url, username: db.username.clone(), password: db.password.clone() })
    }
    fn request(&self, method: Method, id: Option<&str>) -> reqwest::RequestBuilder {
        let mut url = self.url.clone();
        if let Some(id) = id { url.path_segments_mut().expect("URL validada").push(id); }
        self.client.request(method, url).basic_auth(&self.username, Some(&self.password))
    }
    async fn map_error(response: reqwest::Response, lookup: bool) -> FacturaError {
        match response.status() {
            StatusCode::CONFLICT => FacturaError::Conflict,
            StatusCode::NOT_FOUND if lookup => FacturaError::NotFound,
            StatusCode::NOT_FOUND | StatusCode::TOO_MANY_REQUESTS | StatusCode::SERVICE_UNAVAILABLE | StatusCode::GATEWAY_TIMEOUT => FacturaError::Unavailable,
            StatusCode::BAD_REQUEST => {
                let body: Value = response.json().await.unwrap_or(Value::Null);
                if body["error"] == "no_usable_index" { FacturaError::IndexUnavailable } else { FacturaError::Upstream }
            }
            StatusCode::UNAUTHORIZED | StatusCode::FORBIDDEN => FacturaError::Configuration,
            _ => FacturaError::Upstream,
        }
    }
    pub async fn get_empresa(&self, id: &str) -> Result<Value, FacturaError> {
        let mut url = self.empresas_url.clone();
        url.path_segments_mut().expect("URL validada").push(id);
        let r = self.client.get(url).basic_auth(&self.username, Some(&self.password)).send().await.map_err(|_| FacturaError::Unavailable)?;
        if !r.status().is_success() { return Err(Self::map_error(r, true).await); }
        r.json().await.map_err(|_| FacturaError::Upstream)
    }
    pub async fn get(&self, id: &str) -> Result<FacturaDocumento, FacturaError> {
        let r = self.request(Method::GET, Some(id)).send().await.map_err(|_| FacturaError::Unavailable)?;
        if !r.status().is_success() { return Err(Self::map_error(r, true).await); }
        r.json().await.map_err(|_| FacturaError::Upstream)
    }
    pub async fn save(&self, mut doc: FacturaDocumento) -> Result<FacturaDocumento, FacturaError> {
        let id = doc.id.clone().ok_or(FacturaError::Invalid("Falta el identificador de factura"))?;
        let r = self.request(Method::PUT, Some(&id)).json(&doc).send().await.map_err(|_| FacturaError::Unavailable)?;
        if !r.status().is_success() { return Err(Self::map_error(r, false).await); }
        let w: WriteResponse = r.json().await.map_err(|_| FacturaError::Upstream)?;
        if !w.ok { return Err(FacturaError::Upstream); }
        doc.id = Some(w.id); doc.rev = Some(w.rev); Ok(doc)
    }
    pub async fn dte_exists(&self, codigo: &str) -> Result<bool, FacturaError> {
        let mut find_url = self.url.clone();
        find_url.path_segments_mut().map_err(|_| FacturaError::Configuration)?.push("_find");
        let r = self.client.post(find_url).basic_auth(&self.username, Some(&self.password))
            .json(&json!({"selector":{"tipo":"factura","dte.codigo_generacion":codigo},"limit":1,"fields":["_id"]})).send().await.map_err(|_| FacturaError::Unavailable)?;
        if !r.status().is_success() { return Err(Self::map_error(r, false).await); }
        let body: Value = r.json().await.map_err(|_| FacturaError::Upstream)?;
        Ok(body["docs"].as_array().is_some_and(|a| !a.is_empty()))
    }
    pub async fn list(&self, limit: u32, bookmark: Option<String>, estado: Option<super::model::EstadoFactura>, owner: Option<&str>) -> Result<(Vec<FacturaDocumento>, String), FacturaError> {
        let mut selector = json!({"tipo":"factura"});
        if let Some(owner) = owner { selector["creado_por"] = json!(owner); }
        if let Some(estado) = estado { selector["estado"] = serde_json::to_value(estado).map_err(|_| FacturaError::Upstream)?; }
        let mut body = json!({"selector":selector,"limit":limit});
        if let Some(b) = bookmark { body["bookmark"] = json!(b); }
        let mut url = self.url.clone();
        url.path_segments_mut().map_err(|_| FacturaError::Configuration)?.push("_find");
        let r = self.client.post(url).basic_auth(&self.username, Some(&self.password)).json(&body).send().await.map_err(|_| FacturaError::Unavailable)?;
        if !r.status().is_success() { return Err(Self::map_error(r, false).await); }
        let found: FindResponse = r.json().await.map_err(|_| FacturaError::Upstream)?;
        Ok((found.docs, found.bookmark))
    }
}
