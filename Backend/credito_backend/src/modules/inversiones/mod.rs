pub mod handler;
pub mod model;
pub mod repository;
pub mod routes;
pub mod service;

use axum::{http::StatusCode, response::IntoResponse, Json};
use serde_json::json;

#[derive(Debug)]
pub enum InversionError {
    Invalid(&'static str),
    Forbidden,
    NotFound,
    Conflict,
    Unavailable,
    Upstream,
    IndexUnavailable,
}

impl IntoResponse for InversionError {
    fn into_response(self) -> axum::response::Response {
        let (status, message) = match self {
            Self::Invalid(message) => (StatusCode::BAD_REQUEST, message),
            Self::Forbidden => (StatusCode::FORBIDDEN, "Permisos insuficientes"),
            Self::NotFound => (
                StatusCode::NOT_FOUND,
                "Oferta, inversión o factura inexistente",
            ),
            Self::Conflict => (
                StatusCode::CONFLICT,
                "La oferta cambió o ya no admite inversiones",
            ),
            Self::Unavailable => (
                StatusCode::SERVICE_UNAVAILABLE,
                "Servicio de inversiones no disponible",
            ),
            Self::Upstream => (
                StatusCode::BAD_GATEWAY,
                "Respuesta inválida de la base de datos",
            ),
            Self::IndexUnavailable => (
                StatusCode::SERVICE_UNAVAILABLE,
                "Falta un índice Mango de inversiones",
            ),
        };

        (status, Json(json!({ "error": message }))).into_response()
    }
}
