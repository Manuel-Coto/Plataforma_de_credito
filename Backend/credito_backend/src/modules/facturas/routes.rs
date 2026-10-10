use axum::{
    extract::FromRef,
    routing::{get, patch, post},
    Router,
};

use crate::modules::usuarios::service::UsuarioService;

use super::{handler, service::FacturaService};

#[derive(Clone)]
pub struct FacturaState {
    facturas: FacturaService,
    usuarios: UsuarioService,
}

impl FromRef<FacturaState> for FacturaService {
    fn from_ref(state: &FacturaState) -> Self {
        state.facturas.clone()
    }
}

impl FromRef<FacturaState> for UsuarioService {
    fn from_ref(state: &FacturaState) -> Self {
        state.usuarios.clone()
    }
}

pub fn router(
    facturas: FacturaService,
    usuarios: UsuarioService,
) -> Router {
    Router::new()
        .route(
            "/api/facturas",
            post(handler::create).get(handler::list),
        )
        .route(
            "/api/facturas/{id}",
            get(handler::get),
        )
        .route(
            "/api/facturas/{id}/verificar-dte",
            patch(handler::verify_dte),
        )
        .with_state(FacturaState {
            facturas,
            usuarios,
        })
}