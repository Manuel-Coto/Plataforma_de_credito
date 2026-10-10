pub mod auth;
pub mod handler;
pub mod model;
pub mod repository;
pub mod routes;
pub mod service;

use axum::{
    http::{header, StatusCode},
    response::{IntoResponse, Response},
    Json,
};
use serde_json::json;

#[derive(Debug)]
pub enum UsuarioError {
    Invalid(&'static str),
    Credentials,
    Unauthorized,
    Forbidden,
    Duplicate,
    NotFound,
    Conflict,
    Unavailable,
    Upstream,
    Internal,
    RateLimited,
}

impl IntoResponse for UsuarioError {
    fn into_response(self) -> Response {
        let (status, message) = match &self {
            Self::Invalid(message) => (StatusCode::BAD_REQUEST, *message),
            Self::Credentials => (StatusCode::UNAUTHORIZED, "Credenciales incorrectas"),
            Self::Unauthorized => (
                StatusCode::UNAUTHORIZED,
                "Autenticación requerida o token inválido",
            ),
            Self::Forbidden => (StatusCode::FORBIDDEN, "Permisos insuficientes"),
            Self::Duplicate => (StatusCode::CONFLICT, "Correo ya registrado"),
            Self::NotFound => (StatusCode::NOT_FOUND, "Usuario inexistente"),
            Self::Conflict => (
                StatusCode::CONFLICT,
                "Conflicto de revisión; consulte su perfil y reintente",
            ),
            Self::Unavailable => (
                StatusCode::SERVICE_UNAVAILABLE,
                "Servicio de usuarios no disponible",
            ),
            Self::Upstream => (
                StatusCode::BAD_GATEWAY,
                "Respuesta inválida de la base de usuarios",
            ),
            Self::Internal => (
                StatusCode::INTERNAL_SERVER_ERROR,
                "Error interno del servicio de usuarios",
            ),
            Self::RateLimited => (
                StatusCode::TOO_MANY_REQUESTS,
                "Demasiados intentos; reintente en 60 segundos",
            ),
        };
        let mut response = (status, Json(json!({"error": message}))).into_response();
        response
            .headers_mut()
            .insert(header::CACHE_CONTROL, "no-store".parse().unwrap());
        if status == StatusCode::UNAUTHORIZED {
            response
                .headers_mut()
                .insert(header::WWW_AUTHENTICATE, "Bearer".parse().unwrap());
        }
        if matches!(self, Self::RateLimited) {
            response
                .headers_mut()
                .insert(header::RETRY_AFTER, "60".parse().unwrap());
        }
        response
    }
}

#[cfg(test)]
mod tests;
