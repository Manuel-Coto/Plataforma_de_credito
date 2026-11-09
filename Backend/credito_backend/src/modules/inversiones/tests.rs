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
use chrono::{Duration, Utc};
use serde_json::{json, Value};
use tokio::{sync::Barrier, task::JoinHandle};

use super::{repository::InversionRepository, routes, service::InversionService};
use crate::{database::connection::CouchDb, modules::usuarios::service::UsuarioService};

const SECRET: &str = "secreto-ficticio-inversiones-pruebas-0123456789";
type Db = Arc<Mutex<MockDb>>;
type Reply = (StatusCode, Json<Value>);

#[derive(Default)]
struct MockDb {
    documents: BTreeMap<(String, String), Value>,
    writes: Vec<(String, String)>,
    fail_before: Option<String>,
    fail_after: Option<String>,
    barrier: Option<Arc<Barrier>>,
    synchronized_reads: usize,
}

impl MockDb {
    fn insert(&mut self, base: &str, document: Value) {
        self.documents.insert(
            (base.into(), document["_id"].as_str().unwrap().into()),
            document,
        );
    }
    fn oferta(&self) -> &Value {
        &self.documents[&("ofertas".into(), "oferta".into())]
    }
    fn inversiones(&self) -> Vec<&Value> {
        self.documents
            .values()
            .filter(|document| document["tipo"] == "inversion")
            .collect()
    }
}

fn basic(headers: &HeaderMap) {
    assert_eq!(headers["authorization"], "Basic dGVzdDp0ZXN0");
}

async fn read(
    State(db): State<Db>,
    Path((base, id)): Path<(String, String)>,
    headers: HeaderMap,
) -> Reply {
    basic(&headers);
    let (document, barrier) = {
        let mut state = db.lock().unwrap();
        let document = state.documents.get(&(base.clone(), id)).cloned();
        let barrier = if base == "ofertas" && state.synchronized_reads > 0 {
            state.synchronized_reads -= 1;
            state.barrier.clone()
        } else {
            None
        };
        (document, barrier)
    };
    if let Some(barrier) = barrier {
        barrier.wait().await;
    }
    match document {
        Some(document) => (StatusCode::OK, Json(document)),
        None => (
            StatusCode::NOT_FOUND,
            Json(json!({"error":"not_found", "reason":"missing"})),
        ),
    }
}

async fn save(
    State(db): State<Db>,
    Path((base, id)): Path<(String, String)>,
    headers: HeaderMap,
    Json(mut document): Json<Value>,
) -> Reply {
    basic(&headers);
    let mut db = db.lock().unwrap();
    let kind = document["tipo"].as_str().unwrap().to_string();
    if db.fail_before.as_deref() == Some(&kind) {
        return (
            StatusCode::SERVICE_UNAVAILABLE,
            Json(json!({"error":"simulated-write-failure"})),
        );
    }
    let key = (base.clone(), id.clone());
    if let Some(current) = db.documents.get(&key) {
        if document["_rev"] != current["_rev"] {
            return (StatusCode::CONFLICT, Json(json!({"error":"conflict"})));
        }
    } else if document.get("_rev").is_some() {
        return (StatusCode::CONFLICT, Json(json!({"error":"conflict"})));
    }
    assert_eq!(document["_id"], id);
    let version = document["_rev"]
        .as_str()
        .and_then(|rev| rev.split('-').next())
        .and_then(|version| version.parse::<u64>().ok())
        .unwrap_or(0)
        + 1;
    let revision = format!("{version}-test");
    document["_rev"] = json!(revision);
    db.documents.insert(key, document);
    db.writes.push((base, id.clone()));
    if db.fail_after.as_deref() == Some(&kind) {
        return (
            StatusCode::SERVICE_UNAVAILABLE,
            Json(json!({"error":"simulated-lost-response"})),
        );
    }
    (
        StatusCode::CREATED,
        Json(json!({"ok":true, "id":id, "rev":revision})),
    )
}

