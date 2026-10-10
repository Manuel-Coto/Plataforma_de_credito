use reqwest::{Client, Url};
use std::{env, time::Duration};

/// Adaptación del cliente de origin/main. No deriva Debug para proteger secretos.
pub struct CouchDb {
    pub client: Client,
    pub url: String,
    pub username: String,
    pub password: String,
}

impl CouchDb {
    pub fn new() -> Result<Self, super::init::InitError> {
        Self::from_parts(
            env::var("COUCHDB_URL").map_err(|_| super::init::InitError::Configuration)?,
            env::var("COUCHDB_USERNAME").map_err(|_| super::init::InitError::Configuration)?,
            env::var("COUCHDB_PASSWORD").map_err(|_| super::init::InitError::Configuration)?,
        )
    }
    pub(crate) fn from_parts(
        url: String,
        username: String,
        password: String,
    ) -> Result<Self, super::init::InitError> {
        let parsed = Url::parse(&url).map_err(|_| super::init::InitError::Configuration)?;
        if !matches!(parsed.scheme(), "http" | "https")
            || parsed.host_str().is_none()
            || !parsed.username().is_empty()
            || parsed.password().is_some()
            || parsed.query().is_some()
            || parsed.fragment().is_some()
            || username.trim().is_empty()
            || password.is_empty()
        {
            return Err(super::init::InitError::Configuration);
        }
        let client = Client::builder()
            .connect_timeout(Duration::from_secs(3))
            .timeout(Duration::from_secs(10))
            .redirect(reqwest::redirect::Policy::none())
            .build()
            .map_err(|_| super::init::InitError::Configuration)?;
        Ok(Self {
            client,
            url: url.trim_end_matches('/').into(),
            username,
            password,
        })
    }
}
