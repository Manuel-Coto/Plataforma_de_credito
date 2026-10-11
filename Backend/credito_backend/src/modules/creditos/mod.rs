pub mod handler;
pub mod model;
pub mod repository;
pub mod routes;
pub mod service;

use axum::{http::StatusCode, response::IntoResponse, Json};
use serde_json::json;

#[derive(Debug)]
pub enum CreditoError {
    Invalid(&'static str),
    Forbidden,
    NotFound,
    Conflict,
    Unavailable,
    Upstream,
}

impl IntoResponse for CreditoError {
    fn into_response(self) -> axum::response::Response {
        let (status, message) = match self {
            Self::Invalid(message) => (StatusCode::BAD_REQUEST, message),
            Self::Forbidden => (StatusCode::FORBIDDEN, "Permisos insuficientes"),
            Self::NotFound => (
                StatusCode::NOT_FOUND,
                "Crédito o documento relacionado inexistente",
            ),
            Self::Conflict => (
                StatusCode::CONFLICT,
                "La operación cambió o su estado no permite esta solicitud; consulte y reintente",
            ),
            Self::Unavailable => (
                StatusCode::SERVICE_UNAVAILABLE,
                "Servicio de créditos no disponible",
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