async fn find(
    State(db): State<Db>,
    Path(base): Path<String>,
    headers: HeaderMap,
    Json(query): Json<Value>,
) -> Reply {
    basic(&headers);
    let state = db.lock().unwrap();
    let offset = query["bookmark"]
        .as_str()
        .and_then(|bookmark| bookmark.parse::<usize>().ok())
        .unwrap_or(0);
    let limit = query["limit"].as_u64().unwrap_or(25) as usize;
    let documents: Vec<_> = state
        .documents
        .iter()
        .filter(|((collection, _), document)| {
            collection == &base
                && query["selector"]
                    .as_object()
                    .unwrap()
                    .iter()
                    .all(|(key, value)| document[key] == *value)
        })
        .skip(offset)
        .take(limit)
        .map(|(_, document)| document.clone())
        .collect();
    let bookmark = if documents.is_empty() {
        String::new()
    } else {
        (offset + documents.len()).to_string()
    };
    (
        StatusCode::OK,
        Json(json!({"docs":documents,"bookmark":bookmark})),
    )
}

struct Server {
    url: String,
    task: JoinHandle<()>,
}
impl Drop for Server {
    fn drop(&mut self) {
        self.task.abort();
    }
}
async fn serve(app: Router) -> Server {
    let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
    let url = format!("http://{}", listener.local_addr().unwrap());
    let task = tokio::spawn(async move {
        axum::serve(listener, app).await.unwrap();
    });
    Server { url, task }
}

async fn setup() -> (Server, Server, Db) {
    let db = Db::default();
    {
        let mut state = db.lock().unwrap();
        let now = Utc::now();
        for (id, role, status) in [
            ("inversor", "inversionista", "activo"),
            ("otro", "inversionista", "activo"),
            ("pyme", "pyme", "activo"),
            ("admin", "administrador", "activo"),
            ("inactivo", "inversionista", "inactivo"),
        ] {
            state.insert("usuarios", json!({"_id":id,"_rev":"1-test","nombre":"Usuario ficticio","correo":format!("{id}@example.test"),"password_hash":"no-usado","rol":role,"estado":status,"fecha_creacion":now,"fecha_actualizacion":now}));
        }
        state.insert("ofertas", json!({"_id":"oferta","_rev":"1-test","tipo":"oferta","factura_id":"factura","empresa_id":"empresa","monto_objetivo":10.0,"monto_recaudado":0.0,"moneda":"USD","tasa_rendimiento_anual":8.0,"estado":"abierta","fecha_apertura":now,"fecha_cierre":now + Duration::days(1),"creado_por":"pyme","campo_ajeno":{"conservar":true}}));
        state.insert("facturas", json!({"_id":"factura","_rev":"1-test","tipo":"factura","estado":"disponible","empresa_id":"empresa","creado_por":"pyme","monto_total_centavos":10000,"moneda":"USD", "dte":{"verificado":true}}));
    }
    let couch = serve(
        Router::new()
            .route("/{base}/_find", post(find))
            .route("/{base}/{id}", get(read).put(save))
            .with_state(db.clone()),
    )
    .await;
    let connection = CouchDb::from_parts(couch.url.clone(), "test".into(), "test".into()).unwrap();
    let repository = InversionRepository::from_connection(&connection).unwrap();
    let usuarios = UsuarioService::for_test(&couch.url, SECRET).await;
    let api = serve(routes::router(
        InversionService::new(Some(repository)),
        usuarios,
    ))
    .await;
    (api, couch, db)
}

fn client(actor: &str) -> reqwest::Client {
    let now = Utc::now().timestamp();
    let token = jsonwebtoken::encode(&jsonwebtoken::Header::default(), &json!({"sub":actor,"iat":now,"nbf":now,"exp":now+3600,"iss":"credito-backend","aud":"credito-api"}), &jsonwebtoken::EncodingKey::from_secret(SECRET.as_bytes())).unwrap();
    let mut headers = HeaderMap::new();
    headers.insert("authorization", format!("Bearer {token}").parse().unwrap());
    reqwest::Client::builder()
        .default_headers(headers)
        .build()
        .unwrap()
}

