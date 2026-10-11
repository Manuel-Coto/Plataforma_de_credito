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
use chrono::{NaiveDate, Utc};
use serde_json::{json, Value};
use tokio::task::JoinHandle;

use super::{
    model::{AuditoriaQuery, Modulo, ReporteModulo},
    repository::AdministracionRepository,
    routes,
    service::{accumulate, AdministracionService},
    AdministracionError,
};
use crate::{
    database::connection::CouchDb,
    modules::usuarios::{
        model::{EstadoUsuario, Rol, Usuario},
        service::UsuarioService,
    },
};

#[derive(Default)]
struct MockDb {
    documents: BTreeMap<String, Vec<Value>>,
    requests: Vec<(String, Value)>,
    page_cap: Option<usize>,
    stuck_bookmark: bool,
    failure: Option<StatusCode>,
}
type Db = Arc<Mutex<MockDb>>;

async fn find(
    State(state): State<Db>,
    Path(database): Path<String>,
    headers: HeaderMap,
    Json(query): Json<Value>,
) -> (StatusCode, Json<Value>) {
    assert_eq!(headers["authorization"], "Basic dGVzdDp0ZXN0");
    let mut db = state.lock().unwrap();
    db.requests.push((database.clone(), query.clone()));
    if let Some(status) = db.failure {
        return (
            status,
            Json(json!({"error":"upstream", "reason":"secret-in-error"})),
        );
    }
    let offset = query["bookmark"]
        .as_str()
        .and_then(|s| s.parse::<usize>().ok())
        .unwrap_or(0);
    let limit = (query["limit"].as_u64().unwrap() as usize).min(db.page_cap.unwrap_or(usize::MAX));
    let docs: Vec<_> = db
        .documents
        .get(&database)
        .into_iter()
        .flatten()
        .filter(|doc| {
            query["selector"]
                .as_object()
                .unwrap()
                .iter()
                .all(|(key, value)| value.is_object() || doc[key] == *value)
        })
        .skip(offset)
        .take(limit)
        .map(|doc| {
            let fields = query["fields"].as_array().unwrap();
            assert!(!fields
                .iter()
                .any(|f| matches!(f.as_str(), Some("password_hash" | "correo" | "nombre"))));
            let projected = fields
                .iter()
                .filter_map(|f| {
                    let key = f.as_str().unwrap();
                    doc.get(key).map(|value| (key.into(), value.clone()))
                })
                .collect::<serde_json::Map<String, Value>>();
            Value::Object(projected)
        })
        .collect();
    let bookmark = if db.stuck_bookmark {
        "0".to_string()
    } else {
        (offset + docs.len()).to_string()
    };
    (
        StatusCode::OK,
        Json(json!({"docs": docs, "bookmark": bookmark})),
    )
}

async fn user_read(Path(id): Path<String>) -> Json<Value> {
    let role = match id.as_str() {
        "pyme" => "pyme",
        "inversionista" => "inversionista",
        _ => "administrador",
    };
    Json(
        json!({"_id":id, "_rev":"1-test", "nombre":"Prueba", "correo":"prueba@example.test", "password_hash":"private-hash", "rol":role,
        "estado":if id == "inactivo" { "inactivo" } else { "activo" }, "fecha_creacion":"2026-01-01T00:00:00Z", "fecha_actualizacion":"2026-01-01T00:00:00Z"}),
    )
}

