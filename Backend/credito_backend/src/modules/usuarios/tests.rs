use super::{
    auth::{AuthenticatedUser, Claims, Tokens, AUDIENCE, ISSUER},
    model::Rol,
    repository::UsuarioRepository,
    routes,
    service::UsuarioService,
};
use axum::{
    extract::{Path, State},
    http::{HeaderMap, StatusCode},
    routing::{get, post},
    Json, Router,
};
use serde_json::{json, Value};
use std::{
    collections::BTreeMap,
    sync::{Arc, Mutex},
};
use tokio::task::JoinHandle;

const PASSWORD: &str = "Ficticia-Prueba-123!";
const TEST_SECRET: &str = "solo-pruebas-locales-sin-valor-real-0123456789";
#[derive(Default)]
struct Db {
    documents: BTreeMap<String, Value>,
    failure: Option<u16>,
    malformed: bool,
    conflict_on_update: bool,
}
type Shared = Arc<Mutex<Db>>;
type Reply = (StatusCode, Json<Value>);
fn failure(db: &Db, headers: &HeaderMap) -> Option<Reply> {
    assert_eq!(headers.get("authorization").unwrap(), "Basic dGVzdDp0ZXN0");
    if db.malformed {
        return Some((StatusCode::OK, Json(json!({"invalid": true}))));
    }
    db.failure.map(|code| {
        (
            StatusCode::from_u16(code).unwrap(),
            Json(json!({"error": "internal", "reason": "secret-password"})),
        )
    })
}
async fn find(State(shared): State<Shared>, headers: HeaderMap, Json(query): Json<Value>) -> Reply {
    let db = shared.lock().unwrap();
    if let Some(reply) = failure(&db, &headers) {
        return reply;
    }
    assert_eq!(query["limit"], 2);
    assert_eq!(query["use_index"], json!(["usuarios-correo", "por-correo"]));
    let docs: Vec<_> = db
        .documents
        .values()
        .filter(|d| d["correo"] == query["selector"]["correo"]["$eq"])
        .take(2)
        .cloned()
        .collect();
    (
        StatusCode::OK,
        Json(json!({"docs": docs, "bookmark": "unused"})),
    )
}
async fn read(State(shared): State<Shared>, Path(id): Path<String>, headers: HeaderMap) -> Reply {
    let db = shared.lock().unwrap();
    if let Some(reply) = failure(&db, &headers) {
        return reply;
    }
    match db.documents.get(&id) {
        Some(doc) => (StatusCode::OK, Json(doc.clone())),
        None => (
            StatusCode::NOT_FOUND,
            Json(json!({"error": "not_found", "reason": "missing"})),
        ),
    }
}
async fn write(
    State(shared): State<Shared>,
    Path(id): Path<String>,
    headers: HeaderMap,
    Json(mut doc): Json<Value>,
) -> Reply {
    let mut db = shared.lock().unwrap();
    if let Some(reply) = failure(&db, &headers) {
        return reply;
    }
    assert_eq!(doc["_id"], id);
    let mut revision = 1;
    if let Some(old) = db.documents.get(&id) {
        if db.conflict_on_update || doc["_rev"] != old["_rev"] {
            return (StatusCode::CONFLICT, Json(json!({"error": "conflict"})));
        }
        revision = 2;
    } else {
        assert!(doc.get("_rev").is_none());
    }
    let rev = format!("{revision}-test");
    doc["_rev"] = json!(rev);
    db.documents.insert(id.clone(), doc);
    (
        StatusCode::CREATED,
        Json(json!({"ok": true, "id": id, "rev": rev})),
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
async fn serve(router: Router) -> Server {
    let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
    let url = format!("http://{}", listener.local_addr().unwrap());
    let task = tokio::spawn(async move {
        axum::serve(listener, router).await.unwrap();
    });
    Server { url, task }
}
async fn admin(user: AuthenticatedUser) -> Result<StatusCode, super::UsuarioError> {
    user.require_roles(&[Rol::Administrador])?;
    Ok(StatusCode::NO_CONTENT)
}
async fn setup() -> (Server, Server, Shared) {
    let db = Shared::default();
    let couch = serve(
        Router::new()
            .route("/usuarios/_find", post(find))
            .route("/usuarios/{id}", get(read).put(write))
            .with_state(db.clone()),
    )
    .await;
    let repo = UsuarioRepository::new(&couch.url, "test".into(), "test".into()).unwrap();
    let service = UsuarioService::new(repo, TEST_SECRET.into(), 3600)
        .await
        .unwrap();
    let admin_route = Router::new()
        .route("/test/admin", get(admin))
        .with_state(service.clone());
    let api = serve(routes::router(service).merge(admin_route)).await;
    (api, couch, db)
}
fn registration(email: &str) -> Value {
    json!({"nombre": "Usuario ficticio", "correo": email, "password": PASSWORD, "rol": "pyme"})
}
async fn register(client: &reqwest::Client, api: &Server, email: &str) -> Value {
    let response = client
        .post(format!("{}/api/auth/register", api.url))
        .json(&registration(email))
        .send()
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::CREATED);
    let value: Value = response.json().await.unwrap();
    assert!(value.get("password_hash").is_none());
    assert!(value.get("password").is_none());
    value
}
async fn login(client: &reqwest::Client, api: &Server, email: &str) -> Value {
    let response = client
        .post(format!("{}/api/auth/login", api.url))
        .json(&json!({"correo": email, "password": PASSWORD}))
        .send()
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::OK);
    assert_eq!(response.headers()["cache-control"], "no-store");
    response.json().await.unwrap()
}