async fn invest(api: &Server, actor: &str, key: Option<&str>, amount: f64) -> reqwest::Response {
    let mut request = client(actor)
        .post(format!("{}/api/inversiones", api.url))
        .json(&json!({"oferta_id":"oferta","monto":amount}));
    if let Some(key) = key {
        request = request.header("Idempotency-Key", key);
    }
    request.send().await.unwrap()
}

async fn body(response: reqwest::Response, status: StatusCode) -> Value {
    let actual = response.status();
    let body = response.text().await.unwrap();
    assert_eq!(actual, status, "{body}");
    serde_json::from_str(&body).unwrap()
}

#[tokio::test]
async fn pending_projection_is_recovered_without_charging_the_offer_twice() {
    let (api, _couch, db) = setup().await;
    db.lock().unwrap().fail_before = Some("inversion".into());
    body(
        invest(&api, "inversor", Some("reintento-proyeccion"), 2.50).await,
        StatusCode::SERVICE_UNAVAILABLE,
    )
    .await;
    {
        let state = db.lock().unwrap();
        assert_eq!(state.oferta()["monto_recaudado"], 2.5);
        assert_eq!(
            state.oferta()["reservas_inversiones"]
                .as_object()
                .unwrap()
                .len(),
            1
        );
        assert!(state.inversiones().is_empty());
    }
    db.lock().unwrap().fail_before = None;
    db.lock()
        .unwrap()
        .documents
        .get_mut(&("ofertas".into(), "oferta".into()))
        .unwrap()["fecha_cierre"] = json!(Utc::now() - Duration::days(1));
    let saved = body(
        invest(&api, "inversor", Some("reintento-proyeccion"), 2.50).await,
        StatusCode::CREATED,
    )
    .await;
    let replay = body(
        invest(&api, "inversor", Some("reintento-proyeccion"), 2.50).await,
        StatusCode::CREATED,
    )
    .await;
    assert_eq!(saved, replay);
    assert_eq!(saved["estado"], "pago_pendiente");
    let state = db.lock().unwrap();
    assert_eq!(state.oferta()["monto_recaudado"], 2.5);
    assert_eq!(state.oferta()["campo_ajeno"]["conservar"], true);
    assert_eq!(state.inversiones().len(), 1);
}

#[tokio::test]
async fn failures_before_first_commit_and_uncertain_responses_are_retryable() {
    let (api, _couch, db) = setup().await;
    db.lock().unwrap().fail_before = Some("solicitud_inversion".into());
    body(
        invest(&api, "inversor", Some("primera-escritura"), 1.0).await,
        StatusCode::SERVICE_UNAVAILABLE,
    )
    .await;
    assert_eq!(db.lock().unwrap().oferta()["monto_recaudado"], 0.0);
    assert!(db.lock().unwrap().inversiones().is_empty());
    db.lock().unwrap().fail_before = None;
    db.lock().unwrap().fail_after = Some("solicitud_inversion".into());
    body(
        invest(&api, "inversor", Some("primera-escritura"), 1.0).await,
        StatusCode::CREATED,
    )
    .await;
    for kind in ["oferta", "inversion"] {
        db.lock().unwrap().fail_after = Some(kind.into());
        let key = format!("respuesta-perdida-{kind}");
        let saved = body(
            invest(&api, "inversor", Some(&key), 1.0).await,
            StatusCode::CREATED,
        )
        .await;
        assert_eq!(saved["monto"], 1.0);
        body(
            invest(&api, "inversor", Some(&key), 1.0).await,
            StatusCode::CREATED,
        )
        .await;
    }
    assert_eq!(db.lock().unwrap().oferta()["monto_recaudado"], 3.0);
    assert_eq!(db.lock().unwrap().inversiones().len(), 3);
}

