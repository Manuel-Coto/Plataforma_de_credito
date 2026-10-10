use super::connection::CouchDb;
use reqwest::StatusCode;
use serde_json::Value;

pub const BASES: &[&str] = &[
    "usuarios",
    "empresas",
    "facturas",
    "ofertas",
    "operaciones",
    "auditoria",
];

/// Solo contiene información estructural segura para logs.
#[derive(Debug)]
pub enum InitError {
    Configuration,
    Transport,
    Http { base: &'static str, status: u16 },
    InvalidIndex { base: &'static str },
}

impl std::fmt::Display for InitError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::Configuration => write!(f, "configuración inválida"),
            Self::Transport => write!(f, "conexión o solicitud fallida"),
            Self::Http { base, status } => write!(f, "base {base}: HTTP {status}"),
            Self::InvalidIndex { base } => {
                write!(f, "base {base}: respuesta de índice incompatible")
            }
        }
    }
}

pub async fn inicializar_bases(db: &CouchDb) -> Result<(), InitError> {
    for &base in BASES {
        let response = db
            .client
            .put(format!("{}/{base}", db.url))
            .basic_auth(&db.username, Some(&db.password))
            .send()
            .await
            .map_err(|_| InitError::Transport)?;
        match response.status() {
            StatusCode::CREATED | StatusCode::ACCEPTED | StatusCode::PRECONDITION_FAILED => {
                tracing::info!(
                    base,
                    status = response.status().as_u16(),
                    "Base CouchDB disponible"
                );
            }
            status => {
                return Err(InitError::Http {
                    base,
                    status: status.as_u16(),
                })
            }
        }
    }
    inicializar_indices(db).await
}

pub async fn inicializar_indices(db: &CouchDb) -> Result<(), InitError> {
    let definitions = [
        (
            "empresas",
            include_str!("../../../../database/empresas/indexes/por_nit.json"),
        ),
        (
            "usuarios",
            include_str!("../../../../database/usuarios/indexes/por_correo.json"),
        ),
        (
            "empresas",
            include_str!("../../../../database/empresas/indexes/por_responsable.json"),
        ),
    ];
    for (base, source) in definitions {
        let definition: Value =
            serde_json::from_str(source).map_err(|_| InitError::InvalidIndex { base })?;
        let response = db
            .client
            .post(format!("{}/{base}/_index", db.url))
            .basic_auth(&db.username, Some(&db.password))
            .json(&definition)
            .send()
            .await
            .map_err(|_| InitError::Transport)?;
        if !matches!(response.status(), StatusCode::OK | StatusCode::CREATED) {
            return Err(InitError::Http {
                base,
                status: response.status().as_u16(),
            });
        }
        let body: Value = response
            .json()
            .await
            .map_err(|_| InitError::InvalidIndex { base })?;
        if !matches!(body["result"].as_str(), Some("created" | "exists")) {
            return Err(InitError::InvalidIndex { base });
        }
        tracing::info!(base, "Índice Mango disponible");
    }
    Ok(())
}
