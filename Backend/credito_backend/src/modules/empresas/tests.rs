//! Pruebas HTTP con un doble local de CouchDB: no requieren credenciales ni una BD real.
use std::{
    collections::BTreeMap,
    sync::{Arc, Mutex},
};

use axum::{
    extract::{Path, State},
    http::{HeaderMap, StatusCode},
    routing::{get, post},
    Json, Router,
};
use serde_json::{json, Value};
use tokio::task::JoinHandle;

use super::{repository::EmpresaRepository, routes, service::EmpresaService};

#[derive(Default)]
struct MockDb {
    documents: BTreeMap<String, Value>,
    requests: Vec<(String, Value)>,
    failure: Option<StatusCode>,
    malformed: bool,
    missing_index: bool,
}
type Db = Arc<Mutex<MockDb>>;
type Reply = (StatusCode, Json<Value>);

fn failure(db: &MockDb, headers: &HeaderMap) -> Option<Reply> {
    assert_eq!(headers.get("authorization").unwrap(), "Basic dGVzdDp0ZXN0");
    if db.malformed {
        return Some((StatusCode::OK, Json(json!({"unexpected": true}))));
    }
    db.failure.map(|status| {
        (
            status,
            Json(json!({"error": "internal", "reason": "secret-password"})),
        )
    })
}

async fn find(State(state): State<Db>, headers: HeaderMap, Json(query): Json<Value>) -> Reply {
    let mut db = state.lock().unwrap();
    db.requests.push(("find".into(), query.clone()));
    if let Some(reply) = failure(&db, &headers) {
        return reply;
    }
    if db.missing_index && query.get("sort").is_some() {
        return (
            StatusCode::BAD_REQUEST,
            Json(json!({"error": "no_usable_index", "reason": "secret-password"})),
        );
    }
    let nit = query["selector"]["nit"]["$eq"].as_str();
    let except = query["selector"]["_id"]["$ne"].as_str();
    let offset = query["bookmark"]
        .as_str()
        .and_then(|b| b.parse::<usize>().ok())
        .unwrap_or(0);
    let limit = query["limit"].as_u64().unwrap() as usize;
    let docs: Vec<_> = db
        .documents
        .values()
        .filter(|d| nit.is_none_or(|nit| d["nit"] == nit) && except.is_none_or(|id| d["_id"] != id))
        .skip(offset)
        .take(limit)
        .cloned()
        .collect();
    (
        StatusCode::OK,
        Json(json!({"bookmark": (offset + docs.len()).to_string(), "docs": docs})),
    )
}

async fn create(
    State(state): State<Db>,
    headers: HeaderMap,
    Json(mut value): Json<Value>,
) -> Reply {
    let mut db = state.lock().unwrap();
    db.requests.push(("create".into(), value.clone()));
    if let Some(reply) = failure(&db, &headers) {
        return reply;
    }
    assert!(value.get("_id").is_none());
    assert!(value.get("_rev").is_none());
    let id = format!("empresa-{}", db.documents.len() + 1);
    value["_id"] = json!(id);
    value["_rev"] = json!("1-test");
    db.documents.insert(id.clone(), value);
    (
        StatusCode::CREATED,
        Json(json!({"ok": true, "id": id, "rev": "1-test"})),
    )
}

async fn read(State(state): State<Db>, Path(id): Path<String>, headers: HeaderMap) -> Reply {
    let db = state.lock().unwrap();
    if let Some(reply) = failure(&db, &headers) {
        return reply;
    }
    match db.documents.get(&id) {
        Some(value) => (StatusCode::OK, Json(value.clone())),
        None => (
            StatusCode::NOT_FOUND,
            Json(json!({"error": "not_found", "reason": "missing"})),
        ),
    }
}

async fn update(
    State(state): State<Db>,
    Path(id): Path<String>,
    headers: HeaderMap,
    Json(mut value): Json<Value>,
) -> Reply {
    let mut db = state.lock().unwrap();
    db.requests.push(("update".into(), value.clone()));
    if let Some(reply) = failure(&db, &headers) {
        return reply;
    }
    let Some(old) = db.documents.get(&id) else {
        return (
            StatusCode::NOT_FOUND,
            Json(json!({"error": "not_found", "reason": "missing"})),
        );
    };
    assert_eq!(value["_id"], id);
    if value["_rev"] != old["_rev"] {
        return (StatusCode::CONFLICT, Json(json!({"error": "conflict"})));
    }
    let rev = format!(
        "{}-test",
        old["_rev"]
            .as_str()
            .unwrap()
            .split('-')
            .next()
            .unwrap()
            .parse::<u32>()
            .unwrap()
            + 1
    );
    value["_rev"] = json!(rev);
    db.documents.insert(id.clone(), value);
    (
        StatusCode::CREATED,
        Json(json!({"ok": true, "id": id, "rev": rev})),
    )
}

