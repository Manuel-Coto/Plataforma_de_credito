use axum::{routing::get, Json, Router};
use serde_json::{json, Value};

mod database;
mod modules;

use modules::{
    empresas::{repository::EmpresaRepository, routes as empresa_routes, service::EmpresaService},
    facturas::{repository::FacturaRepository, routes as factura_routes, service::FacturaService},
    inversiones::{
        repository::InversionRepository, routes as inversion_routes, service::InversionService,
    },
    usuarios::{routes as usuario_routes, service::UsuarioService},
};

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
            tracing::warn!(
                %error,
                "Inicialización CouchDB incompleta"
            );
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
    let usuarios = match db {
        Some(db) => UsuarioService::from_connection(db).await,
        None => Ok(UsuarioService::disabled()),
    }
    .unwrap_or_else(|_| {
        tracing::warn!("Usuarios no configurado; revisar CouchDB y JWT_SECRET");
        UsuarioService::disabled()
    });

    let empresas_repo = db
        .map(EmpresaRepository::from_connection)
        .transpose()
        .unwrap_or_else(|_| {
            tracing::warn!("Repositorio de empresas no disponible");
            None
        });

    let facturas_repo = db
        .map(FacturaRepository::from_connection)
        .transpose()
        .unwrap_or_else(|_| {
            tracing::warn!("Repositorio de facturas no disponible");
            None
        });

    let inversiones_repo = db
        .map(InversionRepository::from_connection)
        .transpose()
        .unwrap_or_else(|_| {
            tracing::warn!("Repositorio de inversiones no disponible");
            None
        });

    Router::new()
        .route("/api/health", get(health))
        .merge(empresa_routes::router(
            EmpresaService::new(empresas_repo),
            usuarios.clone(),
        ))
        .merge(usuario_routes::router(usuarios.clone()))
        .merge(factura_routes::router(
            FacturaService::new(facturas_repo),
            usuarios.clone(),
        ))
        .merge(inversion_routes::router(
            InversionService::new(inversiones_repo),
            usuarios,
        ))
}
