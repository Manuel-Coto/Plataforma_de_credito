use axum::{extract::FromRef, routing::get, Router};

use super::{handler, service::AdministracionService};
use crate::modules::usuarios::service::UsuarioService;

#[derive(Clone)]
pub struct AdministracionState {
    administracion: AdministracionService,
    usuarios: UsuarioService,
}

impl FromRef<AdministracionState> for AdministracionService {
    fn from_ref(state: &AdministracionState) -> Self {
        state.administracion.clone()
    }
}

impl FromRef<AdministracionState> for UsuarioService {
    fn from_ref(state: &AdministracionState) -> Self {
        state.usuarios.clone()
    }
}

pub fn router(service: AdministracionService, usuarios: UsuarioService) -> Router {
    Router::new()
        .route("/api/administracion/resumen", get(handler::resumen))
        .route("/api/administracion/reportes", get(handler::reporte))
        .route("/api/administracion/auditoria", get(handler::auditoria))
        .with_state(AdministracionState {
            administracion: service,
            usuarios,
        })
}