struct RunningServer {
    url: String,
    task: JoinHandle<()>,
}
impl Drop for RunningServer {
    fn drop(&mut self) {
        self.task.abort();
    }
}
async fn serve(app: Router) -> RunningServer {
    let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
    let url = format!("http://{}", listener.local_addr().unwrap());
    let task = tokio::spawn(async move {
        axum::serve(listener, app).await.unwrap();
    });
    RunningServer { url, task }
}

async fn setup() -> (RunningServer, RunningServer, Db) {
    let db = Db::default();
    let couch = serve(
        Router::new()
            .route("/empresas", post(create))
            .route("/empresas/_find", post(find))
            .route("/empresas/{id}", get(read).put(update))
            .with_state(db.clone()),
    )
    .await;
    let repository = EmpresaRepository::new(&couch.url, "test".into(), "test".into()).unwrap();
    let api = serve(
        Router::new()
            .route("/api/health", get(crate::health))
            .merge(routes::router(EmpresaService::new(Some(repository)))),
    )
    .await;
    (api, couch, db)
}

fn input(nit: &str) -> Value {
    json!({"nombre": " Empresa ficticia ", "nit": nit, "correo": "contacto@example.test",
        "telefono": "0000-0000", "direccion": "Dirección ficticia"})
}

#[tokio::test]
async fn complete_lifecycle_and_sequential_duplicates() {
    let (api, _couch, db) = setup().await;
    let client = reqwest::Client::new();
    let collection = format!("{}/api/empresas", api.url);
    assert_eq!(
        client
            .get(format!("{}/api/health", api.url))
            .send()
            .await
            .unwrap()
            .status(),
        StatusCode::OK
    );
    let created = client
        .post(&collection)
        .json(&input(" NIT-TEST-1 "))
        .send()
        .await
        .unwrap();
    assert_eq!(created.status(), StatusCode::CREATED);
    let created: Value = created.json().await.unwrap();
    assert_eq!(created["estado"], "pendiente");
    assert_eq!(created["nit"], "NIT-TEST-1");
    assert!(created["fecha_creacion"].as_str().is_some());
    assert!(created.get("_rev").is_none());
    assert!(created.get("_id").is_none());
    let url = format!("{collection}/{}", created["id"].as_str().unwrap());
    let read: Value = client.get(&url).send().await.unwrap().json().await.unwrap();
    assert_eq!(read, created);
    assert_eq!(
        client
            .post(&collection)
            .json(&input("NIT-TEST-1"))
            .send()
            .await
            .unwrap()
            .status(),
        StatusCode::CONFLICT
    );
    let mut body = input("NIT-TEST-1");
    body["nombre"] = json!("Empresa ficticia actualizada");
    let response = client.put(&url).json(&body).send().await.unwrap();
    assert_eq!(response.status(), StatusCode::OK);
    let updated: Value = response.json().await.unwrap();
    assert_eq!(updated["nombre"], body["nombre"]);
    assert_eq!(updated["fecha_creacion"], created["fecha_creacion"]);
    assert_eq!(updated["estado"], "pendiente");
    assert_eq!(
        client
            .post(&collection)
            .json(&input("NIT-TEST-2"))
            .send()
            .await
            .unwrap()
            .status(),
        StatusCode::CREATED
    );
    assert_eq!(
        client
            .put(&url)
            .json(&input("NIT-TEST-2"))
            .send()
            .await
            .unwrap()
            .status(),
        StatusCode::CONFLICT
    );
    let first: Value = client
        .get(format!("{collection}?limit=1"))
        .send()
        .await
        .unwrap()
        .json()
        .await
        .unwrap();
    assert_eq!(first["empresas"].as_array().unwrap().len(), 1);
    let second: Value = client
        .get(&collection)
        .query(&[
            ("limit", "1"),
            ("bookmark", first["bookmark"].as_str().unwrap()),
        ])
        .send()
        .await
        .unwrap()
        .json()
        .await
        .unwrap();
    assert_ne!(first["empresas"][0]["id"], second["empresas"][0]["id"]);
    let response = client
        .patch(format!("{url}/desactivar"))
        .send()
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::OK);
    let inactive: Value = response.json().await.unwrap();
    assert_eq!(inactive["estado"], "inactiva");
    let again: Value = client
        .patch(format!("{url}/desactivar"))
        .send()
        .await
        .unwrap()
        .json()
        .await
        .unwrap();
    assert_eq!(again, inactive);
    assert_eq!(
        client
            .post(&collection)
            .json(&input("NIT-TEST-1"))
            .send()
            .await
            .unwrap()
            .status(),
        StatusCode::CONFLICT
    );
    assert_eq!(
        client
            .get(format!("{collection}/inexistente"))
            .send()
            .await
            .unwrap()
            .status(),
        StatusCode::NOT_FOUND
    );
    let db = db.lock().unwrap();
    assert_eq!(db.documents.len(), 2);
    assert!(db.documents.values().all(|d| d.get("_deleted").is_none()));
    assert_eq!(
        db.requests
            .iter()
            .filter(|(method, _)| method == "update")
            .count(),
        2
    );
    assert!(db
        .requests
        .iter()
        .filter(|(method, _)| method == "find")
        .all(|(_, q)| q["limit"].as_u64().unwrap() <= 100));
}