#[tokio::test]
async fn register_login_profile_and_live_authorization() {
    let (api, _couch, db) = setup().await;
    let client = reqwest::Client::new();
    let created = register(&client, &api, " Demo@EXAMPLE.TEST ").await;
    assert_eq!(created["correo"], "demo@example.test");
    assert_eq!(created["rol"], "pyme");
    assert_eq!(created["estado"], "activo");
    let signed = login(&client, &api, "DEMO@example.test").await;
    let token = signed["access_token"].as_str().unwrap();
    let me = format!("{}/api/usuarios/me", api.url);
    let response = client.get(&me).bearer_auth(token).send().await.unwrap();
    assert_eq!(response.status(), StatusCode::OK);
    let profile: Value = response.json().await.unwrap();
    assert_eq!(profile, created);
    let updated = client
        .put(&me)
        .bearer_auth(token)
        .json(&json!({"nombre":"Nombre ficticio actualizado"}))
        .send()
        .await
        .unwrap();
    assert_eq!(updated.status(), StatusCode::OK);
    let updated: Value = updated.json().await.unwrap();
    assert_eq!(updated["fecha_creacion"], created["fecha_creacion"]);
    assert_eq!(updated["rol"], "pyme");
    assert!(updated.get("password_hash").is_none());
    assert_eq!(
        client
            .get(format!("{}/test/admin", api.url))
            .bearer_auth(token)
            .send()
            .await
            .unwrap()
            .status(),
        StatusCode::FORBIDDEN
    );
    let id = created["id"].as_str().unwrap();
    {
        let mut db = db.lock().unwrap();
        let doc = db.documents.get_mut(id).unwrap();
        assert!(doc["password_hash"]
            .as_str()
            .unwrap()
            .starts_with("$argon2id$"));
        assert!(doc.get("password").is_none());
        doc["rol"] = json!("administrador");
    }
    // El rol procede de CouchDB, no de un claim aportado por el cliente.
    assert_eq!(
        client
            .get(format!("{}/test/admin", api.url))
            .bearer_auth(token)
            .send()
            .await
            .unwrap()
            .status(),
        StatusCode::NO_CONTENT
    );
    db.lock().unwrap().documents.get_mut(id).unwrap()["estado"] = json!("inactivo");
    assert_eq!(
        client
            .get(&me)
            .bearer_auth(token)
            .send()
            .await
            .unwrap()
            .status(),
        StatusCode::UNAUTHORIZED
    );
    assert_eq!(
        client
            .post(format!("{}/api/auth/login", api.url))
            .json(&json!({"correo":"demo@example.test","password":PASSWORD}))
            .send()
            .await
            .unwrap()
            .status(),
        StatusCode::UNAUTHORIZED
    );
}

#[tokio::test]
async fn concurrent_and_normalized_duplicates_do_not_overwrite_account() {
    let (api, _couch, db) = setup().await;
    let client = reqwest::Client::new();
    let url = format!("{}/api/auth/register", api.url);
    let a = client
        .post(&url)
        .json(&registration("RACE@example.test"))
        .send();
    let b = client
        .post(&url)
        .json(&registration(" race@EXAMPLE.TEST "))
        .send();
    let (a, b) = tokio::join!(a, b);
    let mut codes = [a.unwrap().status().as_u16(), b.unwrap().status().as_u16()];
    codes.sort();
    assert_eq!(codes, [201, 409]);
    assert_eq!(db.lock().unwrap().documents.len(), 1);
    assert_eq!(
        client
            .post(&url)
            .json(&registration("race@example.test"))
            .send()
            .await
            .unwrap()
            .status(),
        StatusCode::CONFLICT
    );
}