#[tokio::test]
async fn failed_offer_write_can_resume_and_reusing_a_key_changes_nothing() {
    let (api, _couch, db) = setup().await;
    db.lock().unwrap().fail_before = Some("oferta".into());
    body(
        invest(&api, "inversor", Some("reserva"), 2.0).await,
        StatusCode::SERVICE_UNAVAILABLE,
    )
    .await;
    assert_eq!(db.lock().unwrap().oferta()["monto_recaudado"], 0.0);
    db.lock().unwrap().fail_before = None;
    body(
        invest(&api, "inversor", Some("reserva"), 3.0).await,
        StatusCode::CONFLICT,
    )
    .await;
    let changed_offer = client("inversor")
        .post(format!("{}/api/inversiones", api.url))
        .header("Idempotency-Key", "reserva")
        .json(&json!({"oferta_id":"otra-oferta","monto":2.0}))
        .send()
        .await
        .unwrap();
    body(changed_offer, StatusCode::CONFLICT).await;
    body(
        invest(&api, "inversor", Some("reserva"), 2.0).await,
        StatusCode::CREATED,
    )
    .await;
    body(
        invest(&api, "otro", Some("reserva"), 2.0).await,
        StatusCode::CREATED,
    )
    .await;
    assert_eq!(db.lock().unwrap().oferta()["monto_recaudado"], 4.0);
    assert_eq!(db.lock().unwrap().inversiones().len(), 2);
}

#[tokio::test]
async fn replay_after_confirmation_and_offer_financing_does_not_revert_any_document() {
    let (api, _couch, db) = setup().await;
    let saved = body(
        invest(&api, "inversor", Some("confirmada"), 10.0).await,
        StatusCode::CREATED,
    )
    .await;
    let id = saved["_id"].as_str().unwrap();
    let before = {
        let mut state = db.lock().unwrap();
        let inversion = state
            .documents
            .get_mut(&("operaciones".into(), id.into()))
            .unwrap();
        inversion["estado"] = json!("confirmada");
        inversion["fecha_confirmacion_pago"] = json!("2026-11-08T12:00:00Z");
        inversion["confirmado_por"] = json!("inversor");
        inversion["historial_ajeno"] = json!(["conservar"]);
        let oferta = state
            .documents
            .get_mut(&("ofertas".into(), "oferta".into()))
            .unwrap();
        oferta["estado"] = json!("financiada");
        oferta["fecha_cierre"] = json!(Utc::now() - Duration::days(1));
        state.documents.clone()
    };
    let replay = body(
        invest(&api, "inversor", Some("confirmada"), 10.0).await,
        StatusCode::CREATED,
    )
    .await;
    assert_eq!(replay["_id"], id);
    assert_eq!(replay["estado"], "confirmada");
    assert_eq!(db.lock().unwrap().documents, before);
    let recovery = body(
        client("inversor")
            .post(format!("{}/api/inversiones/recuperar", api.url))
            .send()
            .await
            .unwrap(),
        StatusCode::OK,
    )
    .await;
    assert_eq!(recovery["recuperadas"], 0);
    assert_eq!(recovery["omitidas"], 1);
    assert_eq!(db.lock().unwrap().documents, before);
}

#[tokio::test]
async fn concurrent_reservations_cannot_overfund_and_same_key_creates_one_investment() {
    let (api, _couch, db) = setup().await;
    {
        let mut state = db.lock().unwrap();
        state.barrier = Some(Arc::new(Barrier::new(2)));
        state.synchronized_reads = 2;
    }
    let (first, second) = tokio::join!(
        invest(&api, "inversor", Some("competencia-1"), 7.0),
        invest(&api, "otro", Some("competencia-2"), 7.0)
    );
    let statuses = [first.status(), second.status()];
    assert_eq!(
        statuses
            .iter()
            .filter(|status| **status == StatusCode::CREATED)
            .count(),
        1
    );
    assert_eq!(
        statuses
            .iter()
            .filter(|status| **status == StatusCode::BAD_REQUEST)
            .count(),
        1
    );
    assert_eq!(db.lock().unwrap().oferta()["monto_recaudado"], 7.0);
    assert_eq!(db.lock().unwrap().inversiones().len(), 1);
    {
        let mut state = db.lock().unwrap();
        state.barrier = Some(Arc::new(Barrier::new(2)));
        state.synchronized_reads = 2;
    }
    let (first, second) = tokio::join!(
        invest(&api, "inversor", Some("misma-clave"), 3.0),
        invest(&api, "inversor", Some("misma-clave"), 3.0)
    );
    let first = body(first, StatusCode::CREATED).await;
    let second = body(second, StatusCode::CREATED).await;
    assert_eq!(first, second);
    assert_eq!(db.lock().unwrap().oferta()["monto_recaudado"], 10.0);
    assert_eq!(db.lock().unwrap().inversiones().len(), 2);
}