#[tokio::test]
async fn invalid_bodies_states_and_pagination_never_access_database() {
    let (api, _couch, db) = setup().await;
    let client = reqwest::Client::new();
    let url = format!("{}/api/empresas", api.url);
    for (field, value) in [
        ("estado", "activa"),
        ("estado", "inventado"),
        ("_rev", "1-test"),
        ("id", "falso"),
        ("fecha_creacion", "falsa"),
        ("nombre", "  "),
        ("nit", " "),
        ("correo", "incorrecto"),
    ] {
        let mut body = input("NIT-TEST");
        body[field] = json!(value);
        assert_eq!(
            client.post(&url).json(&body).send().await.unwrap().status(),
            StatusCode::BAD_REQUEST
        );
        assert_eq!(
            client
                .put(format!("{url}/empresa_prueba_001"))
                .json(&body)
                .send()
                .await
                .unwrap()
                .status(),
            StatusCode::BAD_REQUEST
        );
    }
    assert_eq!(
        client
            .post(&url)
            .header("content-type", "application/json")
            .body("{")
            .send()
            .await
            .unwrap()
            .status(),
        StatusCode::BAD_REQUEST
    );
    assert_eq!(
        client
            .post(&url)
            .json(&json!({}))
            .send()
            .await
            .unwrap()
            .status(),
        StatusCode::BAD_REQUEST
    );
    for query in [
        "limit=0",
        "limit=101",
        "limit=no",
        "limit=-1",
        "desconocido=1",
    ] {
        assert_eq!(
            client
                .get(format!("{url}?{query}"))
                .send()
                .await
                .unwrap()
                .status(),
            StatusCode::BAD_REQUEST
        );
    }
    assert_eq!(
        client
            .get(format!("{url}/_all_docs"))
            .send()
            .await
            .unwrap()
            .status(),
        StatusCode::BAD_REQUEST
    );
    assert!(db.lock().unwrap().requests.is_empty());
}

#[tokio::test]
async fn maps_couchdb_failures_without_exposing_details() {
    let (api, _couch, db) = setup().await;
    let client = reqwest::Client::new();
    for (upstream, expected) in [
        (401, 503),
        (403, 503),
        (404, 503),
        (409, 409),
        (429, 503),
        (500, 502),
        (503, 503),
    ] {
        db.lock().unwrap().failure = Some(StatusCode::from_u16(upstream).unwrap());
        let response = client
            .get(format!("{}/api/empresas", api.url))
            .send()
            .await
            .unwrap();
        assert_eq!(response.status().as_u16(), expected);
        let body = response.text().await.unwrap();
        assert!(!body.contains("secret-password"));
        assert!(!body.contains("127.0.0.1"));
    }
    db.lock().unwrap().failure = None;
    db.lock().unwrap().malformed = true;
    assert_eq!(
        client
            .get(format!("{}/api/empresas", api.url))
            .send()
            .await
            .unwrap()
            .status(),
        StatusCode::BAD_GATEWAY
    );
}

