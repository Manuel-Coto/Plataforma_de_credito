use axum::{
    extract::FromRef,
    routing::post,
    Router,
};

use crate::modules::usuarios::service::UsuarioService;

use super::{handler, service::InversionService};

#[derive(Clone)]
pub struct InversionState {
    inversiones: InversionService,
    usuarios: UsuarioService,
}

impl FromRef<InversionState> for InversionService {
    fn from_ref(state: &InversionState) -> Self {
        state.inversiones.clone()
    }
}

impl FromRef<InversionState> for UsuarioService {
    fn from_ref(state: &InversionState) -> Self {
        state.usuarios.clone()
    }
}

pub fn router(inversiones: InversionService, usuarios: UsuarioService) -> Router {
    Router::new()
        .route(
            "/api/ofertas",
            post(handler::crear_oferta).get(handler::listar_ofertas),
        )
        .route(
            "/api/inversiones",
            post(handler::invertir).get(handler::listar_mis_inversiones),
        )
        .with_state(InversionState {
            inversiones,
            usuarios,
        })
}
