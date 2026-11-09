//! Opt-in end-to-end tests against a real local CouchDB installation.
//! The application only sees a loopback proxy that maps its six database names
//! to fresh, randomly named databases. Existing databases are never routed.

use axum::{
    body::{to_bytes, Body},
    extract::{Request, State},
    http::{header, StatusCode},
    response::Response,
    Router,
};
use chrono::{Duration as CalendarDuration, Utc};
use rand_core::{OsRng, RngCore};
use reqwest::{Client, Method, Url};
use serde_json::{json, Value};
use std::{collections::HashMap, time::Duration};
use tokio::task::JoinHandle;

use crate::database::{
    connection::CouchDb,
    init::{inicializar_bases, BASES},
};

const PASSWORD: &str = "Solo-Prueba-Aislada-2026!";
const JWT_TEST_SECRET: &str = "jwt-exclusivo-para-prueba-real-aislada-sin-valor-real";

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
    let task = tokio::spawn(async move { axum::serve(listener, app).await.unwrap() });
    Server { url, task }
}

// Never derive Debug: this fixture holds credentials read only from the local .env.
#[derive(Clone)]
struct IsolatedState {
    root: String,
    username: String,
    password: String,
    client: Client,
    names: HashMap<String, String>,
}

async fn isolated_proxy(State(state): State<IsolatedState>, request: Request) -> Response {
    let (parts, body) = request.into_parts();
    let path = parts.uri.path().trim_start_matches('/');
    let (logical, suffix) = path
        .split_once('/')
        .map_or((path, String::new()), |(base, rest)| {
            (base, format!("/{rest}"))
        });
    let Some(database) = state.names.get(logical) else {
        return Response::builder()
            .status(StatusCode::NOT_FOUND)
            .body(Body::empty())
            .unwrap();
    };
    let mut url = match Url::parse(&format!(
        "{}/{database}{suffix}",
        state.root.trim_end_matches('/')
    )) {
        Ok(url) => url,
        Err(_) => {
            return Response::builder()
                .status(StatusCode::BAD_GATEWAY)
                .body(Body::empty())
                .unwrap()
        }
    };
    url.set_query(parts.uri.query());
    let body = match to_bytes(body, 2 * 1024 * 1024).await {
        Ok(body) => body,
        Err(_) => {
            return Response::builder()
                .status(StatusCode::PAYLOAD_TOO_LARGE)
                .body(Body::empty())
                .unwrap()
        }
    };
    let response = state
        .client
        .request(parts.method, url)
        .basic_auth(&state.username, Some(&state.password))
        .header(header::CONTENT_TYPE, "application/json")
        .body(body)
        .send()
        .await;
    let Ok(response) = response else {
        return Response::builder()
            .status(StatusCode::BAD_GATEWAY)
            .body(Body::empty())
            .unwrap();
    };
    let status = response.status();
    let content_type = response.headers().get(header::CONTENT_TYPE).cloned();
    let bytes = response.bytes().await.unwrap_or_default();
    let mut result = Response::builder().status(status);
    if let Some(content_type) = content_type {
        result = result.header(header::CONTENT_TYPE, content_type);
    }
    result.body(Body::from(bytes)).unwrap()
}

struct IsolatedCouch {
    state: IsolatedState,
    created: Vec<String>,
    proxy: Server,
}