#[tokio::test]
async fn preserves_existing_test_document_and_state_during_update() {
    let (api, _couch, db) = setup().await;
    db.lock().unwrap().documents.insert("empresa_prueba_001".into(), json!({
        "_id": "empresa_prueba_001", "_rev": "1-test", "nombre": "Prueba ficticia", "nit": "NIT-LEGACY", "estado": "activa"
    }));
    let client = reqwest::Client::new();
    let url = format!("{}/api/empresas/empresa_prueba_001", api.url);
    let old: Value = client.get(&url).send().await.unwrap().json().await.unwrap();
    assert_eq!(old["id"], "empresa_prueba_001");
    assert!(old["fecha_creacion"].is_null());
    let response = client
        .put(&url)
        .json(&input("NIT-LEGACY"))
        .send()
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::OK);
    let updated: Value = response.json().await.unwrap();
    assert_eq!(updated["estado"], "activa");
    assert!(updated["fecha_creacion"].is_null());
    assert!(updated["fecha_actualizacion"].as_str().is_some());
}

#[tokio::test]
async fn couchdb_revision_conflict_is_not_overwritten() {
    let (_api, couch, db) = setup().await;
    db.lock().unwrap().documents.insert("empresa_prueba_001".into(), json!({
        "_id": "empresa_prueba_001", "_rev": "1-test", "nombre": "Prueba ficticia", "nit": "NIT-LEGACY"
    }));
    let repository = EmpresaRepository::new(&couch.url, "test".into(), "test".into()).unwrap();
    let mut document = repository.get("empresa_prueba_001").await.unwrap();
    document.rev = Some("0-stale".into());
    assert!(matches!(
        repository.save(document).await,
        Err(super::EmpresaError::Conflict)
    ));
    assert_eq!(
        db.lock().unwrap().documents["empresa_prueba_001"]["_rev"],
        "1-test"
    );
}

#[tokio::test]
async fn health_works_without_configuration_and_unreachable_database_returns_503() {
    let api = serve(
        Router::new()
            .route("/api/health", get(crate::health))
            .merge(routes::router(EmpresaService::new(None))),
    )
    .await;
    let client = reqwest::Client::new();
    assert_eq!(
        client
            .get(format!("{}/api/health", api.url))
            .send()
            .await
            .unwrap()
            .status(),
        StatusCode::OK
    );
    assert_eq!(
        client
            .get(format!("{}/api/empresas", api.url))
            .send()
            .await
            .unwrap()
            .status(),
        StatusCode::SERVICE_UNAVAILABLE
    );
    let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
    let url = format!("http://{}", listener.local_addr().unwrap());
    drop(listener);
    let repository = EmpresaRepository::new(&url, "test".into(), "test".into()).unwrap();
    assert!(matches!(
        repository.get("empresa_prueba_001").await,
        Err(super::EmpresaError::Unavailable)
    ));
}

#[test]
fn rejects_unsafe_or_incomplete_configuration() {
    for url in [
        "invalid",
        "file:///tmp",
        "http://admin:secret@localhost:5984",
        "http://localhost:5984?x=y",
        "http://localhost:5984#fragment",
    ] {
        assert!(EmpresaRepository::new(url, "test".into(), "test".into()).is_err());
    }
    assert!(EmpresaRepository::new("http://localhost:5984", "".into(), "test".into()).is_err());
    assert!(EmpresaRepository::new("http://localhost:5984", "test".into(), "".into()).is_err());
}

