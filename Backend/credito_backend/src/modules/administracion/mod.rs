pub mod handler;
pub mod model;
pub mod repository;
pub mod routes;
pub mod service;

use axum::{http::StatusCode, response::IntoResponse, Json};
use serde_json::json;

#[derive(Debug)]
pub enum AdministracionError {
    Invalid(&'static str),
    Forbidden,
    Configuration,
    Unavailable,
    Upstream,
}

impl IntoResponse for AdministracionError {
    fn into_response(self) -> axum::response::Response {
        let (status, message) = match self {
            Self::Invalid(message) => (StatusCode::BAD_REQUEST, message),
            Self::Forbidden => (StatusCode::FORBIDDEN, "Permisos insuficientes"),
            Self::Configuration => (
                StatusCode::SERVICE_UNAVAILABLE,
                "Servicio de administración no configurado",
            ),
            Self::Unavailable => (
                StatusCode::SERVICE_UNAVAILABLE,
                "Base de datos no disponible",
            ),
            Self::Upstream => (
                StatusCode::BAD_GATEWAY,
                "Respuesta inválida de la base de datos",
            ),
        };
        (status, Json(json!({"error": message}))).into_response()
    }
}

#[cfg(test)]
mod tests;