impl IsolatedCouch {
    async fn create() -> Result<Self, &'static str> {
        let variables = dotenvy::from_filename_iter(".env")
            .map_err(|_| "No se pudo leer el .env local; no se imprimen credenciales")?
            .collect::<Result<HashMap<_, _>, _>>()
            .map_err(|_| "El .env tiene un formato inválido")?;
        let read = |key: &str| {
            variables
                .get(key)
                .filter(|value| !value.trim().is_empty())
                .cloned()
                .ok_or("Falta una variable COUCHDB en .env")
        };
        let root = read("COUCHDB_URL")?;
        let url = Url::parse(&root).map_err(|_| "COUCHDB_URL inválida")?;
        if !matches!(url.host_str(), Some("127.0.0.1" | "localhost" | "::1"))
            || !matches!(url.scheme(), "http" | "https")
            || !url.username().is_empty()
            || url.password().is_some()
            || url.query().is_some()
            || url.fragment().is_some()
        {
            return Err(
                "Las pruebas reales solo admiten un CouchDB local sin credenciales en la URL",
            );
        }
        let username = read("COUCHDB_USERNAME")?;
        let password = read("COUCHDB_PASSWORD")?;
        let client = Client::builder()
            .connect_timeout(Duration::from_secs(3))
            .timeout(Duration::from_secs(15))
            .redirect(reqwest::redirect::Policy::none())
            .build()
            .map_err(|_| "No se pudo crear el cliente local")?;
        let session = client
            .get(format!("{}/_session", root.trim_end_matches('/')))
            .basic_auth(&username, Some(&password))
            .send()
            .await
            .map_err(|_| "CouchDB local no responde")?;
        if session.status() != StatusCode::OK {
            return Err("CouchDB rechazó las credenciales locales");
        }
        let session: Value = session
            .json()
            .await
            .map_err(|_| "Sesión CouchDB incompatible")?;
        if !session["userCtx"]["roles"]
            .as_array()
            .is_some_and(|roles| roles.iter().any(|role| role == "_admin"))
        {
            return Err(
                "Se requiere permiso para crear y eliminar las bases aisladas de esta prueba",
            );
        }
        let mut random = [0_u8; 16];
        OsRng.fill_bytes(&mut random);
        let nonce: String = random.iter().map(|byte| format!("{byte:02x}")).collect();
        let names: HashMap<_, _> = BASES
            .iter()
            .map(|base| ((*base).into(), format!("credito_codex_it_{nonce}_{base}")))
            .collect();
        let state = IsolatedState {
            root,
            username,
            password,
            client,
            names,
        };
        // Bind the proxy before creating anything, so a bind failure leaves no databases.
        let proxy = serve(
            Router::new()
                .fallback(isolated_proxy)
                .with_state(state.clone()),
        )
        .await;
        let mut created = Vec::new();
        for base in BASES {
            let name = &state.names[*base];
            let response = state
                .client
                .put(format!("{}/{name}", state.root.trim_end_matches('/')))
                .basic_auth(&state.username, Some(&state.password))
                .send()
                .await;
            // A 412 means a pre-existing database. Never claim or delete it.
            if !response
                .as_ref()
                .is_ok_and(|response| response.status() == StatusCode::CREATED)
            {
                if !cleanup(&state, &created).await {
                    return Err(
                        "Falló la creación y quedó incompleta la limpieza de bases aisladas",
                    );
                }
                return Err("No se pudo crear una base nueva; no se usarán bases existentes");
            }
            created.push(name.clone());
        }
        Ok(Self {
            state,
            created,
            proxy,
        })
    }

    fn connection(&self) -> CouchDb {
        CouchDb::from_parts(
            self.proxy.url.clone(),
            self.state.username.clone(),
            self.state.password.clone(),
        )
        .unwrap()
    }

    async fn bootstrap_test_admin(state: &IsolatedState, id: &str) {
        // This document was created moments ago by this test in its own database.
        let database = &state.names["usuarios"];
        let mut url = Url::parse(&state.root).unwrap();
        url.path_segments_mut()
            .unwrap()
            .pop_if_empty()
            .push(database)
            .push(id);
        let response = state
            .client
            .get(url.clone())
            .basic_auth(&state.username, Some(&state.password))
            .send()
            .await
            .unwrap_or_else(|_| panic!("No se pudo leer la cuenta ficticia aislada"));
        assert_eq!(
            response.status(),
            StatusCode::OK,
            "No se pudo leer la cuenta ficticia aislada"
        );
        let mut document: Value = response
            .json()
            .await
            .unwrap_or_else(|_| panic!("La cuenta ficticia no contiene JSON válido"));
        assert_eq!(document["_id"], id);
        assert_eq!(document["rol"], "pyme");
        document["rol"] = json!("administrador");
        let status = state
            .client
            .put(url)
            .basic_auth(&state.username, Some(&state.password))
            .json(&document)
            .send()
            .await
            .unwrap_or_else(|_| panic!("No se pudo guardar la cuenta ficticia aislada"))
            .status();
        assert_eq!(
            status,
            StatusCode::CREATED,
            "No se pudo preparar el administrador ficticio"
        );
    }
}

async fn cleanup(state: &IsolatedState, created: &[String]) -> bool {
    let mut complete = true;
    for name in created {
        // Defense in depth: delete only exact names recorded after a successful 201.
        if !name.starts_with("credito_codex_it_")
            || !state.names.values().any(|owned| owned == name)
        {
            complete = false;
            continue;
        }
        let result = state
            .client
            .request(
                Method::DELETE,
                format!("{}/{name}", state.root.trim_end_matches('/')),
            )
            .basic_auth(&state.username, Some(&state.password))
            .send()
            .await;
        complete &= result.is_ok_and(|response| {
            matches!(response.status(), StatusCode::OK | StatusCode::ACCEPTED)
        });
    }
    complete
}