#[tokio::test]
async fn public_offer_and_investment_lists_hide_internal_reservations_and_requests() {
    let (api, _couch, db) = setup().await;
    body(
        invest(&api, "inversor", Some("privacidad"), 1.0).await,
        StatusCode::CREATED,
    )
    .await;
    let offers = body(
        client("otro")
            .get(format!("{}/api/ofertas", api.url))
            .send()
            .await
            .unwrap(),
        StatusCode::OK,
    )
    .await;
    let serialized = offers.to_string();
    assert!(!serialized.contains("reservas_inversiones"));
    assert!(!serialized.contains("inversionista_id"));
    let investments = body(
        client("inversor")
            .get(format!("{}/api/inversiones", api.url))
            .send()
            .await
            .unwrap(),
        StatusCode::OK,
    )
    .await;
    assert_eq!(investments["inversiones"].as_array().unwrap().len(), 1);
    assert!(!investments.to_string().contains("solicitud_inversion"));
    assert_eq!(
        db.lock()
            .unwrap()
            .documents
            .values()
            .filter(|doc| doc["tipo"] == "solicitud_inversion")
            .count(),
        1
    );
}

#[tokio::test]
async fn roles_keys_amounts_and_self_funding_are_checked_before_reserving() {
    let (api, _couch, db) = setup().await;
    for actor in ["pyme", "admin"] {
        body(
            invest(&api, actor, Some("sin-permiso"), 1.0).await,
            StatusCode::FORBIDDEN,
        )
        .await;
    }
    body(
        invest(&api, "inactivo", Some("inactivo"), 1.0).await,
        StatusCode::UNAUTHORIZED,
    )
    .await;
    for key in [None, Some(""), Some("espacio intermedio")] {
        body(
            invest(&api, "inversor", key, 1.0).await,
            StatusCode::BAD_REQUEST,
        )
        .await;
    }
    for amount in [0.0, -1.0, 0.001, 1.005, 0.00001, 1.000001] {
        body(
            invest(&api, "inversor", Some("subcentavo"), amount).await,
            StatusCode::BAD_REQUEST,
        )
        .await;
    }
    let repeated_header = client("inversor")
        .post(format!("{}/api/inversiones", api.url))
        .header("Idempotency-Key", "clave-1")
        .header("Idempotency-Key", "clave-2")
        .json(&json!({"oferta_id":"oferta", "monto":1.0}))
        .send()
        .await
        .unwrap();
    body(repeated_header, StatusCode::BAD_REQUEST).await;
    for goal in [0.001, 10.005] {
        let response = client("pyme")
            .post(format!("{}/api/ofertas", api.url))
            .json(&json!({"factura_id":"factura", "monto_objetivo":goal,
                "tasa_rendimiento_anual":8.0, "fecha_cierre":Utc::now() + Duration::days(1)}))
            .send()
            .await
            .unwrap();
        body(response, StatusCode::BAD_REQUEST).await;
    }
    assert!(db.lock().unwrap().writes.is_empty());
    db.lock()
        .unwrap()
        .documents
        .get_mut(&("ofertas".into(), "oferta".into()))
        .unwrap()["creado_por"] = json!("inversor");
    body(
        invest(&api, "inversor", Some("propia"), 1.0).await,
        StatusCode::FORBIDDEN,
    )
    .await;
    assert_eq!(db.lock().unwrap().oferta()["monto_recaudado"], 0.0);
    assert!(db.lock().unwrap().inversiones().is_empty());
}

