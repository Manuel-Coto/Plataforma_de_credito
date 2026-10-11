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
use tokio::task::JoinHandle;

use super::{repository::CreditoRepository, routes, service::CreditoService};
use crate::database::connection::CouchDb;

const SECRET: &str = "secreto-ficticio-creditos-de-pruebas-32-caracteres";
type Db = Arc<Mutex<MockDb>>;
type Reply = (StatusCode, Json<Value>);

#[derive(Default)]
struct MockDb {
    documents: BTreeMap<(String, String), Value>,
    writes: Vec<(String, String, Value)>,
    fail_writes: Option<String>,
    ledger_conflicts: usize,
}

impl MockDb {
    fn insert(&mut self, collection: &str, document: Value) {
        self.documents.insert(
            (collection.into(), document["_id"].as_str().unwrap().into()),
            document,
        );
    }

    fn document(&self, collection: &str, id: &str) -> &Value {
        &self.documents[&(collection.into(), id.into())]
    }

    fn document_mut(&mut self, collection: &str, id: &str) -> &mut Value {
        self.documents
            .get_mut(&(collection.into(), id.into()))
            .unwrap()
    }

    fn credits(&self) -> Vec<&Value> {
        self.documents
            .values()
            .filter(|doc| doc["tipo"] == "credito")
            .collect()
    }
}

fn basic_auth(headers: &HeaderMap) {
    assert_eq!(headers.get("authorization").unwrap(), "Basic dGVzdDp0ZXN0");
}

fn matches_condition(value: &Value, condition: &Value) -> bool {
    let Some(operators) = condition.as_object() else {
        return value == condition;
    };
    operators
        .iter()
        .all(|(operator, operand)| match operator.as_str() {
            "$eq" => value == operand,
            "$ne" => value != operand,
            "$in" => operand.as_array().unwrap().contains(value),
            "$exists" => !value.is_null() == operand.as_bool().unwrap(),
            "$all" => operand
                .as_array()
                .unwrap()
                .iter()
                .all(|item| value.as_array().is_some_and(|values| values.contains(item))),
            "$elemMatch" => value.as_array().is_some_and(|items| {
                items.iter().any(|item| {
                    if operand
                        .as_object()
                        .is_some_and(|object| object.keys().any(|key| key.starts_with('$')))
                    {
                        matches_condition(item, operand)
                    } else {
                        matches_selector(item, operand)
                    }
                })
            }),
            "$gt" => value
                .as_str()
                .zip(operand.as_str())
                .is_some_and(|(a, b)| a > b),
            "$gte" => value
                .as_str()
                .zip(operand.as_str())
                .is_some_and(|(a, b)| a >= b),
            other => panic!("Operador Mango no implementado en prueba: {other}"),
        })
}

fn matches_selector(document: &Value, selector: &Value) -> bool {
    selector
        .as_object()
        .unwrap()
        .iter()
        .all(|(field, condition)| match field.as_str() {
            "$and" => condition
                .as_array()
                .unwrap()
                .iter()
                .all(|part| matches_selector(document, part)),
            "$or" => condition
                .as_array()
                .unwrap()
                .iter()
                .any(|part| matches_selector(document, part)),
            _ => matches_condition(&document[field], condition),
        })
}

async fn find(
    State(state): State<Db>,
    Path(collection): Path<String>,
    headers: HeaderMap,
    Json(query): Json<Value>,
) -> Reply {
    basic_auth(&headers);
    let db = state.lock().unwrap();
    let offset = query["bookmark"]
        .as_str()
        .and_then(|s| s.parse::<usize>().ok())
        .unwrap_or(0);
    let limit = query["limit"].as_u64().unwrap_or(25) as usize;
    let documents: Vec<_> = db
        .documents
        .iter()
        .filter(|((name, _), doc)| name == &collection && matches_selector(doc, &query["selector"]))
        .skip(offset)
        .take(limit)
        .map(|(_, doc)| doc.clone())
        .collect();
    (
        StatusCode::OK,
        Json(json!({"bookmark": (offset + documents.len()).to_string(), "docs": documents})),
    )
}

async fn read(
    State(state): State<Db>,
    Path((collection, id)): Path<(String, String)>,
    headers: HeaderMap,
) -> Reply {
    basic_auth(&headers);
    let db = state.lock().unwrap();
    match db.documents.get(&(collection, id)) {
        Some(document) => (StatusCode::OK, Json(document.clone())),
        None => (StatusCode::NOT_FOUND, Json(json!({"error":"not_found"}))),
    }
}

