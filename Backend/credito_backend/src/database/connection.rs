
use std::env;
use std::time::Duration;

use reqwest::Client;

pub struct CouchDb {
    pub client: Client,
    pub url: String,
    pub username: String,
    pub password: String,
}

impl CouchDb {
    pub fn new() -> Result<Self, Box<dyn std::error::Error>> {
        let url = env::var("COUCHDB_URL")?;
        let username = env::var("COUCHDB_USERNAME")?;
        let password = env::var("COUCHDB_PASSWORD")?;

        let client = Client::builder()
            .timeout(Duration::from_secs(10))
            .build()?;

        Ok(Self {
            client,
            url: url.trim_end_matches('/').to_string(),
            username,
            password,
        })
    }
}
