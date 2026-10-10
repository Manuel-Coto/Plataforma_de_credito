use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum EstadoEmpresa {
    #[default]
    Pendiente,
    Activa,
    Rechazada,
    Inactiva,
}

/// El mismo cuerpo se usa para POST y PUT. PUT reemplaza los datos de contacto.
/// Campos administrados por el servidor (estado, id, fechas, _rev) se rechazan.
#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct EmpresaInput {
    pub nombre: String,
    pub nit: String,
    pub correo: String,
    pub telefono: String,
    pub direccion: String,
    pub usuario_responsable_id: Option<String>,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct EmpresaDatos {
    pub nombre: String,
    pub nit: String,
    #[serde(default)]
    pub correo: String,
    #[serde(default)]
    pub telefono: String,
    #[serde(default)]
    pub direccion: String,
    #[serde(default)]
    pub estado: EstadoEmpresa,
    #[serde(default)]
    pub usuario_responsable_id: Option<String>,
    // Documentos antiguos pueden no tener fechas: no inventamos su historial.
    #[serde(default)]
    pub fecha_creacion: Option<DateTime<Utc>>,
    #[serde(default)]
    pub fecha_actualizacion: Option<DateTime<Utc>>,
}

#[derive(Debug, Serialize)]
pub struct Empresa {
    pub id: String,
    #[serde(flatten)]
    pub datos: EmpresaDatos,
}

/// Metadatos CouchDB separados de la respuesta pública.
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct EmpresaDocumento {
    #[serde(rename = "_id", skip_serializing_if = "Option::is_none")]
    pub id: Option<String>,
    #[serde(rename = "_rev", skip_serializing_if = "Option::is_none")]
    pub rev: Option<String>,
    #[serde(flatten)]
    pub datos: EmpresaDatos,
}

impl EmpresaDocumento {
    pub fn into_empresa(self) -> Result<Empresa, super::EmpresaError> {
        Ok(Empresa {
            id: self
                .id
                .filter(|id| !id.is_empty())
                .ok_or(super::EmpresaError::Upstream)?,
            datos: self.datos,
        })
    }
}

#[derive(Debug, Default, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct ListQuery {
    pub limit: Option<u32>,
    pub bookmark: Option<String>,
}

#[derive(Debug, Serialize)]
pub struct EmpresaPagina {
    pub empresas: Vec<Empresa>,
    pub bookmark: String,
    pub limit: u32,
}
