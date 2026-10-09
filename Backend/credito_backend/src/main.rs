
mod database;

use axum::{routing::get, Json, Router};
use serde_json::{json, Value};

use database::connection::CouchDb;
use database::init::inicializar_bases;

async fn health() -> Json<Value> {
    Json(json!({
        "estado": "activo",
        "mensaje": "Backend Rust funcionando"
    }))
}

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {

    // Cargar las variables del archivo .env
    dotenvy::dotenv().ok();

    println!("Iniciando Plataforma de Credito...");

    // Crear el cliente de CouchDB
    let db = CouchDb::new()?;

    // Crear las bases de datos si no existen
    inicializar_bases(&db).await?;

    // Configurar la API REST
    let app = Router::new()
        .route("/api/health", get(health));

    let listener = tokio::net::TcpListener::bind(
        "127.0.0.1:3000"
    )
        .await?;

    println!("Servidor Rust iniciado.");
    println!("API: http://127.0.0.1:3000");

    axum::serve(listener, app).await?;

    Ok(())
}
