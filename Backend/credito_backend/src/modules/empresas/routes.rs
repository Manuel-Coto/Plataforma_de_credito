use axum::{
    routing::{get, patch},
    Router,
};

use super::{handler, service::EmpresaService};

pub fn router(service: EmpresaService) -> Router {
    Router::new()
        .route("/api/empresas", get(handler::list).post(handler::create))
        .route("/api/empresas/{id}", get(handler::get).put(handler::update))
        .route("/api/empresas/{id}/desactivar", patch(handler::deactivate))
        .with_state(service)
}