#[tokio::test]
async fn actor_can_recover_after_losing_the_key_without_allocating_unreserved_requests() {
    let (api, _couch, db) = setup().await;
    db.lock().unwrap().fail_before = Some("inversion".into());
    body(
        invest(&api, "inversor", Some("clave-perdida-propia"), 2.0).await,
        StatusCode::SERVICE_UNAVAILABLE,
    )
    .await;
    body(
        invest(&api, "otro", Some("clave-perdida-ajena"), 3.0).await,
        StatusCode::SERVICE_UNAVAILABLE,
    )
    .await;
    let pending = body(
        client("inversor")
            .post(format!("{}/api/inversiones/recuperar", api.url))
            .send()
            .await
            .unwrap(),
        StatusCode::OK,
    )
    .await;
    assert_eq!(pending["recuperadas"], 0);
    assert_eq!(pending["pendientes"], 1);
    assert!(db.lock().unwrap().inversiones().is_empty());
    db.lock().unwrap().fail_before = None;
    let recovered = body(
        client("inversor")
            .post(format!("{}/api/inversiones/recuperar", api.url))
            .send()
            .await
            .unwrap(),
        StatusCode::OK,
    )
    .await;
    assert_eq!(recovered["recuperadas"], 1);
    assert_eq!(recovered["pendientes"], 0);
    assert_eq!(recovered["omitidas"], 0);
    assert!(recovered.as_object().unwrap().keys().all(|key| [
        "recuperadas",
        "pendientes",
        "omitidas",
        "bookmark"
    ]
    .contains(&key.as_str())));
    {
        let state = db.lock().unwrap();
        assert_eq!(state.inversiones().len(), 1);
        assert_eq!(state.inversiones()[0]["inversionista_id"], "inversor");
        assert_eq!(state.oferta()["monto_recaudado"], 5.0);
    }
    let admin = body(
        client("admin")
            .post(format!("{}/api/inversiones/recuperar", api.url))
            .send()
            .await
            .unwrap(),
        StatusCode::OK,
    )
    .await;
    assert_eq!(admin["recuperadas"], 0);
    assert_eq!(admin["pendientes"], 0);
    assert_eq!(admin["omitidas"], 0);
    body(
        client("pyme")
            .post(format!("{}/api/inversiones/recuperar", api.url))
            .send()
            .await
            .unwrap(),
        StatusCode::FORBIDDEN,
    )
    .await;
    db.lock().unwrap().fail_before = Some("oferta".into());
    body(
        invest(&api, "inversor", Some("intento-sin-reserva"), 1.0).await,
        StatusCode::SERVICE_UNAVAILABLE,
    )
    .await;
    db.lock().unwrap().fail_before = None;
    let before = db.lock().unwrap().documents.clone();
    let repeat = body(
        client("inversor")
            .post(format!("{}/api/inversiones/recuperar", api.url))
            .send()
            .await
            .unwrap(),
        StatusCode::OK,
    )
    .await;
    assert_eq!(repeat["recuperadas"], 0);
    assert_eq!(repeat["pendientes"], 0);
    assert_eq!(repeat["omitidas"], 2);
    assert_eq!(db.lock().unwrap().documents, before);
    let other = body(
        client("otro")
            .post(format!("{}/api/inversiones/recuperar", api.url))
            .send()
            .await
            .unwrap(),
        StatusCode::OK,
    )
    .await;
    assert_eq!(other["recuperadas"], 1);
    assert_eq!(db.lock().unwrap().oferta()["monto_recaudado"], 5.0);
}