async fn save(
    State(state): State<Db>,
    Path((collection, id)): Path<(String, String)>,
    headers: HeaderMap,
    Json(mut document): Json<Value>,
) -> Reply {
    basic_auth(&headers);
    let mut db = state.lock().unwrap();
    if db.fail_writes.as_deref() == Some(&collection) {
        return (
            StatusCode::SERVICE_UNAVAILABLE,
            Json(json!({"error":"secret-database-failure"})),
        );
    }
    assert_eq!(document["_id"], id);
    let key = (collection.clone(), id.clone());
    if document["tipo"] == "credito" && db.documents.contains_key(&key) && db.ledger_conflicts > 0 {
        db.ledger_conflicts -= 1;
        return (StatusCode::CONFLICT, Json(json!({"error":"conflict"})));
    }
    let revision = if let Some(previous) = db.documents.get(&key) {
        if previous["_rev"] != document["_rev"] {
            return (StatusCode::CONFLICT, Json(json!({"error":"conflict"})));
        }
        previous["_rev"]
            .as_str()
            .unwrap()
            .split('-')
            .next()
            .unwrap()
            .parse::<u32>()
            .unwrap()
            + 1
    } else {
        assert!(document.get("_rev").is_none_or(Value::is_null));
        1
    };
    let rev = format!("{revision}-test");
    document["_rev"] = json!(rev);
    db.writes.push((collection, id.clone(), document.clone()));
    db.documents.insert(key, document);
    (
        StatusCode::CREATED,
        Json(json!({"ok":true, "id":id, "rev":rev})),
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
async fn serve(router: Router) -> RunningServer {
    let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
    let url = format!("http://{}", listener.local_addr().unwrap());
    let task = tokio::spawn(async move {
        axum::serve(listener, router).await.unwrap();
    });
    RunningServer { url, task }
}

fn fixtures() -> MockDb {
    let mut db = MockDb::default();
    let now = Utc::now();
    for (id, role, status) in [
        ("admin", "administrador", "activo"),
        ("pyme", "pyme", "activo"),
        ("otra-pyme", "pyme", "activo"),
        ("inversor", "inversionista", "activo"),
        ("segundo-inversor", "inversionista", "activo"),
        ("ajeno", "inversionista", "activo"),
        ("inactivo", "administrador", "inactivo"),
    ] {
        db.insert(
            "usuarios",
            json!({"_id":id,"_rev":"1-test", "nombre":"Usuario ficticio",
            "correo":format!("{id}@example.test"), "password_hash":"no-usado", "rol":role,
            "estado":status,"fecha_creacion":now,"fecha_actualizacion":now}),
        );
    }
    db.insert(
        "empresas",
        json!({"_id":"empresa", "_rev":"1-test", "nombre":"Empresa ficticia",
        "nit":"NIT-TEST", "estado":"activa", "usuario_responsable_id":"pyme"}),
    );
    db.insert("facturas", json!({"_id":"factura", "_rev":"1-test", "tipo":"factura",
        "empresa_id":"empresa", "numero":"TEST-1", "dte":{"codigo_generacion":"CODIGO-TEST",
        "sello_recepcion":"SELLO-TEST", "verificado":true, "fecha_verificacion":now}, "moneda":"USD",
        "monto_total_centavos":120000, "monto_financiado_centavos":0,
        "fecha_emision":now.date_naive(), "fecha_vencimiento":(now + Duration::days(10)).date_naive(),
        "estado":"disponible", "creado_por":"pyme", "fecha_creacion":now,
        "fecha_actualizacion":now, "campo_ajeno":"conservar"}));
    db.insert(
        "ofertas",
        json!({"_id":"oferta", "_rev":"1-test", "tipo":"oferta",
        "factura_id":"factura", "empresa_id":"empresa", "monto_objetivo":1000.0,
        "monto_recaudado":1000.0, "moneda":"USD", "tasa_rendimiento_anual":36.5,
        "estado":"objetivo_alcanzado", "fecha_apertura":now - Duration::days(2),
        "fecha_cierre":now + Duration::days(1), "creado_por":"pyme", "campo_ajeno":"conservar"}),
    );
    for (id, owner, amount) in [
        ("aporte-1", "inversor", 600.0),
        ("aporte-2", "segundo-inversor", 400.0),
    ] {
        db.insert(
            "operaciones",
            json!({"_id":id, "_rev":"1-test", "tipo":"inversion",
            "oferta_id":"oferta", "factura_id":"factura", "inversionista_id":owner,
            "monto":amount, "moneda":"USD", "estado":"confirmada", "fecha_creacion":now,
            "fecha_liquidacion":null, "rendimiento_real":null, "campo_ajeno":"conservar"}),
        );
    }
    db
}

async fn setup() -> (RunningServer, RunningServer, Db) {
    let db = Arc::new(Mutex::new(fixtures()));
    let couch = serve(
        Router::new()
            .route("/{collection}/_find", post(find))
            .route("/{collection}/{id}", get(read).put(save))
            .with_state(db.clone()),
    )
    .await;
    let connection = CouchDb::from_parts(couch.url.clone(), "test".into(), "test".into()).unwrap();
    let repository = CreditoRepository::from_connection(&connection).unwrap();
    let usuarios =
        crate::modules::usuarios::service::UsuarioService::for_test(&couch.url, SECRET).await;
    let api = serve(routes::router(
        CreditoService::new(Some(repository)),
        usuarios,
    ))
    .await;
    (api, couch, db)
}

fn token(actor: &str, expired: bool) -> String {
    let now = Utc::now().timestamp();
    let issued = if expired { now - 120 } else { now };
    jsonwebtoken::encode(
        &jsonwebtoken::Header::default(),
        &json!({"sub":actor,"iat":issued,"nbf":issued,"exp":if expired {now-1} else {now+3600},
            "iss":"credito-backend","aud":"credito-api"}),
        &jsonwebtoken::EncodingKey::from_secret(SECRET.as_bytes()),
    )
    .unwrap()
}

fn client(actor: &str) -> reqwest::Client {
    let mut headers = HeaderMap::new();
    headers.insert(
        "authorization",
        format!("Bearer {}", token(actor, false)).parse().unwrap(),
    );
    reqwest::Client::builder()
        .default_headers(headers)
        .build()
        .unwrap()
}

async fn body(response: reqwest::Response, expected: StatusCode) -> Value {
    let status = response.status();
    let body = response.text().await.unwrap();
    assert_eq!(status, expected, "Respuesta: {body}");
    serde_json::from_str(&body).unwrap()
}

async fn create_credit(api: &RunningServer) -> Value {
    body(
        client("admin")
            .post(format!("{}/api/creditos", api.url))
            .json(&json!({"oferta_id":"oferta"}))
            .send()
            .await
            .unwrap(),
        StatusCode::CREATED,
    )
    .await
}

async fn pay(
    api: &RunningServer,
    id: &str,
    reference: &str,
    amount: i64,
    expected: StatusCode,
) -> Value {
    body(
        client("pyme")
            .post(format!("{}/api/creditos/{id}/pagos", api.url))
            .json(&json!({"referencia":reference, "monto_centavos":amount}))
            .send()
            .await
            .unwrap(),
        expected,
    )
    .await
}

// El contrato deja que el cliente reenvíe la misma referencia tras un 409 de revisión.
async fn pay_with_conflict_retry(
    api: &RunningServer,
    id: &str,
    reference: &str,
    amount: i64,
) -> Value {
    let response = client("pyme")
        .post(format!("{}/api/creditos/{id}/pagos", api.url))
        .json(&json!({"referencia":reference, "monto_centavos":amount}))
        .send()
        .await
        .unwrap();
    if response.status() == StatusCode::CONFLICT {
        pay(api, id, reference, amount, StatusCode::OK).await
    } else {
        body(response, StatusCode::OK).await
    }
}

#[tokio::test]
async fn full_credit_lifecycle_conserves_money_and_filters_investor_data() {
    let (api, _couch, db) = setup().await;
    let created = create_credit(&api).await;
    let credit = &created["credito"];
    let id = credit["id"].as_str().unwrap();
    assert_eq!(created["sincronizacion_pendiente"], false);
    assert_eq!(credit["capital_centavos"], 100000);
    assert_eq!(credit["interes_centavos"], 1000);
    assert_eq!(credit["tasa_anual_bp"], 3650);
    assert_eq!(credit["total_centavos"], 101000);
    assert_eq!(credit["saldo_centavos"], 101000);
    assert_eq!(credit["estado"], "activo");
    assert_eq!(credit["vencido"], false);
    assert_eq!(credit["dias_mora"], 0);
    assert!(credit.get("_rev").is_none());
    assert_eq!(credit["participaciones"][0]["interes_centavos"], 600);
    assert_eq!(credit["participaciones"][1]["interes_centavos"], 400);
    {
        let db = db.lock().unwrap();
        assert_eq!(db.credits().len(), 1);
        assert_eq!(db.document("ofertas", "oferta")["estado"], "financiada");
        assert_eq!(db.document("facturas", "factura")["estado"], "financiada");
        assert_eq!(
            db.document("facturas", "factura")["monto_financiado_centavos"],
            100000
        );
        assert_eq!(
            db.document("facturas", "factura")["campo_ajeno"],
            "conservar"
        );
    }
    let duplicate = create_credit(&api).await;
    assert_eq!(duplicate["credito"], *credit);
    assert_eq!(db.lock().unwrap().credits().len(), 1);
    let partial = pay(&api, id, "CUOTA-1", 40000, StatusCode::OK).await;
    assert_eq!(partial["credito"]["pagado_centavos"], 40000);
    assert_eq!(partial["credito"]["saldo_centavos"], 61000);
    assert_eq!(partial["credito"]["pagos"].as_array().unwrap().len(), 1);
    let replay = pay(&api, id, "CUOTA-1", 40000, StatusCode::OK).await;
    assert_eq!(partial, replay);
    pay(&api, id, "CUOTA-1", 40001, StatusCode::CONFLICT).await;
    pay(&api, id, "EXCESO", 61001, StatusCode::BAD_REQUEST).await;
    let investor = body(
        client("inversor")
            .get(format!("{}/api/creditos/{id}", api.url))
            .send()
            .await
            .unwrap(),
        StatusCode::OK,
    )
    .await;
    assert!(investor.get("pagos").is_none());
    assert!(investor.get("inversionistas_ids").is_none());
    assert!(!investor.to_string().contains("segundo-inversor"));
    assert_eq!(investor["participaciones"].as_array().unwrap().len(), 1);
    assert_eq!(
        investor["participaciones"][0]["inversionista_id"],
        "inversor"
    );
    let complete = pay(&api, id, "CUOTA-2", 61000, StatusCode::OK).await;
    assert_eq!(complete["sincronizacion_pendiente"], false);
    assert_eq!(complete["credito"]["estado"], "pagado");
    assert_eq!(complete["credito"]["saldo_centavos"], 0);
    assert_eq!(complete["credito"]["pagado_centavos"], 101000);
    assert_eq!(complete["credito"]["pagos"].as_array().unwrap().len(), 2);
    assert!(complete["credito"]["fecha_pago_total"].as_str().is_some());
    // La última cuota también debe ser repetible cuando el crédito ya está pagado.
    assert_eq!(
        pay(&api, id, "CUOTA-2", 61000, StatusCode::OK).await,
        complete
    );
    let db = db.lock().unwrap();
    assert_eq!(db.document("facturas", "factura")["estado"], "pagada");
    for (investment, interest) in [("aporte-1", 6.0), ("aporte-2", 4.0)] {
        let document = db.document("operaciones", investment);
        assert_eq!(document["estado"], "liquidada");
        assert_eq!(document["rendimiento_real"], interest);
        assert!(document["fecha_liquidacion"].as_str().is_some());
        assert_eq!(document["campo_ajeno"], "conservar");
    }
    let saved = db.credits()[0];
    let sum: i64 = saved["pagos"]
        .as_array()
        .unwrap()
        .iter()
        .map(|p| p["monto_centavos"].as_i64().unwrap())
        .sum();
    assert_eq!(saved["pagado_centavos"], sum);
}

#[tokio::test]
async fn authentication_and_ownership_protect_all_mutations() {
    let (api, _couch, db) = setup().await;
    for path in [
        "/api/creditos",
        "/api/creditos/ausente/pagos",
        "/api/creditos/ausente/sincronizar",
        "/api/creditos/aportes/aporte-1/confirmar",
    ] {
        for auth in [
            None,
            Some(format!("Bearer {}", token("admin", true))),
            Some(format!("Bearer {}", token("inactivo", false))),
        ] {
            let mut request = reqwest::Client::new().post(format!("{}{path}", api.url));
            if let Some(auth) = auth {
                request = request.header("authorization", auth);
            }
            assert_eq!(
                request.json(&json!({})).send().await.unwrap().status(),
                StatusCode::UNAUTHORIZED
            );
        }
    }
    for actor in ["pyme", "otra-pyme", "inversor"] {
        body(
            client(actor)
                .post(format!("{}/api/creditos", api.url))
                .json(&json!({"oferta_id":"oferta"}))
                .send()
                .await
                .unwrap(),
            StatusCode::FORBIDDEN,
        )
        .await;
    }
    assert!(db.lock().unwrap().writes.is_empty());
    let created = create_credit(&api).await;
    let id = created["credito"]["id"].as_str().unwrap();
    let writes = db.lock().unwrap().writes.len();
    for actor in ["otra-pyme", "ajeno"] {
        body(
            client(actor)
                .get(format!("{}/api/creditos/{id}", api.url))
                .send()
                .await
                .unwrap(),
            StatusCode::FORBIDDEN,
        )
        .await;
    }
    for actor in ["inversor", "segundo-inversor", "otra-pyme", "ajeno"] {
        let response = client(actor)
            .post(format!("{}/api/creditos/{id}/pagos", api.url))
            .json(&json!({"referencia":"NO-AUTORIZADO", "monto_centavos":100}))
            .send()
            .await
            .unwrap();
        assert!(matches!(
            response.status(),
            StatusCode::NOT_FOUND | StatusCode::FORBIDDEN
        ));
    }
    assert_eq!(db.lock().unwrap().writes.len(), writes);
    let admin_payment = body(
        client("admin")
            .post(format!("{}/api/creditos/{id}/pagos", api.url))
            .json(&json!({"referencia":"ADMIN-1", "monto_centavos":100}))
            .send()
            .await
            .unwrap(),
        StatusCode::OK,
    )
    .await;
    assert_eq!(
        admin_payment["credito"]["pagos"][0]["registrado_por"],
        "admin"
    );
}

#[tokio::test]
async fn funding_preconditions_prevent_issuing_invalid_credit() {
    let (api, _couch, db) = setup().await;
    for (collection, id, field, value) in [
        ("empresas", "empresa", "estado", json!("pendiente")),
        (
            "facturas",
            "factura",
            "estado",
            json!("pendiente_verificacion"),
        ),
        (
            "facturas",
            "factura",
            "dte",
            json!({"codigo_generacion":"TEST", "verificado":false}),
        ),
        (
            "facturas",
            "factura",
            "fecha_vencimiento",
            json!((Utc::now() - Duration::days(1)).date_naive()),
        ),
        ("ofertas", "oferta", "estado", json!("abierta")),
        ("ofertas", "oferta", "monto_recaudado", json!(999.0)),
        ("operaciones", "aporte-1", "estado", json!("pago_pendiente")),
        ("operaciones", "aporte-1", "monto", json!(599.0)),
        ("operaciones", "aporte-1", "moneda", json!("EUR")),
        (
            "operaciones",
            "aporte-1",
            "factura_id",
            json!("otra-factura"),
        ),
    ] {
        {
            let mut db = db.lock().unwrap();
            *db = fixtures();
            db.document_mut(collection, id)[field] = value.clone();
        }
        let response = client("admin")
            .post(format!("{}/api/creditos", api.url))
            .json(&json!({"oferta_id":"oferta"}))
            .send()
            .await
            .unwrap();
        assert_eq!(
            response.status(),
            if field == "fecha_vencimiento" {
                StatusCode::BAD_REQUEST
            } else {
                StatusCode::CONFLICT
            },
            "{collection}/{id}.{field} = {value}: {}",
            response.text().await.unwrap()
        );
        assert!(db.lock().unwrap().credits().is_empty());
        assert!(db.lock().unwrap().writes.is_empty());
    }
}

#[tokio::test]
async fn payment_projection_failure_keeps_ledger_and_retry_recovers_without_duplicate() {
    let (api, _couch, db) = setup().await;
    let created = create_credit(&api).await;
    let id = created["credito"]["id"].as_str().unwrap();
    db.lock().unwrap().fail_writes = Some("facturas".into());
    let paid = pay(&api, id, "PAGO-COMPLETO", 101000, StatusCode::OK).await;
    assert_eq!(paid["sincronizacion_pendiente"], true);
    assert_eq!(paid["credito"]["estado"], "pagado");
    assert_eq!(db.lock().unwrap().credits()[0]["pagado_centavos"], 101000);
    let writes = db.lock().unwrap().writes.len();
    // La lectura no tiene efectos secundarios, incluso con proyecciones pendientes.
    let read = body(
        client("pyme")
            .get(format!("{}/api/creditos/{id}", api.url))
            .send()
            .await
            .unwrap(),
        StatusCode::OK,
    )
    .await;
    assert_eq!(read["saldo_centavos"], 0);
    assert_eq!(db.lock().unwrap().writes.len(), writes);
    db.lock().unwrap().fail_writes = None;
    let recovered = pay(&api, id, "PAGO-COMPLETO", 101000, StatusCode::OK).await;
    assert_eq!(recovered["sincronizacion_pendiente"], false);
    assert_eq!(recovered["credito"], paid["credito"]);
    let db = db.lock().unwrap();
    assert_eq!(db.credits()[0]["pagos"].as_array().unwrap().len(), 1);
    assert_eq!(db.document("facturas", "factura")["estado"], "pagada");
    assert_eq!(
        db.document("operaciones", "aporte-1")["estado"],
        "liquidada"
    );
    assert_eq!(
        db.document("operaciones", "aporte-2")["estado"],
        "liquidada"
    );
}

#[tokio::test]
async fn creation_with_missing_audit_is_recoverable_by_explicit_sync() {
    let (api, _couch, db) = setup().await;
    db.lock().unwrap().fail_writes = Some("auditoria".into());
    let created = create_credit(&api).await;
    let id = created["credito"]["id"].as_str().unwrap();
    assert_eq!(created["sincronizacion_pendiente"], true);
    assert_eq!(db.lock().unwrap().credits().len(), 1);
    db.lock().unwrap().fail_writes = None;
    let synced = body(
        client("admin")
            .post(format!("{}/api/creditos/{id}/sincronizar", api.url))
            .send()
            .await
            .unwrap(),
        StatusCode::OK,
    )
    .await;
    assert_eq!(synced["sincronizacion_pendiente"], false);
    assert_eq!(synced["credito"], created["credito"]);
    let audit_count = db
        .lock()
        .unwrap()
        .documents
        .keys()
        .filter(|(base, _)| base == "auditoria")
        .count();
    assert!(audit_count > 0);
    let again = body(
        client("admin")
            .post(format!("{}/api/creditos/{id}/sincronizar", api.url))
            .send()
            .await
            .unwrap(),
        StatusCode::OK,
    )
    .await;
    assert_eq!(synced, again);
    assert_eq!(
        db.lock()
            .unwrap()
            .documents
            .keys()
            .filter(|(base, _)| base == "auditoria")
            .count(),
        audit_count
    );
}

#[tokio::test]
async fn concurrent_and_retried_payments_never_overwrite_history() {
    let (api, _couch, db) = setup().await;
    let created = create_credit(&api).await;
    let id = created["credito"]["id"].as_str().unwrap();
    db.lock().unwrap().ledger_conflicts = 1;
    pay(
        &api,
        id,
        "CONFLICTO-RECUPERABLE",
        1000,
        StatusCode::CONFLICT,
    )
    .await;
    assert_eq!(db.lock().unwrap().credits()[0]["pagado_centavos"], 0);
    pay(&api, id, "CONFLICTO-RECUPERABLE", 1000, StatusCode::OK).await;
    let (first, second) = tokio::join!(
        pay_with_conflict_retry(&api, id, "PARALELO-A", 40000),
        pay_with_conflict_retry(&api, id, "PARALELO-B", 30000),
    );
    assert_eq!(first["credito"]["estado"], "activo");
    assert_eq!(second["credito"]["estado"], "activo");
    let saved = db.lock().unwrap().credits()[0].clone();
    assert_eq!(saved["pagado_centavos"], 71000);
    assert_eq!(saved["pagos"].as_array().unwrap().len(), 3);
    let (same_a, same_b) = tokio::join!(
        pay_with_conflict_retry(&api, id, "MISMA-REFERENCIA", 30000),
        pay_with_conflict_retry(&api, id, "MISMA-REFERENCIA", 30000),
    );
    assert_eq!(same_a["credito"], same_b["credito"]);
    let db = db.lock().unwrap();
    let saved = db.credits()[0];
    assert_eq!(saved["pagado_centavos"], 101000);
    assert_eq!(saved["pagos"].as_array().unwrap().len(), 4);
    assert_eq!(db.document("facturas", "factura")["estado"], "pagada");
}

#[tokio::test]
async fn contribution_confirmation_is_owned_simulated_and_idempotent() {
    let (api, _couch, db) = setup().await;
    db.lock().unwrap().document_mut("operaciones", "aporte-1")["estado"] = json!("pago_pendiente");
    let url = format!("{}/api/creditos/aportes/aporte-1/confirmar", api.url);
    for actor in ["pyme", "otra-pyme", "segundo-inversor"] {
        let response = client(actor).post(&url).send().await.unwrap();
        assert!(matches!(
            response.status(),
            StatusCode::FORBIDDEN | StatusCode::NOT_FOUND
        ));
    }
    assert!(db.lock().unwrap().writes.is_empty());
    let first = body(
        client("inversor").post(&url).send().await.unwrap(),
        StatusCode::OK,
    )
    .await;
    assert_eq!(first["estado"], "confirmada");
    assert_eq!(first["simulado"], true);
    let saved = db
        .lock()
        .unwrap()
        .document("operaciones", "aporte-1")
        .clone();
    assert_eq!(saved["pago_simulado"], true);
    assert_eq!(saved["confirmado_por"], "inversor");
    assert!(saved["fecha_confirmacion_pago"].as_str().is_some());
    assert_eq!(saved["campo_ajeno"], "conservar");
    let again = body(
        client("inversor").post(&url).send().await.unwrap(),
        StatusCode::OK,
    )
    .await;
    assert_eq!(first, again);
    assert_eq!(
        *db.lock().unwrap().document("operaciones", "aporte-1"),
        saved
    );
    db.lock().unwrap().document_mut("operaciones", "aporte-2")["estado"] = json!("registrada");
    body(
        client("admin")
            .post(format!(
                "{}/api/creditos/aportes/aporte-2/confirmar",
                api.url
            ))
            .send()
            .await
            .unwrap(),
        StatusCode::OK,
    )
    .await;
    create_credit(&api).await;
}

#[tokio::test]
async fn invalid_bodies_and_pagination_do_not_mutate_any_documents() {
    let (api, _couch, db) = setup().await;
    for invalid in [
        json!({}),
        json!({"oferta_id":""}),
        json!({"oferta_id":"oferta", "estado":"pagado"}),
        json!({"oferta_id":"_all_docs"}),
    ] {
        body(
            client("admin")
                .post(format!("{}/api/creditos", api.url))
                .json(&invalid)
                .send()
                .await
                .unwrap(),
            StatusCode::BAD_REQUEST,
        )
        .await;
    }
    for query in ["limit=-1", "estado=inexistente", "campo_extra=1"] {
        body(
            client("admin")
                .get(format!("{}/api/creditos?{query}", api.url))
                .send()
                .await
                .unwrap(),
            StatusCode::BAD_REQUEST,
        )
        .await;
    }
    assert!(db.lock().unwrap().writes.is_empty());
    let created = create_credit(&api).await;
    let id = created["credito"]["id"].as_str().unwrap();
    let writes = db.lock().unwrap().writes.len();
    for invalid in [
        json!({"referencia":"", "monto_centavos":100}),
        json!({"referencia":"NEG", "monto_centavos":-1}),
        json!({"referencia":"CERO", "monto_centavos":0}),
        json!({"referencia":"FRACCION", "monto_centavos":1.5}),
        json!({"referencia":"EXTRA", "monto_centavos":100, "registrado_por":"admin"}),
    ] {
        body(
            client("pyme")
                .post(format!("{}/api/creditos/{id}/pagos", api.url))
                .json(&invalid)
                .send()
                .await
                .unwrap(),
            StatusCode::BAD_REQUEST,
        )
        .await;
    }
    assert_eq!(db.lock().unwrap().writes.len(), writes);
}

#[tokio::test]
async fn lists_only_owned_credits_and_derives_overdue_without_writes() {
    let (api, _couch, db) = setup().await;
    let created = create_credit(&api).await;
    let id = created["credito"]["id"].as_str().unwrap();
    {
        let mut db = db.lock().unwrap();
        let key = db
            .documents
            .iter()
            .find(|(_, value)| value["tipo"] == "credito")
            .unwrap()
            .0
            .clone();
        db.documents.get_mut(&key).unwrap()["fecha_vencimiento"] =
            json!((Utc::now() - Duration::days(3)).date_naive());
    }
    let writes = db.lock().unwrap().writes.len();
    for (actor, expected) in [
        ("admin", 1),
        ("pyme", 1),
        ("inversor", 1),
        ("otra-pyme", 0),
        ("ajeno", 0),
    ] {
        let list = body(
            client(actor)
                .get(format!("{}/api/creditos?limit=1", api.url))
                .send()
                .await
                .unwrap(),
            StatusCode::OK,
        )
        .await;
        assert_eq!(
            list["creditos"].as_array().unwrap().len(),
            expected,
            "actor: {actor}"
        );
        if expected == 1 {
            assert_eq!(list["creditos"][0]["id"], id);
            assert_eq!(list["creditos"][0]["vencido"], true);
            assert_eq!(list["creditos"][0]["dias_mora"], 3);
        }
    }
    let empty = body(
        client("admin")
            .get(format!("{}/api/creditos?estado=pagado", api.url))
            .send()
            .await
            .unwrap(),
        StatusCode::OK,
    )
    .await;
    assert!(empty["creditos"].as_array().unwrap().is_empty());
    assert_eq!(db.lock().unwrap().writes.len(), writes);
}

#[tokio::test]
async fn issuing_collects_every_investment_page_and_distributes_exact_integer_totals() {
    let (api, _couch, db) = setup().await;
    {
        let mut db = db.lock().unwrap();
        db.documents
            .retain(|(base, _), document| base != "operaciones" || document["tipo"] != "inversion");
        for number in 0..201 {
            let owner = if number == 200 {
                "segundo-inversor"
            } else {
                "inversor"
            };
            db.insert("operaciones", json!({"_id":format!("aporte-{number:04}"), "_rev":"1-test", "tipo":"inversion",
                "oferta_id":"oferta", "factura_id":"factura", "inversionista_id":owner,
                "monto":if number == 200 { 0.01 } else { 5.0 }, "moneda":"USD", "estado":"confirmada",
                "fecha_creacion":Utc::now(), "fecha_liquidacion":null, "rendimiento_real":null}));
        }
        db.document_mut("ofertas", "oferta")["monto_objetivo"] = json!(1000.01);
        db.document_mut("ofertas", "oferta")["monto_recaudado"] = json!(1000.01);
    }
    let created = create_credit(&api).await;
    assert_eq!(created["credito"]["capital_centavos"], 100001);
    assert_eq!(created["credito"]["interes_centavos"], 1000);
    let shares = created["credito"]["participaciones"].as_array().unwrap();
    assert_eq!(shares.len(), 201);
    assert_eq!(
        shares
            .iter()
            .map(|share| share["capital_centavos"].as_i64().unwrap())
            .sum::<i64>(),
        100001
    );
    assert_eq!(
        shares
            .iter()
            .map(|share| share["interes_centavos"].as_i64().unwrap())
            .sum::<i64>(),
        1000
    );
    assert!(shares
        .iter()
        .all(|share| share["interes_centavos"].as_i64().unwrap() >= 0));
}

#[tokio::test]
async fn competing_payments_cannot_together_exceed_outstanding_balance() {
    let (api, _couch, db) = setup().await;
    let created = create_credit(&api).await;
    let id = created["credito"]["id"].as_str().unwrap();
    let url = format!("{}/api/creditos/{id}/pagos", api.url);
    let payer = client("pyme");
    let first = payer
        .post(&url)
        .json(&json!({"referencia":"A", "monto_centavos":60000}));
    let second = payer
        .post(&url)
        .json(&json!({"referencia":"B", "monto_centavos":60000}));
    let (first, second) = tokio::join!(first.send(), second.send());
    let mut statuses = [
        first.unwrap().status().as_u16(),
        second.unwrap().status().as_u16(),
    ];
    statuses.sort();
    assert!(matches!(statuses, [200, 400] | [200, 409]));
    let db = db.lock().unwrap();
    assert_eq!(db.credits()[0]["pagado_centavos"], 60000);
    assert_eq!(db.credits()[0]["pagos"].as_array().unwrap().len(), 1);
}

#[tokio::test]
async fn stale_projection_cannot_reopen_paid_invoice() {
    let (api, couch, db) = setup().await;
    let created = create_credit(&api).await;
    let id = created["credito"]["id"].as_str().unwrap();
    let stale: super::model::CreditoDocumento =
        serde_json::from_value(db.lock().unwrap().credits()[0].clone()).unwrap();
    pay(&api, id, "TOTAL", 101000, StatusCode::OK).await;
    let paid_invoice = db.lock().unwrap().document("facturas", "factura").clone();
    let connection = CouchDb::from_parts(couch.url.clone(), "test".into(), "test".into()).unwrap();
    let repository = CreditoRepository::from_connection(&connection).unwrap();
    repository
        .project(
            "facturas",
            "factura",
            "factura",
            &stale,
            json!({"estado":"financiada"}),
        )
        .await
        .unwrap();
    assert_eq!(
        *db.lock().unwrap().document("facturas", "factura"),
        paid_invoice
    );
    assert_eq!(paid_invoice["estado"], "pagada");
}

#[tokio::test]
async fn distinct_offers_cannot_create_two_debts_for_one_invoice() {
    let (api, _couch, db) = setup().await;
    create_credit(&api).await;
    {
        let mut db = db.lock().unwrap();
        let mut another = db.document("ofertas", "oferta").clone();
        another["_id"] = json!("otra-oferta");
        another["estado"] = json!("objetivo_alcanzado");
        db.insert("ofertas", another);
    }
    body(
        client("admin")
            .post(format!("{}/api/creditos", api.url))
            .json(&json!({"oferta_id":"otra-oferta"}))
            .send()
            .await
            .unwrap(),
        StatusCode::CONFLICT,
    )
    .await;
    assert_eq!(db.lock().unwrap().credits().len(), 1);
}

#[test]
fn dollar_adapter_rejects_non_finite_or_fractional_cent_amounts() {
    use super::service::centavos;
    for (dollars, cents) in [(0.01, 1), (12.34, 1234), (999999.99, 99999999)] {
        assert_eq!(centavos(dollars).unwrap(), cents);
    }
    for invalid in [
        f64::NAN,
        f64::INFINITY,
        f64::NEG_INFINITY,
        -1.0,
        0.0,
        0.001,
        1.234,
        1e15,
    ] {
        assert!(centavos(invalid).is_err(), "Debe rechazar {invalid}");
    }
}

#[test]
fn interest_uses_actual_days_365_and_rounds_half_cents_up() {
    use super::service::calcular_interes;
    assert_eq!(calcular_interes(100000, 1000, 365).unwrap(), 10000);
    assert_eq!(calcular_interes(100000, 3650, 10).unwrap(), 1000);
    assert_eq!(calcular_interes(100, 5000, 365).unwrap(), 50);
    assert_eq!(calcular_interes(1, 5000, 365).unwrap(), 1);
    assert_eq!(calcular_interes(1, 4999, 365).unwrap(), 0);
    assert_eq!(calcular_interes(100000, 0, 365).unwrap(), 0);
    for (capital, rate, days) in [
        (0, 1000, 365),
        (100, -1, 365),
        (100, 10001, 365),
        (100, 1000, 0),
    ] {
        assert!(calcular_interes(capital, rate, days).is_err());
    }
}
