use axum::http::HeaderMap;
use serde_json::Value;
use sha2::{Digest, Sha256};

pub fn key(headers: &HeaderMap) -> Result<Option<&str>, &'static str> {
    let mut values = headers.get_all("idempotency-key").iter();
    let Some(value) = values.next() else {
        return Ok(None);
    };
    if values.next().is_some() {
        return Err("Idempotency-Key debe contener una única clave");
    }
    let value = value.to_str().map_err(|_| "Idempotency-Key inválida")?;
    if value.is_empty() || value.len() > 128 || !value.bytes().all(|b| b.is_ascii_graphic()) {
        return Err("Idempotency-Key debe tener entre 1 y 128 caracteres ASCII sin espacios");
    }
    Ok(Some(value))
}

pub fn document_id(kind: &str, user_id: &str, key: &str) -> String {
    // Length prefix prevents ambiguous concatenations and the actor isolates keys.
    let digest = Sha256::digest(format!("{}:{user_id}{key}", user_id.len()).as_bytes());
    format!("{kind}-solicitud-{digest:x}")
}

pub fn fingerprint(value: Value) -> String {
    format!("{:x}", Sha256::digest(value.to_string().as_bytes()))
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn keys_are_bounded_and_scoped_to_actor() {
        let mut headers = HeaderMap::new();
        assert_eq!(key(&headers).unwrap(), None);
        headers.insert("idempotency-key", "key".parse().unwrap());
        assert_eq!(key(&headers).unwrap(), Some("key"));
        assert_ne!(
            document_id("empresa", "ab", "c"),
            document_id("empresa", "a", "bc")
        );
        headers.append("idempotency-key", "second".parse().unwrap());
        assert!(key(&headers).is_err());
        headers.remove("idempotency-key");
        headers.insert("idempotency-key", "has space".parse().unwrap());
        assert!(key(&headers).is_err());
    }
}
