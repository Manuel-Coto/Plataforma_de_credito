use argon2::{
    password_hash::{PasswordHash, PasswordHasher, PasswordVerifier, SaltString},
    Algorithm, Argon2, Params, Version,
};
use chrono::Utc;
use rand_core::OsRng;
use std::{
    collections::HashMap,
    env,
    sync::{Arc, Mutex},
    time::{Duration, Instant},
};
use tokio::sync::Semaphore;

use super::{
    auth::Tokens,
    model::{
        EstadoUsuario, LoginInput, LoginResponse, ProfileInput, RegisterInput, Rol, Usuario,
        UsuarioDocumento,
    },
    repository::{email_id, UsuarioRepository},
    UsuarioError,
};

#[derive(Clone)]
pub struct UsuarioService {
    inner: Option<Arc<Inner>>,
}
struct Inner {
    repository: UsuarioRepository,
    tokens: Tokens,
    dummy_hash: String,
    attempts: Mutex<Attempts>,
    hashing: Arc<Semaphore>,
}
struct Window {
    start: Instant,
    count: u32,
}
struct Attempts {
    global: Window,
    emails: HashMap<String, Window>,
}
impl Default for Attempts {
    fn default() -> Self {
        Self {
            global: Window {
                start: Instant::now(),
                count: 0,
            },
            emails: HashMap::new(),
        }
    }
}
impl Attempts {
    fn check(&mut self, key: String) -> Result<(), UsuarioError> {
        let now = Instant::now();
        let duration = Duration::from_secs(60);
        if now.duration_since(self.global.start) >= duration {
            self.global = Window {
                start: now,
                count: 0,
            };
        }
        self.emails
            .retain(|_, window| now.duration_since(window.start) < duration);
        if self.global.count >= 100
            || (self.emails.len() >= 10000 && !self.emails.contains_key(&key))
        {
            return Err(UsuarioError::RateLimited);
        }
        self.global.count += 1;
        let window = self.emails.entry(key).or_insert(Window {
            start: now,
            count: 0,
        });
        if window.count >= 5 {
            return Err(UsuarioError::RateLimited);
        }
        window.count += 1;
        Ok(())
    }
}