#[tokio::test]
async fn recovery_uses_one_owned_page_and_validates_the_cursor_query() {
    let (api, _couch, db) = setup().await;
    db.lock().unwrap().fail_before = Some("inversion".into());
    for key in ["pagina-1", "pagina-2", "pagina-3"] {
        body(
            invest(&api, "inversor", Some(key), 1.0).await,
            StatusCode::SERVICE_UNAVAILABLE,
        )
        .await;
    }
    db.lock().unwrap().fail_before = None;
    let first = body(
        client("inversor")
            .post(format!("{}/api/inversiones/recuperar?limit=2", api.url))
            .send()
            .await
            .unwrap(),
        StatusCode::OK,
    )
    .await;
    assert_eq!(first["recuperadas"], 2);
    assert_eq!(db.lock().unwrap().inversiones().len(), 2);
    let next = body(
        client("inversor")
            .post(format!("{}/api/inversiones/recuperar", api.url))
            .query(&[
                ("limit", "2"),
                ("bookmark", first["bookmark"].as_str().unwrap()),
            ])
            .send()
            .await
            .unwrap(),
        StatusCode::OK,
    )
    .await;
    assert_eq!(next["recuperadas"], 1);
    assert_eq!(db.lock().unwrap().inversiones().len(), 3);
    assert_eq!(db.lock().unwrap().oferta()["monto_recaudado"], 3.0);
    for query in ["limit=0", "limit=101", "actor_id=otro"] {
        body(
            client("inversor")
                .post(format!("{}/api/inversiones/recuperar?{query}", api.url))
                .send()
                .await
                .unwrap(),
            StatusCode::BAD_REQUEST,
        )
        .await;
    }
}

#[tokio::test]
async fn concurrent_offer_publication_is_deterministic_and_replay_preserves_current_state() {
    let (api, _couch, db) = setup().await;
    db.lock()
        .unwrap()
        .documents
        .remove(&("ofertas".into(), "oferta".into()));
    let input = json!({"factura_id":"factura", "monto_objetivo":10.0,
        "tasa_rendimiento_anual":8.0, "fecha_cierre":Utc::now() + Duration::days(1)});
    let (first, second) = tokio::join!(
        client("pyme")
            .post(format!("{}/api/ofertas", api.url))
            .json(&input)
            .send(),
        client("pyme")
            .post(format!("{}/api/ofertas", api.url))
            .json(&input)
            .send()
    );
    let first = body(first.unwrap(), StatusCode::CREATED).await;
    let second = body(second.unwrap(), StatusCode::CREATED).await;
    assert_eq!(first, second);
    let id = first["_id"].as_str().unwrap();
    {
        let mut state = db.lock().unwrap();
        assert_eq!(
            state
                .documents
                .values()
                .filter(|document| document["tipo"] == "oferta")
                .count(),
            1
        );
        assert_eq!(
            state
                .writes
                .iter()
                .filter(|(base, _)| base == "ofertas")
                .count(),
            1
        );
        let oferta = state
            .documents
            .get_mut(&("ofertas".into(), id.into()))
            .unwrap();
        oferta["estado"] = json!("financiada");
        oferta["campo_ajeno"] = json!("conservar");
        state
            .documents
            .get_mut(&("facturas".into(), "factura".into()))
            .unwrap()["estado"] = json!("financiada");
    }
    let before = db.lock().unwrap().documents.clone();
    let replay = body(
        client("pyme")
            .post(format!("{}/api/ofertas", api.url))
            .json(&input)
            .send()
            .await
            .unwrap(),
        StatusCode::CREATED,
    )
    .await;
    assert_eq!(replay["_id"], id);
    assert_eq!(replay["estado"], "financiada");
    assert_eq!(db.lock().unwrap().documents, before);
    let mut changed = input.clone();
    changed["monto_objetivo"] = json!(9.0);
    body(
        client("pyme")
            .post(format!("{}/api/ofertas", api.url))
            .json(&changed)
            .send()
            .await
            .unwrap(),
        StatusCode::CONFLICT,
    )
    .await;
    body(
        client("admin")
            .post(format!("{}/api/ofertas", api.url))
            .json(&input)
            .send()
            .await
            .unwrap(),
        StatusCode::CONFLICT,
    )
    .await;
    assert_eq!(db.lock().unwrap().documents, before);
}