async fn body(request: reqwest::RequestBuilder, expected: StatusCode) -> Value {
    let response = request
        .send()
        .await
        .unwrap_or_else(|_| panic!("La API de prueba local no respondió"));
    let status = response.status();
    let result: Value = response
        .json()
        .await
        .unwrap_or_else(|_| panic!("La API de prueba no devolvió JSON"));
    let public = result.to_string();
    assert!(
        !public.contains("\"password_hash\"") && !public.contains("\"solicitud_creacion_huella\""),
        "Una respuesta pública incluyó metadatos privados"
    );
    assert_eq!(
        status,
        expected,
        "Error API: {}",
        result["error"]
            .as_str()
            .unwrap_or("respuesta sin mensaje público")
    );
    result
}

async fn register(client: &Client, api: &str, email: &str, role: &str) -> Value {
    let result = body(client.post(format!("{api}/api/auth/register")).json(&json!({
        "nombre":"Cuenta ficticia de integración", "correo":email, "password":PASSWORD, "rol":role,
    })), StatusCode::CREATED).await;
    assert!(result.get("password_hash").is_none());
    assert!(result.get("_rev").is_none());
    result
}

async fn login(client: &Client, api: &str, email: &str) -> String {
    let result = body(
        client.post(format!("{api}/api/auth/login")).json(&json!({
            "correo":email, "password":PASSWORD,
        })),
        StatusCode::OK,
    )
    .await;
    result["access_token"]
        .as_str()
        .expect("Falta token de la cuenta ficticia")
        .to_string()
}

