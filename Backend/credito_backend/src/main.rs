use axum::{routing::get, Json, Router};
use serde_json::{json, Value};

mod database;
mod modules;

use modules::empresas::{repository::EmpresaRepository, routes, service::EmpresaService};
use modules::usuarios::{routes as usuario_routes, service::UsuarioService};

async fn health() -> Json<Value> {
    Json(json!({
        "estado": "activo",
        "mensaje": "Backend Rust funcionando"
    }))
}

#[tokio::main]
async fn main() {
    dotenvy::dotenv().ok();
    tracing_subscriber::fmt::init();
    let db = database::connection::CouchDb::new().ok();
    if let Some(db) = &db {
        if let Err(error) = database::init::inicializar_bases(db).await {
            // InitError no incluye URLs, credenciales ni cuerpos de respuesta.
            tracing::warn!(%error, "Inicialización CouchDB incompleta; revisar disponibilidad y permisos");
        }
    } else {
        tracing::warn!("Configuración CouchDB inválida o incompleta");
    }
    let app = build_app(db.as_ref()).await;
    let listener = tokio::net::TcpListener::bind("127.0.0.1:3000")
        .await
        .expect("No se pudo iniciar el servidor");
    println!("API en http://127.0.0.1:3000");
    axum::serve(listener, app).await.expect("Fallo de servidor");
}

async fn build_app(db: Option<&database::connection::CouchDb>) -> Router {
    let repository = match db.map(EmpresaRepository::from_connection).transpose() {
        Ok(repository) => repository,
        Err(_) => {
            tracing::warn!(
                "Configuración de CouchDB inválida o incompleta; Empresas responderá 503"
            );
            None
        }
    };
    let usuarios = match db {
        Some(db) => UsuarioService::from_connection(db).await,
        None => Ok(UsuarioService::disabled()),
    }
    .unwrap_or_else(|_| {
        tracing::warn!("Usuarios no configurado; revisar conexión CouchDB y JWT_SECRET");
        UsuarioService::disabled()
    });
    Router::new()
        .route("/api/health", get(health))
        .merge(routes::router(EmpresaService::new(repository)))
        .merge(usuario_routes::router(usuarios))
}