impl UsuarioService {
    #[cfg(test)]
    pub(crate) async fn for_test(url: &str, secret: &str) -> Self {
        let repository = UsuarioRepository::new(url, "test".into(), "test".into()).unwrap();
        Self::new(repository, secret.into(), 3600).await.unwrap()
    }
    pub fn disabled() -> Self {
        Self { inner: None }
    }
    #[allow(dead_code)]
    pub async fn from_env() -> Result<Self, UsuarioError> {
        let repository = UsuarioRepository::from_env()?;
        Self::configured(repository).await
    }
    pub async fn from_connection(
        db: &crate::database::connection::CouchDb,
    ) -> Result<Self, UsuarioError> {
        Self::configured(UsuarioRepository::from_connection(db)?).await
    }
    async fn configured(repository: UsuarioRepository) -> Result<Self, UsuarioError> {
        let secret = env::var("JWT_SECRET").map_err(|_| UsuarioError::Unavailable)?;
        let ttl = env::var("JWT_TTL_SECONDS")
            .unwrap_or_else(|_| "3600".into())
            .parse()
            .map_err(|_| UsuarioError::Unavailable)?;
        Self::new(repository, secret, ttl).await
    }
    pub(super) async fn new(
        repository: UsuarioRepository,
        secret: String,
        ttl: u64,
    ) -> Result<Self, UsuarioError> {
        let tokens = Tokens::new(secret, ttl)?;
        let dummy_hash =
            tokio::task::spawn_blocking(|| hash_password("verificacion-ficticia-interna"))
                .await
                .map_err(|_| UsuarioError::Internal)??;
        Ok(Self {
            inner: Some(Arc::new(Inner {
                repository,
                tokens,
                dummy_hash,
                attempts: Mutex::new(Attempts::default()),
                hashing: Arc::new(Semaphore::new(4)),
            })),
        })
    }
    fn inner(&self) -> Result<&Arc<Inner>, UsuarioError> {
        self.inner.as_ref().ok_or(UsuarioError::Unavailable)
    }
    fn attempt(inner: &Inner, operation: &str, email: &str) -> Result<(), UsuarioError> {
        inner
            .attempts
            .lock()
            .map_err(|_| UsuarioError::Internal)?
            .check(format!("{operation}:{}", email_id(email)))
    }
    pub async fn register(&self, mut input: RegisterInput) -> Result<Usuario, UsuarioError> {
        input.nombre = validate_name(input.nombre)?;
        input.correo = normalize_email(&input.correo)?;
        if input.rol == Rol::Administrador {
            return Err(UsuarioError::Invalid(
                "Rol no permitido para registro público",
            ));
        }
        validate_password(&input.password)?;
        let inner = self.inner()?;
        Self::attempt(inner, "register", &input.correo)?;
        if inner.repository.by_email(&input.correo).await?.is_some() {
            return Err(UsuarioError::Duplicate);
        }
        let permit = inner
            .hashing
            .clone()
            .try_acquire_owned()
            .map_err(|_| UsuarioError::RateLimited)?;
        let password_hash = tokio::task::spawn_blocking(move || {
            let _permit = permit;
            hash_password(&input.password)
        })
        .await
        .map_err(|_| UsuarioError::Internal)??;
        let now = Utc::now();
        let document = UsuarioDocumento {
            id: email_id(&input.correo),
            rev: None,
            nombre: input.nombre,
            correo: input.correo,
            password_hash,
            rol: input.rol,
            estado: EstadoUsuario::Activo,
            fecha_creacion: now,
            fecha_actualizacion: now,
        };
        Ok(inner.repository.save(document).await?.into())
    }
    pub async fn login(&self, input: LoginInput) -> Result<LoginResponse, UsuarioError> {
        let email = normalize_email(&input.correo).map_err(|_| UsuarioError::Credentials)?;
        if input.password.is_empty() || input.password.len() > 512 {
            return Err(UsuarioError::Credentials);
        }
        let inner = self.inner()?;
        Self::attempt(inner, "login", &email)?;
        let document = inner.repository.by_email(&email).await?;
        let hash = document
            .as_ref()
            .map(|d| &d.password_hash)
            .unwrap_or(&inner.dummy_hash)
            .clone();
        let permit = inner
            .hashing
            .clone()
            .try_acquire_owned()
            .map_err(|_| UsuarioError::RateLimited)?;
        let valid = tokio::task::spawn_blocking(move || {
            let _permit = permit;
            verify_password(&input.password, &hash)
        })
        .await
        .map_err(|_| UsuarioError::Internal)??;
        let document = document
            .filter(|d| valid && d.estado == EstadoUsuario::Activo)
            .ok_or(UsuarioError::Credentials)?;
        Ok(LoginResponse {
            access_token: inner.tokens.issue(&document.id)?,
            token_type: "Bearer",
            expires_in: inner.tokens.ttl,
            usuario: document.into(),
        })
    }
    pub async fn authenticate(&self, token: &str) -> Result<Usuario, UsuarioError> {
        let inner = self.inner()?;
        let id = inner.tokens.verify(token)?;
        let document = inner.repository.get(&id).await.map_err(|e| {
            if matches!(e, UsuarioError::NotFound) {
                UsuarioError::Unauthorized
            } else {
                e
            }
        })?;
        if document.estado != EstadoUsuario::Activo {
            return Err(UsuarioError::Unauthorized);
        }
        Ok(document.into())
    }
    pub async fn update_profile(
        &self,
        user: &Usuario,
        input: ProfileInput,
    ) -> Result<Usuario, UsuarioError> {
        let name = validate_name(input.nombre)?;
        let inner = self.inner()?;
        let mut document = inner.repository.get(&user.id).await?;
        if document.estado != EstadoUsuario::Activo {
            return Err(UsuarioError::Unauthorized);
        }
        document.nombre = name;
        document.fecha_actualizacion = Utc::now();
        Ok(inner.repository.save(document).await?.into())
    }
}

