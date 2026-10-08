use axum::{routing::get, Json, Router};
use serde_json::{json, Value};

async fn health() -> Json<Value> {
    Json(json!({"estado": "activo", "mensaje": "Backend Rust funcionando"}))
}

#[tokio::main]
async fn main() {
    let app = Router::new().route("/api/health", get(health));
    let listener = tokio::net::TcpListener::bind("127.0.0.1:3000")
        .await
        .expect("No se pudo iniciar el servidor");
    println!("API en http://127.0.0.1:3000");
    axum::serve(listener, app).await.expect("Fallo de servidor");
}
