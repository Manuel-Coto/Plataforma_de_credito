use super::{handler, service::UsuarioService};
use axum::{
    extract::DefaultBodyLimit,
    extract::Request,
    http::{header, HeaderValue},
    middleware::{self, Next},
    response::Response,
    routing::{get, post},
    Router,
};

async fn no_store(request: Request, next: Next) -> Response {
    let mut response = next.run(request).await;
    response
        .headers_mut()
        .insert(header::CACHE_CONTROL, HeaderValue::from_static("no-store"));
    response
}
pub fn router(service: UsuarioService) -> Router {
    Router::new()
        .route("/api/auth/register", post(handler::register))
        .route("/api/auth/login", post(handler::login))
        .route("/api/usuarios/me", get(handler::me).put(handler::update))
        .layer(DefaultBodyLimit::max(16 * 1024))
        .layer(middleware::from_fn(no_store))
        .with_state(service)
}