fn validate_name(name: String) -> Result<String, UsuarioError> {
    let name = name.trim().to_owned();
    if name.is_empty() || name.len() > 250 || name.chars().any(char::is_control) {
        Err(UsuarioError::Invalid(
            "Nombre obligatorio, máximo 250 bytes y sin caracteres de control",
        ))
    } else {
        Ok(name)
    }
}
pub(super) fn normalize_email(email: &str) -> Result<String, UsuarioError> {
    let email = email.trim().to_ascii_lowercase();
    let invalid = || UsuarioError::Invalid("Correo inválido");
    if email.len() > 254 || !email.is_ascii() {
        return Err(invalid());
    }
    let (local, domain) = email.split_once('@').ok_or_else(invalid)?;
    if local.is_empty()
        || local.len() > 64
        || local.starts_with('.')
        || local.ends_with('.')
        || local.contains("..")
        || !local
            .bytes()
            .all(|c| c.is_ascii_alphanumeric() || b".!#$%&'*+-/=?^_`{|}~".contains(&c))
    {
        return Err(invalid());
    }
    let labels: Vec<_> = domain.split('.').collect();
    if labels.len() < 2
        || !labels.iter().all(|label| {
            !label.is_empty()
                && label.len() <= 63
                && !label.starts_with('-')
                && !label.ends_with('-')
                && label
                    .bytes()
                    .all(|c| c.is_ascii_alphanumeric() || c == b'-')
        })
    {
        return Err(invalid());
    }
    Ok(email)
}
pub(super) fn validate_password(password: &str) -> Result<(), UsuarioError> {
    let length = password.chars().count();
    let classes = [
        password.chars().any(char::is_lowercase),
        password.chars().any(char::is_uppercase),
        password.chars().any(|c| c.is_ascii_digit()),
        password
            .chars()
            .any(|c| !c.is_alphanumeric() && !c.is_whitespace()),
    ];
    if !(12..=128).contains(&length)
        || password.len() > 512
        || password.chars().any(char::is_control)
        || classes.into_iter().filter(|v| *v).count() < 3
    {
        return Err(UsuarioError::Invalid("Contraseña de 12 a 128 caracteres y al menos tres categorías: minúsculas, mayúsculas, números, símbolos"));
    }
    Ok(())
}
fn argon() -> Argon2<'static> {
    Argon2::new(
        Algorithm::Argon2id,
        Version::V0x13,
        Params::new(19456, 2, 1, Some(32)).expect("Parámetros constantes válidos"),
    )
}
pub(super) fn hash_password(password: &str) -> Result<String, UsuarioError> {
    let salt = SaltString::generate(&mut OsRng);
    argon()
        .hash_password(password.as_bytes(), &salt)
        .map(|hash| hash.to_string())
        .map_err(|_| UsuarioError::Internal)
}
pub(super) fn verify_password(password: &str, hash: &str) -> Result<bool, UsuarioError> {
    // Limita los parámetros procedentes de la BD para no aceptar costes arbitrarios.
    if !hash.starts_with("$argon2id$v=19$m=19456,t=2,p=1$") || hash.len() > 256 {
        return Err(UsuarioError::Upstream);
    }
    let parsed = PasswordHash::new(hash).map_err(|_| UsuarioError::Upstream)?;
    match argon().verify_password(password.as_bytes(), &parsed) {
        Ok(()) => Ok(true),
        Err(argon2::password_hash::Error::Password) => Ok(false),
        Err(_) => Err(UsuarioError::Upstream),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn validates_and_normalizes() {
        assert_eq!(
            normalize_email(" Demo@EXAMPLE.TEST ").unwrap(),
            "demo@example.test"
        );
        for email in [
            "",
            "a@",
            "a@@example.test",
            "a b@example.test",
            "a@-example.test",
        ] {
            assert!(normalize_email(email).is_err());
        }
        for password in ["short", "abcdefghijklmnop", "Abc123!"] {
            assert!(validate_password(password).is_err());
        }
        assert!(validate_password("Ficticia-Prueba-123!").is_ok());
        assert!(validate_name(" \t".into()).is_err());
    }
    #[test]
    fn secure_hash_has_random_salt_and_rejects_wrong_password() {
        let a = hash_password("Ficticia-Prueba-123!").unwrap();
        let b = hash_password("Ficticia-Prueba-123!").unwrap();
        assert_ne!(a, b);
        assert!(a.starts_with("$argon2id$"));
        assert!(!a.contains("Ficticia"));
        assert!(verify_password("Ficticia-Prueba-123!", &a).unwrap());
        assert!(!verify_password("Otra-ficticia-123!", &a).unwrap());
        assert!(verify_password("x", "$argon2id$v=19$m=999999999,t=2,p=1$abc$abc").is_err());
    }
    #[test]
    fn rate_limits_and_recovers_after_window() {
        let mut limits = Attempts::default();
        for _ in 0..5 {
            limits.check("demo".into()).unwrap();
        }
        assert!(matches!(
            limits.check("demo".into()),
            Err(UsuarioError::RateLimited)
        ));
        limits.emails.get_mut("demo").unwrap().start -= Duration::from_secs(61);
        limits.check("demo".into()).unwrap();
        limits.global.count = 100;
        assert!(limits.check("other".into()).is_err());
    }
}