// La rama estática /usuarios/{id} tiene prioridad sobre /{database}/_find en Axum.
// Registrar /usuarios/_find explícitamente reproduce los métodos CouchDB reales.
async fn find_users(
    state: State<Db>,
    headers: HeaderMap,
    query: Json<Value>,
) -> (StatusCode, Json<Value>) {
    find(state, Path("usuarios".into()), headers, query).await
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

async fn setup() -> (RunningServer, Db, AdministracionService) {
    let db = Db::default();
    let couch = serve(
        Router::new()
            .route("/{database}/_find", post(find))
            .route("/usuarios/_find", post(find_users))
            .route("/usuarios/{id}", get(user_read))
            .with_state(db.clone()),
    )
    .await;
    let connection = CouchDb::from_parts(couch.url.clone(), "test".into(), "test".into()).unwrap();
    let service = AdministracionService::new(Some(
        AdministracionRepository::from_connection(&connection).unwrap(),
    ));
    (couch, db, service)
}

fn user(rol: Rol) -> Usuario {
    Usuario {
        id: "admin".into(),
        nombre: "Prueba".into(),
        correo: "prueba@example.test".into(),
        rol,
        estado: EstadoUsuario::Activo,
        fecha_creacion: Utc::now(),
        fecha_actualizacion: Utc::now(),
    }
}

fn credit() -> Value {
    json!({"_id":"credito-1", "tipo":"credito", "estado":"activo", "moneda":"USD", "capital_centavos":10000,
        "interes_centavos":500, "total_centavos":10500, "pagado_centavos":2500, "fecha_vencimiento":"2026-01-01",
        "pagos":[{"id":"pago-1", "monto_centavos":1000}, {"id":"pago-2", "monto_centavos":1500}]})
}

#[tokio::test]
async fn report_reads_every_page_including_short_pages_without_exposing_profiles() {
    let (_couch, db, service) = setup().await;
    {
        let mut state = db.lock().unwrap();
        state.page_cap = Some(17);
        state.documents.insert("usuarios".into(), (0..135).map(|i| json!({"_id":format!("usuario-{i}"), "rol":"pyme", "estado":"activo", "password_hash":"secret-hash", "correo":"private@example.test"})).collect());
    }
    let report = service
        .reporte(&user(Rol::Administrador), Modulo::Usuarios)
        .await
        .unwrap();
    assert_eq!(report.total, 135);
    assert_eq!(report.por_rol["pyme"], 135);
    let serialized = serde_json::to_string(&report).unwrap();
    assert!(!serialized.contains("secret-hash") && !serialized.contains("private@example.test"));
    let state = db.lock().unwrap();
    assert_eq!(state.requests.len(), 9);
    assert_eq!(state.requests[1].1["bookmark"], "17");
    assert_eq!(state.requests[0].1["limit"], 100);
}

#[tokio::test]
async fn summary_covers_all_modules_and_keeps_operations_types_separate() {
    let (_couch, db, service) = setup().await;
    {
        let mut state = db.lock().unwrap();
        state.documents.insert(
            "usuarios".into(),
            vec![json!({"_id":"u1", "estado":"activo", "rol":"pyme"})],
        );
        state.documents.insert(
            "empresas".into(),
            vec![json!({"_id":"e1", "estado":"aprobada"})],
        );
        state.documents.insert("facturas".into(), vec![json!({"_id":"f1", "tipo":"factura", "estado":"financiada", "moneda":"USD", "monto_total_centavos":10000, "monto_financiado_centavos":10000})]);
        state.documents.insert("ofertas".into(), vec![json!({"_id":"o1", "tipo":"oferta", "estado":"financiada", "moneda":"USD", "monto_objetivo":100, "monto_recaudado":100})]);
        state.documents.insert("operaciones".into(), vec![credit(), json!({"_id":"i1", "tipo":"inversion", "estado":"confirmada", "moneda":"USD", "monto":100})]);
        state.documents.insert(
            "auditoria".into(),
            vec![json!({"_id":"a1", "tipo":"evento"})],
        );
    }
    let report = service.resumen(&user(Rol::Administrador)).await.unwrap();
    assert_eq!(report.reportes.len(), 8);
    for entry in &report.reportes {
        assert_eq!(
            entry.total,
            if entry.modulo == Modulo::Pagos { 2 } else { 1 }
        );
    }
    let payments = report
        .reportes
        .iter()
        .find(|r| r.modulo == Modulo::Pagos)
        .unwrap();
    assert_eq!(payments.montos_por_moneda["USD"]["pagado_centavos"], 2500);
}

#[test]
fn legacy_companies_without_state_are_reported_as_pending() {
    let mut report = ReporteModulo::new(Modulo::Empresas);
    accumulate(
        &mut report,
        &json!({"_id":"legacy-company"}),
        Utc::now().date_naive(),
    )
    .unwrap();
    assert_eq!(report.total, 1);
    assert_eq!(report.por_estado["pendiente"], 1);
    assert!(matches!(
        accumulate(
            &mut report,
            &json!({"estado":null}),
            Utc::now().date_naive()
        ),
        Err(AdministracionError::Upstream)
    ));
}

#[test]
fn credit_balances_and_past_due_are_derived_and_currencies_do_not_mix() {
    let today = NaiveDate::from_ymd_opt(2026, 2, 1).unwrap();
    let mut report = ReporteModulo::new(Modulo::Creditos);
    accumulate(&mut report, &credit(), today).unwrap();
    let mut paid = credit();
    paid["estado"] = json!("pagado");
    paid["pagado_centavos"] = json!(10500);
    paid["moneda"] = json!("EUR");
    accumulate(&mut report, &paid, today).unwrap();
    assert_eq!(report.por_estado["vencido"], 1);
    assert_eq!(report.por_estado["pagado"], 1);
    assert_eq!(report.montos_por_moneda["USD"]["saldo_centavos"], 8000);
    assert_eq!(report.montos_por_moneda["EUR"]["saldo_centavos"], 0);
    let mut due_today = credit();
    due_today["fecha_vencimiento"] = json!(today.to_string());
    accumulate(&mut report, &due_today, today).unwrap();
    assert_eq!(report.por_estado["activo"], 1);
}

#[test]
fn report_rejects_corrupt_amounts_and_overflow_instead_of_returning_wrong_totals() {
    let today = Utc::now().date_naive();
    let mut report = ReporteModulo::new(Modulo::Facturas);
    let doc = json!({"estado":"disponible", "moneda":"USD", "monto_total_centavos":i64::MAX});
    accumulate(&mut report, &doc, today).unwrap();
    assert!(matches!(
        accumulate(&mut report, &doc, today),
        Err(AdministracionError::Upstream)
    ));
    let mut doc = credit();
    doc["pagado_centavos"] = json!(11000);
    assert!(matches!(
        accumulate(&mut ReporteModulo::new(Modulo::Creditos), &doc, today),
        Err(AdministracionError::Upstream)
    ));
    let investment = json!({"estado":"confirmada", "moneda":"USD", "monto":12.34});
    let mut investments = ReporteModulo::new(Modulo::Inversiones);
    accumulate(&mut investments, &investment, today).unwrap();
    assert_eq!(
        investments.montos_por_moneda["USD"]["invertido_centavos"],
        1234
    );
}

#[tokio::test]
async fn audit_filters_and_paginates_and_drops_sensitive_details() {
    let (_couch, db, service) = setup().await;
    db.lock().unwrap().documents.insert("auditoria".into(), (0..3).map(|i| json!({"_id":format!("evt-{i}"), "tipo":"evento", "actor_id":"admin", "accion":"pago_registrado", "recurso_tipo":"credito", "recurso_id":"credito-1", "fecha":"2026-01-01T00:00:00Z",
        "detalles":{"moneda":"USD", "monto_centavos":1000, "password_hash":"sensitive-value", "token":"sensitive-value", "documento":{"correo":"sensitive-value"}}})).collect());
    let first = service
        .auditoria(
            &user(Rol::Administrador),
            AuditoriaQuery {
                limit: Some(2),
                actor_id: Some("admin".into()),
                recurso_id: Some("credito-1".into()),
                ..Default::default()
            },
        )
        .await
        .unwrap();
    assert_eq!(first.eventos.len(), 2);
    assert_eq!(first.eventos[0].detalles.len(), 2);
    assert!(!serde_json::to_string(&first)
        .unwrap()
        .contains("sensitive-value"));
    let second = service
        .auditoria(
            &user(Rol::Administrador),
            AuditoriaQuery {
                limit: Some(2),
                bookmark: Some(first.bookmark),
                actor_id: Some("admin".into()),
                recurso_id: Some("credito-1".into()),
            },
        )
        .await
        .unwrap();
    assert_eq!(second.eventos.len(), 1);
    assert_eq!(second.eventos[0].id, "evt-2");
    let absent = service
        .auditoria(
            &user(Rol::Administrador),
            AuditoriaQuery {
                actor_id: Some("otro".into()),
                ..Default::default()
            },
        )
        .await
        .unwrap();
    assert!(absent.eventos.is_empty());
}

#[tokio::test]
async fn report_fails_on_repeated_bookmark_and_unavailable_database() {
    let (_couch, db, service) = setup().await;
    {
        let mut state = db.lock().unwrap();
        state.stuck_bookmark = true;
        state.documents.insert(
            "empresas".into(),
            vec![json!({"_id":"e1", "estado":"aprobada"})],
        );
    }
    assert!(matches!(
        service
            .reporte(&user(Rol::Administrador), Modulo::Empresas)
            .await,
        Err(AdministracionError::Upstream)
    ));
    db.lock().unwrap().failure = Some(StatusCode::NOT_FOUND);
    assert!(matches!(
        service.resumen(&user(Rol::Administrador)).await,
        Err(AdministracionError::Unavailable)
    ));
}

#[tokio::test]
async fn roles_and_query_validation_run_before_database_access() {
    let service = AdministracionService::new(None);
    for role in [Rol::Pyme, Rol::Inversionista] {
        assert!(matches!(
            service.resumen(&user(role)).await,
            Err(AdministracionError::Forbidden)
        ));
        assert!(matches!(
            service.reporte(&user(role), Modulo::Usuarios).await,
            Err(AdministracionError::Forbidden)
        ));
        assert!(matches!(
            service.auditoria(&user(role), Default::default()).await,
            Err(AdministracionError::Forbidden)
        ));
    }
    assert!(matches!(
        service
            .auditoria(
                &user(Rol::Administrador),
                AuditoriaQuery {
                    limit: Some(101),
                    ..Default::default()
                }
            )
            .await,
        Err(AdministracionError::Invalid(_))
    ));
    let mut inactive = user(Rol::Administrador);
    inactive.estado = EstadoUsuario::Inactivo;
    assert!(matches!(
        service.resumen(&inactive).await,
        Err(AdministracionError::Forbidden)
    ));
    assert!(matches!(
        service.resumen(&user(Rol::Administrador)).await,
        Err(AdministracionError::Configuration)
    ));
}

const TEST_SECRET: &str = "secreto-ficticio-de-pruebas-con-32-caracteres";
fn token(id: &str) -> String {
    let now = Utc::now().timestamp();
    jsonwebtoken::encode(&jsonwebtoken::Header::default(), &json!({"sub":id,"iat":now,"nbf":now,"exp":now+3600,"iss":"credito-backend","aud":"credito-api"}), &jsonwebtoken::EncodingKey::from_secret(TEST_SECRET.as_bytes())).unwrap()
}

#[tokio::test]
async fn http_requires_active_admin_for_every_endpoint_and_validates_module() {
    let (couch, _db, service) = setup().await;
    let users = UsuarioService::for_test(&couch.url, TEST_SECRET).await;
    let api = serve(routes::router(service, users)).await;
    let client = reqwest::Client::new();
    for endpoint in ["resumen", "reportes?modulo=usuarios", "auditoria"] {
        let url = format!("{}/api/administracion/{endpoint}", api.url);
        assert_eq!(
            client.get(&url).send().await.unwrap().status(),
            StatusCode::UNAUTHORIZED
        );
        for role in ["pyme", "inversionista"] {
            assert_eq!(
                client
                    .get(&url)
                    .bearer_auth(token(role))
                    .send()
                    .await
                    .unwrap()
                    .status(),
                StatusCode::FORBIDDEN
            );
        }
        assert_eq!(
            client
                .get(&url)
                .bearer_auth(token("inactivo"))
                .send()
                .await
                .unwrap()
                .status(),
            StatusCode::UNAUTHORIZED
        );
        let response = client
            .get(&url)
            .bearer_auth(token("admin"))
            .send()
            .await
            .unwrap();
        assert_eq!(response.status(), StatusCode::OK);
        assert_eq!(response.headers()["cache-control"], "no-store");
    }
    let response = client
        .get(format!(
            "{}/api/administracion/reportes?modulo=no-existe",
            api.url
        ))
        .bearer_auth(token("admin"))
        .send()
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::BAD_REQUEST);
}