#[tokio::test]
async fn rejects_privilege_changes_and_invalid_registration() {
    let (api, _couch, db) = setup().await;
    let client = reqwest::Client::new();
    for (field, value) in [
        ("rol", "administrador"),
        ("rol", "inventado"),
        ("nombre", " "),
        ("correo", "incorrecto"),
        ("password", "123"),
        ("estado", "activo"),
        ("password_hash", "fake"),
    ] {
        let mut body = registration("demo@example.test");
        body[field] = json!(value);
        assert_eq!(
            client
                .post(format!("{}/api/auth/register", api.url))
                .json(&body)
                .send()
                .await
                .unwrap()
                .status(),
            StatusCode::BAD_REQUEST
        );
    }
    assert!(db.lock().unwrap().documents.is_empty());
    register(&client, &api, "demo@example.test").await;
    let signed = login(&client, &api, "demo@example.test").await;
    for field in [
        "rol",
        "estado",
        "id",
        "_rev",
        "password_hash",
        "password",
        "correo",
    ] {
        let mut body = json!({"nombre":"Nombre ficticio"});
        body[field] = json!("alterado");
        assert_eq!(
            client
                .put(format!("{}/api/usuarios/me", api.url))
                .bearer_auth(signed["access_token"].as_str().unwrap())
                .json(&body)
                .send()
                .await
                .unwrap()
                .status(),
            StatusCode::BAD_REQUEST
        );
    }
}

#[tokio::test]
async fn generic_credentials_errors_and_login_throttling() {
    let (api, _couch, _db) = setup().await;
    let client = reqwest::Client::new();
    register(&client, &api, "demo@example.test").await;
    let url = format!("{}/api/auth/login", api.url);
    let mut bodies = Vec::new();
    for email in ["demo@example.test", "missing@example.test"] {
        let response = client
            .post(&url)
            .json(&json!({"correo":email,"password":"incorrecta-ficticia"}))
            .send()
            .await
            .unwrap();
        assert_eq!(response.status(), StatusCode::UNAUTHORIZED);
        bodies.push(response.text().await.unwrap());
    }
    assert_eq!(bodies[0], bodies[1]);
    for _ in 0..4 {
        assert_eq!(
            client
                .post(&url)
                .json(&json!({"correo":"missing@example.test","password":"incorrecta"}))
                .send()
                .await
                .unwrap()
                .status(),
            StatusCode::UNAUTHORIZED
        );
    }
    let blocked = client
        .post(&url)
        .json(&json!({"correo":"MISSING@EXAMPLE.TEST","password":PASSWORD}))
        .send()
        .await
        .unwrap();
    assert_eq!(blocked.status(), StatusCode::TOO_MANY_REQUESTS);
    assert_eq!(blocked.headers()["retry-after"], "60");
}

#[test]
fn checks_signature_expiration_algorithm_and_claims() {
    let tokens = Tokens::new(TEST_SECRET.into(), 3600).unwrap();
    let valid = tokens.issue("usuario:test").unwrap();
    assert_eq!(tokens.verify(&valid).unwrap(), "usuario:test");
    let now = chrono::Utc::now().timestamp() as u64;
    for case in [
        "expired",
        "aud",
        "iss",
        "future",
        "sub",
        "lifetime",
        "algorithm",
    ] {
        let mut claims = Claims {
            sub: "usuario:test".into(),
            exp: now + 3600,
            iat: now,
            nbf: now,
            iss: ISSUER.into(),
            aud: AUDIENCE.into(),
        };
        let mut algorithm = jsonwebtoken::Algorithm::HS256;
        match case {
            "expired" => {
                claims.exp = now - 1;
                claims.iat = now - 60;
                claims.nbf = now - 60;
            }
            "aud" => claims.aud = "other".into(),
            "iss" => claims.iss = "other".into(),
            "future" => {
                claims.iat = now + 60;
                claims.nbf = now + 60;
            }
            "sub" => claims.sub = "_all_docs".into(),
            "lifetime" => claims.exp = now + 86400,
            "algorithm" => algorithm = jsonwebtoken::Algorithm::HS384,
            _ => unreachable!(),
        }
        assert!(
            tokens
                .verify(&tokens.sign(&claims, algorithm).unwrap())
                .is_err(),
            "{case}"
        );
    }
    let mut manipulated = valid.into_bytes();
    manipulated[10] = if manipulated[10] == b'A' { b'B' } else { b'A' };
    assert!(tokens
        .verify(std::str::from_utf8(&manipulated).unwrap())
        .is_err());
    assert!(Tokens::new("short".into(), 3600).is_err());
    assert!(Tokens::new(TEST_SECRET.into(), 0).is_err());
}

