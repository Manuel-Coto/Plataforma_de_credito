use super::{handler, service::CreditoService};
use crate::modules::usuarios::service::UsuarioService;
use axum::{
    extract::{DefaultBodyLimit, FromRef},
    routing::{get, post},
    Router,
};

#[derive(Clone)]
pub struct CreditoState {
    creditos: CreditoService,
    usuarios: UsuarioService,
}

impl FromRef<CreditoState> for CreditoService {
    fn from_ref(state: &CreditoState) -> Self {
        state.creditos.clone()
    }
}
impl FromRef<CreditoState> for UsuarioService {
    fn from_ref(state: &CreditoState) -> Self {
        state.usuarios.clone()
    }
}

pub fn router(creditos: CreditoService, usuarios: UsuarioService) -> Router {
    Router::new()
        .route("/api/creditos", get(handler::list).post(handler::create))
        .route(
            "/api/creditos/aportes/{id}/confirmar",
            post(handler::confirmar_aporte),
        )
        .route("/api/creditos/{id}", get(handler::get))
        .route("/api/creditos/{id}/pagos", post(handler::pagar))
        .route("/api/creditos/{id}/sincronizar", post(handler::sincronizar))
        .layer(DefaultBodyLimit::max(16 * 1024))
        .with_state(CreditoState { creditos, usuarios })
}