#[tokio::test]
async fn missing_mango_index_is_distinguished_from_invalid_documents() {
    let (api, _couch, db) = setup().await;
    db.lock().unwrap().missing_index = true;
    let client = reqwest::Client::new();
    let url = format!("{}/api/empresas", api.url);
    // Reproduce el incidente: POST y consulta individual funcionan sin índice de ordenación.
    let created = client
        .post(&url)
        .json(&input("NIT-PRUEBA"))
        .send()
        .await
        .unwrap();
    assert_eq!(created.status(), StatusCode::CREATED);
    let created: Value = created.json().await.unwrap();
    assert_eq!(
        client
            .get(format!("{url}/{}", created["id"].as_str().unwrap()))
            .send()
            .await
            .unwrap()
            .status(),
        StatusCode::OK
    );
    let response = client.get(format!("{url}?limit=10")).send().await.unwrap();
    assert_eq!(response.status(), StatusCode::SERVICE_UNAVAILABLE);
    let body = response.text().await.unwrap();
    assert!(body.contains("empresas-nit/por-nit"));
    assert!(!body.contains("secret-password"));
    // Al instalar el índice se recupera el documento, sin fabricar una lista vacía.
    db.lock().unwrap().missing_index = false;
    let response = client.get(format!("{url}?limit=10")).send().await.unwrap();
    assert_eq!(response.status(), StatusCode::OK);
    let page: Value = response.json().await.unwrap();
    assert_eq!(page["empresas"].as_array().unwrap().len(), 1);
    assert_eq!(page["empresas"][0]["id"], created["id"]);
}

#[tokio::test]
async fn mango_listing_accepts_missing_or_null_dates_in_legacy_documents() {
    let (api, _couch, db) = setup().await;
    for (id, dates) in [("empresa_prueba_001", false), ("empresa-fechas-null", true)] {
        let mut doc = json!({"_id": id, "_rev": "1-test", "nombre": "Empresa ficticia", "nit": id});
        if dates {
            doc["fecha_creacion"] = Value::Null;
            doc["fecha_actualizacion"] = Value::Null;
        }
        db.lock().unwrap().documents.insert(id.into(), doc);
    }
    let response = reqwest::get(format!("{}/api/empresas?limit=10", api.url))
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::OK);
    let page: Value = response.json().await.unwrap();
    assert_eq!(page["empresas"].as_array().unwrap().len(), 2);
    assert!(page["empresas"]
        .as_array()
        .unwrap()
        .iter()
        .all(|e| e["fecha_creacion"].is_null() && e["fecha_actualizacion"].is_null()));
    assert_eq!(db.lock().unwrap().documents.len(), 2);
}

#[tokio::test]
async fn incompatible_mango_documents_are_not_silently_discarded() {
    let (api, _couch, db) = setup().await;
    let client = reqwest::Client::new();
    for (field, value) in [
        ("fecha_creacion", json!("secret-invalid-date")),
        ("estado", json!("secret-invalid-state")),
        ("nombre", Value::Null),
    ] {
        let mut doc = json!({"_id": "empresa_prueba_001", "_rev": "1-test", "nombre": "Empresa ficticia", "nit": "NIT-PRUEBA"});
        doc[field] = value;
        db.lock()
            .unwrap()
            .documents
            .insert("empresa_prueba_001".into(), doc.clone());
        let response = client
            .get(format!("{}/api/empresas?limit=10", api.url))
            .send()
            .await
            .unwrap();
        assert_eq!(response.status(), StatusCode::BAD_GATEWAY);
        let body = response.text().await.unwrap();
        assert!(!body.contains("secret"));
        assert_eq!(db.lock().unwrap().documents["empresa_prueba_001"], doc);
    }
}

#[tokio::test]
#[ignore = "Requiere CouchDB real, índice por-nit y documento empresa_prueba_001; solo lectura"]
async fn real_couchdb_listing_and_legacy_document() {
    dotenvy::dotenv().ok();
    let repository = EmpresaRepository::from_env().expect("Configurar CouchDB local");
    let legacy = repository
        .get("empresa_prueba_001")
        .await
        .expect("Consultar documento previo");
    let legacy_id = legacy.id.clone().unwrap();
    let legacy_rev = legacy.rev.clone();
    let mut bookmark = None;
    let mut found = false;
    let mut total = 0;
    loop {
        let (documents, next) = repository
            .list(100, bookmark)
            .await
            .expect("Listar Mango con índice por-nit");
        let count = documents.len();
        total += count;
        for document in documents {
            found |= document.id.as_deref() == Some(legacy_id.as_str());
            document
                .into_empresa()
                .expect("Convertir respuesta pública");
        }
        if count < 100 {
            break;
        }
        bookmark = Some(next);
    }
    assert!(found, "El listado debe incluir el documento previo");
    let after = repository.get(&legacy_id).await.unwrap();
    assert_eq!(
        after.rev, legacy_rev,
        "La prueba no debe modificar el documento"
    );
    println!("Listado real correcto: {total} documentos; documento previo presente sin modificar");
}