#[tokio::test]
async fn profile_requires_own_authentication_and_handles_revision_conflicts() {
    let (api, _couch, db) = setup().await;
    let client = reqwest::Client::new();
    let url = format!("{}/api/usuarios/me", api.url);
    assert_eq!(
        client.get(&url).send().await.unwrap().status(),
        StatusCode::UNAUTHORIZED
    );
    assert_eq!(
        client
            .put(&url)
            .json(&json!({"nombre":"Ficticio"}))
            .send()
            .await
            .unwrap()
            .status(),
        StatusCode::UNAUTHORIZED
    );
    register(&client, &api, "first@example.test").await;
    let other = register(&client, &api, "other@example.test").await;
    let signed = login(&client, &api, "first@example.test").await;
    assert_eq!(
        client
            .get(format!(
                "{}/api/usuarios/{}",
                api.url,
                other["id"].as_str().unwrap()
            ))
            .bearer_auth(signed["access_token"].as_str().unwrap())
            .send()
            .await
            .unwrap()
            .status(),
        StatusCode::NOT_FOUND
    );
    db.lock().unwrap().conflict_on_update = true;
    assert_eq!(
        client
            .put(&url)
            .bearer_auth(signed["access_token"].as_str().unwrap())
            .json(&json!({"nombre":"Ficticio"}))
            .send()
            .await
            .unwrap()
            .status(),
        StatusCode::CONFLICT
    );
}

#[tokio::test]
async fn couchdb_errors_are_sanitized_and_missing_config_keeps_health() {
    let (api, _couch, db) = setup().await;
    let client = reqwest::Client::new();
    for (index, (code, expected)) in [
        (401, 503),
        (403, 503),
        (404, 503),
        (409, 409),
        (500, 502),
        (503, 503),
    ]
    .into_iter()
    .enumerate()
    {
        db.lock().unwrap().failure = Some(code);
        let response = client
            .post(format!("{}/api/auth/register", api.url))
            .json(&registration(&format!("test{index}@example.test")))
            .send()
            .await
            .unwrap();
        assert_eq!(response.status().as_u16(), expected);
        assert!(!response.text().await.unwrap().contains("secret-password"));
    }
    db.lock().unwrap().failure = None;
    db.lock().unwrap().malformed = true;
    assert_eq!(
        client
            .post(format!("{}/api/auth/login", api.url))
            .json(&json!({"correo":"demo@example.test","password":PASSWORD}))
            .send()
            .await
            .unwrap()
            .status(),
        StatusCode::BAD_GATEWAY
    );
    let disabled = serve(
        Router::new()
            .route("/api/health", get(crate::health))
            .merge(routes::router(UsuarioService::disabled())),
    )
    .await;
    assert_eq!(
        client
            .get(format!("{}/api/health", disabled.url))
            .send()
            .await
            .unwrap()
            .status(),
        StatusCode::OK
    );
    assert_eq!(
        client
            .post(format!("{}/api/auth/login", disabled.url))
            .json(&json!({"correo":"demo@example.test","password":PASSWORD}))
            .send()
            .await
            .unwrap()
            .status(),
        StatusCode::SERVICE_UNAVAILABLE
    );
}

#[tokio::test]
#[ignore = "Requiere CouchDB local y base usuarios; crea una cuenta ficticia persistente"]
async fn real_couchdb_register_login_profile() {
    use rand_core::RngCore;
    dotenvy::dotenv().ok();
    let repository = UsuarioRepository::from_env().expect("Configurar CouchDB");
    let mut random = [0u8; 32];
    rand_core::OsRng.fill_bytes(&mut random);
    let secret: String = random.iter().map(|b| format!("{b:02x}")).collect();
    let mut nonce = [0u8; 8];
    rand_core::OsRng.fill_bytes(&mut nonce);
    let nonce: String = nonce.iter().map(|b| format!("{b:02x}")).collect();
    let email = format!("test-{nonce}@example.test");
    let service = UsuarioService::new(repository, secret, 3600).await.unwrap();
    let api = serve(routes::router(service)).await;
    let client = reqwest::Client::new();
    register(&client, &api, &email).await;
    let signed = login(&client, &api, &email).await;
    let response = client
        .get(format!("{}/api/usuarios/me", api.url))
        .bearer_auth(signed["access_token"].as_str().unwrap())
        .send()
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::OK);
    let profile: Value = response.json().await.unwrap();
    assert_eq!(profile["correo"], email);
    assert!(profile.get("password_hash").is_none());
    println!("CouchDB real: registro, login y perfil correctos; cuenta ficticia conservada");
}
