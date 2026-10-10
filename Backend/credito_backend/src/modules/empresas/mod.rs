pub mod handler;
pub mod model;
pub mod repository;
pub mod routes;
pub mod service;

use axum::{http::StatusCode, response::IntoResponse, Json};
use serde_json::json;

#[derive(Debug)]
pub enum EmpresaError {
    Invalid(&'static str),
    Forbidden,
    NotFound,
    Duplicate,
    Conflict,
    Configuration,
    Unavailable,
    IndexUnavailable,
    Upstream,
}

impl IntoResponse for EmpresaError {
    fn into_response(self) -> axum::response::Response {
        let (status, message) = match self {
            Self::Invalid(message) => (StatusCode::BAD_REQUEST, message),
            Self::Forbidden => (StatusCode::FORBIDDEN, "Permisos insuficientes"),
            Self::NotFound => (StatusCode::NOT_FOUND, "Empresa inexistente"),
            Self::Duplicate => (StatusCode::CONFLICT, "Ya existe una empresa con ese NIT"),
            Self::Conflict => (
                StatusCode::CONFLICT,
                "Conflicto de revisión; consulte la empresa y reintente",
            ),
            Self::Configuration => (
                StatusCode::SERVICE_UNAVAILABLE,
                "Servicio de empresas no configurado",
            ),
            Self::Unavailable => (
                StatusCode::SERVICE_UNAVAILABLE,
                "Base de datos no disponible",
            ),
            Self::IndexUnavailable => (
                StatusCode::SERVICE_UNAVAILABLE,
                "Índice Mango de empresas no disponible; revise empresas-nit/por-nit y empresas-responsable/por-responsable",
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
