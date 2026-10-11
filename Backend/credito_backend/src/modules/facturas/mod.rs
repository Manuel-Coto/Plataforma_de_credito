pub mod handler;
pub mod model;
pub mod repository;
pub mod routes;
pub mod service;

use axum::{http::StatusCode, response::IntoResponse, Json};
use serde_json::json;

#[derive(Debug)]
pub enum FacturaError {
    Invalid(&'static str),
    Forbidden,
    NotFound,
    Duplicate,
    Conflict,
    Configuration,
    Unavailable,
    Upstream,
    IndexUnavailable,
}

impl IntoResponse for FacturaError {
    fn into_response(self) -> axum::response::Response {
        let (status, message) = match self {
            Self::Invalid(m) => (StatusCode::BAD_REQUEST, m),
            Self::Forbidden => (StatusCode::FORBIDDEN, "Permisos insuficientes"),
            Self::NotFound => (StatusCode::NOT_FOUND, "Factura inexistente"),
            Self::Duplicate => (
                StatusCode::CONFLICT,
                "Ya existe una factura con ese DTE o número",
            ),
            Self::Conflict => (
                StatusCode::CONFLICT,
                "La factura cambió o ya fue verificada",
            ),
            Self::Configuration | Self::Unavailable => (
                StatusCode::SERVICE_UNAVAILABLE,
                "Servicio de facturas no disponible",
            ),
            Self::Upstream => (
                StatusCode::BAD_GATEWAY,
                "Respuesta inválida de la base de datos",
            ),
            Self::IndexUnavailable => (
                StatusCode::SERVICE_UNAVAILABLE,
                "Falta un índice Mango de facturas",
            ),
        };

        (status, Json(json!({ "error": message }))).into_response()
    }
}
