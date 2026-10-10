use axum::{
    extract::{FromRef, FromRequestParts},
    http::{header, request::Parts},
};
use jsonwebtoken::{decode, encode, Algorithm, DecodingKey, EncodingKey, Header, Validation};
use serde::{Deserialize, Serialize};

use super::{
    model::{Rol, Usuario},
    service::UsuarioService,
    UsuarioError,
};

pub(super) const ISSUER: &str = "credito-backend";
pub(super) const AUDIENCE: &str = "credito-api";

#[derive(Serialize, Deserialize)]
pub(super) struct Claims {
    pub sub: String,
    pub exp: u64,
    pub iat: u64,
    pub nbf: u64,
    pub iss: String,
    pub aud: String,
}

pub(super) struct Tokens {
    secret: Vec<u8>,
    pub ttl: u64,
}

impl Tokens {
    pub fn new(secret: String, ttl: u64) -> Result<Self, UsuarioError> {
        if secret.len() < 32
            || secret.trim() != secret
            || secret.to_ascii_uppercase().contains("CAMBIAR")
            || !(60..=86400).contains(&ttl)
        {
            return Err(UsuarioError::Unavailable);
        }
        Ok(Self {
            secret: secret.into_bytes(),
            ttl,
        })
    }
    pub fn issue(&self, id: &str) -> Result<String, UsuarioError> {
        let now = chrono::Utc::now().timestamp() as u64;
        self.sign(
            &Claims {
                sub: id.into(),
                exp: now + self.ttl,
                iat: now,
                nbf: now,
                iss: ISSUER.into(),
                aud: AUDIENCE.into(),
            },
            Algorithm::HS256,
        )
    }
    pub(super) fn sign(
        &self,
        claims: &Claims,
        algorithm: Algorithm,
    ) -> Result<String, UsuarioError> {
        encode(
            &Header::new(algorithm),
            claims,
            &EncodingKey::from_secret(&self.secret),
        )
        .map_err(|_| UsuarioError::Internal)
    }
    pub fn verify(&self, token: &str) -> Result<String, UsuarioError> {
        if token.len() > 4096 {
            return Err(UsuarioError::Unauthorized);
        }
        let mut validation = Validation::new(Algorithm::HS256);
        validation.leeway = 0;
        validation.validate_nbf = true;
        validation.set_issuer(&[ISSUER]);
        validation.set_audience(&[AUDIENCE]);
        validation.set_required_spec_claims(&["sub", "exp", "nbf", "iss", "aud"]);
        let claims = decode::<Claims>(token, &DecodingKey::from_secret(&self.secret), &validation)
            .map_err(|_| UsuarioError::Unauthorized)?
            .claims;
        let now = chrono::Utc::now().timestamp() as u64;
        if claims.sub.is_empty()
            || claims.sub.len() > 512
            || claims.sub.starts_with('_')
            || claims.sub.contains('/')
            || claims.sub == "."
            || claims.sub == ".."
            || claims.iat > now
            || claims.nbf < claims.iat
            || claims.exp <= now
            || claims.exp <= claims.iat
            || claims.exp - claims.iat > self.ttl
        {
            return Err(UsuarioError::Unauthorized);
        }
        Ok(claims.sub)
    }
}

/// Autenticación genérica: otros estados pueden implementar FromRef para UsuarioService.
pub struct AuthenticatedUser(pub Usuario);

impl<S> FromRequestParts<S> for AuthenticatedUser
where
    S: Send + Sync,
    UsuarioService: FromRef<S>,
{
    type Rejection = UsuarioError;
    async fn from_request_parts(parts: &mut Parts, state: &S) -> Result<Self, Self::Rejection> {
        let mut headers = parts.headers.get_all(header::AUTHORIZATION).iter();
        let value = headers.next().ok_or(UsuarioError::Unauthorized)?;
        if headers.next().is_some() {
            return Err(UsuarioError::Unauthorized);
        }
        let value = value.to_str().map_err(|_| UsuarioError::Unauthorized)?;
        let (scheme, token) = value.split_once(' ').ok_or(UsuarioError::Unauthorized)?;
        if !scheme.eq_ignore_ascii_case("Bearer")
            || token.is_empty()
            || token.contains(char::is_whitespace)
        {
            return Err(UsuarioError::Unauthorized);
        }
        Ok(Self(
            UsuarioService::from_ref(state).authenticate(token).await?,
        ))
    }
}

impl AuthenticatedUser {
    /// Autorización independiente de autenticación; usa el rol actual de CouchDB.
    #[allow(dead_code)]
    pub fn require_roles(&self, allowed: &[Rol]) -> Result<(), UsuarioError> {
        if allowed.contains(&self.0.rol) {
            Ok(())
        } else {
            Err(UsuarioError::Forbidden)
        }
    }
}
