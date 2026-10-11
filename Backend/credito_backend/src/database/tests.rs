use super::{
    connection::CouchDb,
    init::{inicializar_bases, InitError, BASES},
};
use axum::{
    extract::{Path, State},
    http::{HeaderMap, StatusCode},
    routing::{post, put},
    Json, Router,
};
use serde_json::{json, Value};
use std::sync::{Arc, Mutex};

#[derive(Default)]
struct Mock {
    calls: Vec<(String, Option<Value>)>,
    existing: bool,
    failure: Option<u16>,
    invalid_index: bool,
}
type Shared = Arc<Mutex<Mock>>;
async fn database(
    State(state): State<Shared>,
    Path(base): Path<String>,
    headers: HeaderMap,
) -> StatusCode {
    assert_eq!(headers["authorization"], "Basic dGVzdDp0ZXN0");
    let mut state = state.lock().unwrap();
    state.calls.push((base, None));
    StatusCode::from_u16(
        state
            .failure
            .unwrap_or(if state.existing { 412 } else { 201 }),
    )
    .unwrap()
}
async fn index(
    State(state): State<Shared>,
    Path(base): Path<String>,
    headers: HeaderMap,
    Json(value): Json<Value>,
) -> (StatusCode, Json<Value>) {
    assert_eq!(headers["authorization"], "Basic dGVzdDp0ZXN0");
    let mut state = state.lock().unwrap();
    state.calls.push((base, Some(value)));
    (
        StatusCode::OK,
        Json(if state.invalid_index {
            json!({"reason":"secret-password"})
        } else {
            json!({"result":if state.existing {"exists"} else {"created"}})
        }),
    )
}
#[tokio::test]
async fn startup_is_idempotent_and_rejects_errors_safely() {
    let state = Shared::default();
    let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
    let url = format!("http://{}", listener.local_addr().unwrap());
    let app = Router::new()
        .route("/{base}", put(database))
        .route("/{base}/_index", post(index))
        .with_state(state.clone());
    let task = tokio::spawn(async move { axum::serve(listener, app).await.unwrap() });
    let db = CouchDb::from_parts(url, "test".into(), "test".into()).unwrap();
    inicializar_bases(&db).await.unwrap();
    let first_calls = state.lock().unwrap().calls.clone();
    state.lock().unwrap().existing = true;
    inicializar_bases(&db).await.unwrap();
    {
        let state = state.lock().unwrap();
        assert_eq!(state.calls.len(), first_calls.len() * 2);
        assert_eq!(&state.calls[first_calls.len()..], first_calls.as_slice());
        for chunk in state.calls.chunks(first_calls.len()) {
            assert_eq!(
                chunk[..BASES.len()]
                    .iter()
                    .map(|c| c.0.as_str())
                    .collect::<Vec<_>>(),
                BASES
            );
            let indices: Vec<&Value> = chunk[BASES.len()..]
                .iter()
                .map(|call| call.1.as_ref().unwrap())
                .collect();

            assert!(indices.iter().any(|index| {
                index["ddoc"] == "empresas-nit" && index["index"]["fields"] == json!(["nit"])
            }));

            assert!(indices
                .iter()
                .any(|index| { index["name"] == "por-correo" }));

            assert!(indices.iter().any(|index| {
                index["ddoc"] == "empresas-responsable"
                    && index["index"]["fields"] == json!(["usuario_responsable_id", "nit"])
            }));

            for (base, name, fields) in [
                (
                    "operaciones",
                    "creditos-por-responsable",
                    json!(["tipo", "responsable_id", "estado"]),
                ),
                (
                    "operaciones",
                    "creditos-por-estado",
                    json!(["tipo", "estado"]),
                ),
                ("auditoria", "auditoria-por-fecha", json!(["tipo", "fecha"])),
                (
                    "auditoria",
                    "auditoria-por-actor",
                    json!(["tipo", "actor_id"]),
                ),
                (
                    "auditoria",
                    "auditoria-por-recurso",
                    json!(["tipo", "recurso_id"]),
                ),
            ] {
                assert!(
                    chunk.iter().any(|(called_base, definition)| {
                        called_base == base
                            && definition.as_ref().is_some_and(|definition| {
                                definition["name"] == name
                                    && definition["index"]["fields"] == fields
                            })
                    }),
                    "Falta el índice {name} en {base}"
                );
            }
        }
    }
    for status in [401, 403, 500] {
        state.lock().unwrap().failure = Some(status);
        let error = inicializar_bases(&db).await.unwrap_err();
        assert!(matches!(error,InitError::Http{status:code,..} if code==status));
        assert!(!format!("{error:?}").contains("secret-password"));
    }
    state.lock().unwrap().failure = None;
    state.lock().unwrap().invalid_index = true;
    assert!(matches!(
        inicializar_bases(&db).await,
        Err(InitError::InvalidIndex { .. })
    ));
    task.abort();
}