#[tokio::test]
async fn legacy_offer_prevents_duplicate_publication_and_exact_replay_is_safe() {
    let (api, _couch, db) = setup().await;
    let close = Utc::now() - Duration::days(1);
    db.lock()
        .unwrap()
        .documents
        .get_mut(&("ofertas".into(), "oferta".into()))
        .unwrap()["fecha_cierre"] = json!(close);
    let mut input = json!({"factura_id":"factura", "monto_objetivo":9.0,
        "tasa_rendimiento_anual":8.0, "fecha_cierre":close});
    body(
        client("pyme")
            .post(format!("{}/api/ofertas", api.url))
            .json(&input)
            .send()
            .await
            .unwrap(),
        StatusCode::CONFLICT,
    )
    .await;
    input["monto_objetivo"] = json!(10.0);
    let replay = body(
        client("pyme")
            .post(format!("{}/api/ofertas", api.url))
            .json(&input)
            .send()
            .await
            .unwrap(),
        StatusCode::CREATED,
    )
    .await;
    assert_eq!(replay["_id"], "oferta");
    assert!(db.lock().unwrap().writes.is_empty());
}

#[tokio::test]
async fn lost_offer_response_replays_once_and_source_invoice_must_be_usd_and_verified() {
    let (api, _couch, db) = setup().await;
    db.lock()
        .unwrap()
        .documents
        .remove(&("ofertas".into(), "oferta".into()));
    let input = json!({"factura_id":"factura", "monto_objetivo":10.0,
        "tasa_rendimiento_anual":8.0, "fecha_cierre":Utc::now() + Duration::days(1)});
    db.lock()
        .unwrap()
        .documents
        .get_mut(&("facturas".into(), "factura".into()))
        .unwrap()["moneda"] = json!("EUR");
    body(
        client("pyme")
            .post(format!("{}/api/ofertas", api.url))
            .json(&input)
            .send()
            .await
            .unwrap(),
        StatusCode::BAD_REQUEST,
    )
    .await;
    {
        let mut state = db.lock().unwrap();
        let factura = state
            .documents
            .get_mut(&("facturas".into(), "factura".into()))
            .unwrap();
        factura["moneda"] = json!("USD");
        factura["dte"]["verificado"] = json!(false);
    }
    body(
        client("pyme")
            .post(format!("{}/api/ofertas", api.url))
            .json(&input)
            .send()
            .await
            .unwrap(),
        StatusCode::BAD_REQUEST,
    )
    .await;
    assert!(db.lock().unwrap().writes.is_empty());
    db.lock()
        .unwrap()
        .documents
        .get_mut(&("facturas".into(), "factura".into()))
        .unwrap()["dte"]["verificado"] = json!(true);
    db.lock().unwrap().fail_after = Some("oferta".into());
    let saved = body(
        client("pyme")
            .post(format!("{}/api/ofertas", api.url))
            .json(&input)
            .send()
            .await
            .unwrap(),
        StatusCode::CREATED,
    )
    .await;
    let replay = body(
        client("pyme")
            .post(format!("{}/api/ofertas", api.url))
            .json(&input)
            .send()
            .await
            .unwrap(),
        StatusCode::CREATED,
    )
    .await;
    assert_eq!(saved, replay);
    assert_eq!(db.lock().unwrap().writes.len(), 1);
}

#[test]
fn centavos_are_canonical_integers_instead_of_rounded_fractions() {
    use super::service::centavos;
    for cents in 1..10000 {
        assert_eq!(centavos(cents as f64 / 100.0, false).unwrap(), cents);
    }
    assert_eq!(centavos(0.0, true).unwrap(), 0);
    for invalid in [
        0.0,
        -0.01,
        0.001,
        0.009,
        1.005,
        1.000001,
        f64::NAN,
        f64::INFINITY,
        1e15,
    ] {
        assert!(centavos(invalid, false).is_err(), "Debe rechazar {invalid}");
    }
}