#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
#[ignore = "Requiere CouchDB real local y .env; crea y limpia seis bases aisladas nuevas, nunca las existentes"]
async fn real_couchdb_isolated_six_module_lifecycle() {
    let isolated = IsolatedCouch::create()
        .await
        .expect("No se pudo preparar CouchDB aislado");
    let connection = isolated.connection();
    // Only this opt-in process uses this synthetic key. No local .env is changed.
    std::env::set_var("JWT_SECRET", JWT_TEST_SECRET);
    std::env::set_var("JWT_TTL_SECONDS", "3600");
    let fixture = isolated.state.clone();
    let test = tokio::spawn(async move {
        inicializar_bases(&connection).await.expect("Falló la inicialización real de índices");
        let api = serve(crate::build_app(Some(&connection)).await).await;
        let client = Client::builder().timeout(Duration::from_secs(20)).build().unwrap();
        let pyme = register(&client, &api.url, "pyme@isolated.example", "pyme").await;
        register(&client, &api.url, "inversor@isolated.example", "inversionista").await;
        let admin = register(&client, &api.url, "admin@isolated.example", "pyme").await;
        // Bootstrap is confined to this fixture's newly created database.
        IsolatedCouch::bootstrap_test_admin(&fixture, admin["id"].as_str().unwrap()).await;
        let pyme_token = login(&client, &api.url, "pyme@isolated.example").await;
        let investor_token = login(&client, &api.url, "inversor@isolated.example").await;
        let admin_token = login(&client, &api.url, "admin@isolated.example").await;
        body(client.get(format!("{}/api/administracion/resumen", api.url)).bearer_auth(&investor_token), StatusCode::FORBIDDEN).await;
        body(client.get(format!("{}/api/usuarios", api.url)).bearer_auth(&pyme_token), StatusCode::FORBIDDEN).await;
        let users = body(client.get(format!("{}/api/usuarios?limit=1", api.url)).bearer_auth(&admin_token), StatusCode::OK).await;
        assert_eq!(users["usuarios"].as_array().unwrap().len(), 1);
        assert!(users["usuarios"][0].get("password_hash").is_none());
        let company_data = json!({"nombre":"Empresa ficticia aislada", "nit":"000000001", "correo":"empresa@isolated.example", "telefono":"22223344", "direccion":"Dirección exclusivamente ficticia"});
        let company = body(client.post(format!("{}/api/empresas", api.url)).bearer_auth(&pyme_token)
            .header("Idempotency-Key", "real-empresa-1").json(&company_data), StatusCode::CREATED).await;
        let company_id = company["id"].as_str().unwrap();
        let same_company = body(client.post(format!("{}/api/empresas", api.url)).bearer_auth(&pyme_token)
            .header("Idempotency-Key", "real-empresa-1").json(&company_data), StatusCode::CREATED).await;
        assert_eq!(same_company["id"], company["id"]);
        let mut different_company = company_data.clone();
        different_company["nombre"] = json!("Contenido diferente");
        body(client.post(format!("{}/api/empresas", api.url)).bearer_auth(&pyme_token)
            .header("Idempotency-Key", "real-empresa-1").json(&different_company), StatusCode::CONFLICT).await;
        let detail = client.get(format!("{}/api/empresas/{company_id}", api.url)).bearer_auth(&admin_token).send().await.unwrap_or_else(|_| panic!("No se pudo consultar la empresa ficticia"));
        assert_eq!(detail.status(), StatusCode::OK);
        let revision = detail.headers()["etag"].to_str().unwrap().to_string();
        body(client.patch(format!("{}/api/empresas/{company_id}/aprobar", api.url)).bearer_auth(&pyme_token)
            .header("If-Match", &revision), StatusCode::FORBIDDEN).await;
        let approved = body(client.patch(format!("{}/api/empresas/{company_id}/aprobar", api.url)).bearer_auth(&admin_token)
            .header("If-Match", &revision), StatusCode::OK).await;
        assert_eq!(approved["estado"], "activa");
        body(client.put(format!("{}/api/empresas/{company_id}", api.url)).bearer_auth(&pyme_token)
            .header("If-Match", &revision).json(&company_data), StatusCode::PRECONDITION_FAILED).await;
        let replay = body(client.post(format!("{}/api/empresas", api.url)).bearer_auth(&pyme_token)
            .header("Idempotency-Key", "real-empresa-1").json(&company_data), StatusCode::CREATED).await;
        assert_eq!(replay["estado"], "activa");
        let today = Utc::now().date_naive();
        let invoice_data = json!({"empresa_id":company_id,"numero":"AISLADA-001", "codigo_generacion":"00000000-0000-4000-8000-000000000001", "moneda":"USD", "monto_total_centavos":10000,
            "fecha_emision":today.to_string(), "fecha_vencimiento":(today + CalendarDuration::days(30)).to_string()});
        let invoice = body(client.post(format!("{}/api/facturas", api.url)).bearer_auth(&pyme_token)
            .header("Idempotency-Key", "real-factura-1").json(&invoice_data), StatusCode::CREATED).await;
        let invoice_id = invoice["id"].as_str().unwrap();
        let same_invoice = body(client.post(format!("{}/api/facturas", api.url)).bearer_auth(&pyme_token)
            .header("Idempotency-Key", "real-factura-1").json(&invoice_data), StatusCode::CREATED).await;
        assert_eq!(same_invoice["id"], invoice["id"]);
        let mut different_invoice = invoice_data.clone();
        different_invoice["numero"] = json!("AISLADA-DIFERENTE");
        body(client.post(format!("{}/api/facturas", api.url)).bearer_auth(&pyme_token)
            .header("Idempotency-Key", "real-factura-1").json(&different_invoice), StatusCode::CONFLICT).await;
        body(client.patch(format!("{}/api/facturas/{invoice_id}/verificar-dte", api.url)).bearer_auth(&pyme_token)
            .json(&json!({"sello_recepcion":"SELLO-FICTICIO"})), StatusCode::FORBIDDEN).await;
        let verified = body(client.patch(format!("{}/api/facturas/{invoice_id}/verificar-dte", api.url)).bearer_auth(&admin_token)
            .json(&json!({"sello_recepcion":"SELLO-FICTICIO"})), StatusCode::OK).await;
        assert_eq!(verified["estado"], "disponible");
        let replay = body(client.post(format!("{}/api/facturas", api.url)).bearer_auth(&pyme_token)
            .header("Idempotency-Key", "real-factura-1").json(&invoice_data), StatusCode::CREATED).await;
        assert_eq!(replay["estado"], "disponible");
        let offer = body(client.post(format!("{}/api/ofertas", api.url)).bearer_auth(&pyme_token)
            .json(&json!({"factura_id":invoice_id, "monto_objetivo":100.0, "tasa_rendimiento_anual":8.0,
                "fecha_cierre":(Utc::now() + CalendarDuration::days(2)).to_rfc3339()})), StatusCode::CREATED).await;
        let offer_id = offer["_id"].as_str().unwrap();
        let investment_data = json!({"oferta_id":offer_id, "monto":100.0});
        let investment = body(client.post(format!("{}/api/inversiones", api.url)).bearer_auth(&investor_token)
            .header("Idempotency-Key", "real-aporte-1").json(&investment_data), StatusCode::CREATED).await;
        let replay = body(client.post(format!("{}/api/inversiones", api.url)).bearer_auth(&investor_token)
            .header("Idempotency-Key", "real-aporte-1").json(&investment_data), StatusCode::CREATED).await;
        assert_eq!(replay["_id"], investment["_id"]);
        body(client.post(format!("{}/api/inversiones", api.url)).bearer_auth(&investor_token)
            .header("Idempotency-Key", "real-aporte-1").json(&json!({"oferta_id":offer_id, "monto":99.0})), StatusCode::CONFLICT).await;
        let investment_id = investment["_id"].as_str().unwrap();
        let confirmation = body(client.post(format!("{}/api/creditos/aportes/{investment_id}/confirmar", api.url))
            .bearer_auth(&investor_token), StatusCode::OK).await;
        assert_eq!(confirmation["estado"], "confirmada");
        body(client.post(format!("{}/api/creditos", api.url)).bearer_auth(&pyme_token)
            .json(&json!({"oferta_id":offer_id})), StatusCode::FORBIDDEN).await;
        let issued = body(client.post(format!("{}/api/creditos", api.url)).bearer_auth(&admin_token)
            .json(&json!({"oferta_id":offer_id})), StatusCode::CREATED).await;
        assert_eq!(issued["sincronizacion_pendiente"], false);
        let credit = &issued["credito"];
        let credit_id = credit["id"].as_str().unwrap();
        assert_eq!(credit["capital_centavos"], 10000);
        let total = credit["total_centavos"].as_i64().unwrap();
        let restricted = body(client.get(format!("{}/api/creditos/{credit_id}", api.url)).bearer_auth(&investor_token), StatusCode::OK).await;
        assert!(restricted.get("pagos").is_none());
        assert_eq!(restricted["total_centavos"], total);
        let payment = json!({"referencia":"pago-real-aislado-1", "monto_centavos":total});
        let paid = body(client.post(format!("{}/api/creditos/{credit_id}/pagos", api.url)).bearer_auth(&pyme_token)
            .json(&payment), StatusCode::OK).await;
        assert_eq!(paid["credito"]["estado"], "pagado");
        assert_eq!(paid["credito"]["saldo_centavos"], 0);
        assert_eq!(paid["sincronizacion_pendiente"], false);
        let replay = body(client.post(format!("{}/api/creditos/{credit_id}/pagos", api.url)).bearer_auth(&pyme_token)
            .json(&payment), StatusCode::OK).await;
        assert_eq!(replay["credito"]["pagos"].as_array().unwrap().len(), 1);
        let invoice_paid = body(client.get(format!("{}/api/facturas/{invoice_id}", api.url)).bearer_auth(&pyme_token), StatusCode::OK).await;
        assert_eq!(invoice_paid["estado"], "pagada");
        let investments = body(client.get(format!("{}/api/inversiones", api.url)).bearer_auth(&investor_token), StatusCode::OK).await;
        assert_eq!(investments["inversiones"].as_array().unwrap().len(), 1);
        assert_eq!(investments["inversiones"][0]["estado"], "liquidada");
        let summary = body(client.get(format!("{}/api/administracion/resumen", api.url)).bearer_auth(&admin_token), StatusCode::OK).await;
        let reports = summary["reportes"].as_array().unwrap();
        assert_eq!(reports.len(), 8);
        for module in ["empresas", "facturas", "creditos", "inversiones", "pagos"] {
            let report = reports.iter().find(|report| report["modulo"] == module).unwrap();
            assert_eq!(report["total"], 1, "Hay duplicados en el módulo {module}");
        }
        let events = body(client.get(format!("{}/api/administracion/auditoria", api.url)).bearer_auth(&admin_token)
            .query(&[("actor_id", pyme["id"].as_str().unwrap()), ("recurso_id", credit_id)]), StatusCode::OK).await;
        assert!(events["eventos"].as_array().unwrap().iter().any(|event| event["accion"] == "pago_registrado"));
    }).await;
    let cleaned = cleanup(&isolated.state, &isolated.created).await;
    assert!(
        cleaned,
        "La limpieza de las bases creadas por esta prueba no se completó"
    );
    assert!(
        test.is_ok(),
        "Falló el recorrido real; las bases de esta ejecución ya se limpiaron"
    );
    eprintln!(
        "CouchDB real: recorrido de seis módulos verificado y seis bases aisladas eliminadas."
    );
}