#[tokio::test]
async fn health_survives_missing_configuration_and_new_routes_require_authentication() {
    let app = crate::build_app(None).await;
    let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
    let url = format!("http://{}", listener.local_addr().unwrap());
    let task = tokio::spawn(async move { axum::serve(listener, app).await.unwrap() });
    let client = reqwest::Client::new();
    assert_eq!(
        client
            .get(format!("{url}/api/health"))
            .send()
            .await
            .unwrap()
            .status(),
        StatusCode::OK
    );
    for path in [
        "/api/creditos",
        "/api/creditos/credito:ejemplo",
        "/api/administracion/resumen",
        "/api/administracion/reportes?modulo=creditos",
        "/api/administracion/auditoria",
    ] {
        assert_eq!(
            client
                .get(format!("{url}{path}"))
                .send()
                .await
                .unwrap()
                .status(),
            StatusCode::UNAUTHORIZED,
            "La ruta GET {path} debe estar conectada y protegida"
        );
    }
    for path in [
        "/api/creditos",
        "/api/creditos/aportes/inversion:ejemplo/confirmar",
        "/api/creditos/credito:ejemplo/pagos",
        "/api/creditos/credito:ejemplo/sincronizar",
    ] {
        assert_eq!(
            client
                .post(format!("{url}{path}"))
                .json(&json!({}))
                .send()
                .await
                .unwrap()
                .status(),
            StatusCode::UNAUTHORIZED,
            "La ruta POST {path} debe estar conectada y protegida"
        );
    }
    task.abort();
}

#[tokio::test]
#[ignore = "CouchDB local; inicializa sin borrar y ejecuta ambos scripts con datos ficticios"]
async fn real_startup_and_powershell_scripts() {
    use rand_core::RngCore;
    dotenvy::dotenv().ok();
    let db = CouchDb::new().unwrap();
    inicializar_bases(&db).await.unwrap();
    inicializar_bases(&db).await.unwrap();
    // Secreto efímero solo para este proceso de prueba; nunca se escribe en .env.
    let previous = std::env::var_os("JWT_SECRET");
    let mut bytes = [0u8; 32];
    rand_core::OsRng.fill_bytes(&mut bytes);
    std::env::set_var(
        "JWT_SECRET",
        bytes.iter().map(|b| format!("{b:02x}")).collect::<String>(),
    );
    let app = crate::build_app(Some(&db)).await;
    if let Some(value) = previous {
        std::env::set_var("JWT_SECRET", value)
    } else {
        std::env::remove_var("JWT_SECRET")
    }
    let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
    let url = format!("http://{}", listener.local_addr().unwrap());
    let task = tokio::spawn(async move { axum::serve(listener, app).await.unwrap() });
    let executable =
        std::env::var("COUCHDB_TEST_POWERSHELL").unwrap_or_else(|_| "powershell.exe".into());
    for name in ["empresas.ps1", "usuarios.ps1"] {
        let script = std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
            .join("../../docs/api")
            .join(name);
        let executable = executable.clone();
        let url = url.clone();
        let output = tokio::task::spawn_blocking(move || {
            std::process::Command::new(executable)
                .arg("-NoProfile")
                .arg("-File")
                .arg(script)
                .arg("-BaseUrl")
                .arg(url)
                .output()
        })
        .await
        .unwrap()
        .expect("Ejecutar PowerShell");
        assert!(
            output.status.success(),
            "Script {name} falló; código {:?}",
            output.status.code()
        );
        println!("{name}: ejecución real correcta (salida privada omitida)");
    }
    task.abort();
}
