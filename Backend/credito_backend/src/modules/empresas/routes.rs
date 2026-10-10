use axum::{
    extract::FromRef,
    routing::{get, patch},
    Router,
};

use super::{handler, service::EmpresaService};
use crate::modules::usuarios::service::UsuarioService;

#[derive(Clone)]
pub struct EmpresaState {
    empresas: EmpresaService,
    usuarios: UsuarioService,
}

impl FromRef<EmpresaState> for EmpresaService {
    fn from_ref(state: &EmpresaState) -> Self {
        state.empresas.clone()
    }
}

impl FromRef<EmpresaState> for UsuarioService {
    fn from_ref(state: &EmpresaState) -> Self {
        state.usuarios.clone()
    }
}

pub fn router(service: EmpresaService, usuarios: UsuarioService) -> Router {
    Router::new()
        .route("/api/empresas", get(handler::list).post(handler::create))
        .route("/api/empresas/{id}", get(handler::get).put(handler::update))
        .route("/api/empresas/{id}/desactivar", patch(handler::deactivate))
        .with_state(EmpresaState {
            empresas: service,
            usuarios,
        })
}
