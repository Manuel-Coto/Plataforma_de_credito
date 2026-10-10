use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};

#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum Rol {
    Pyme,
    Inversionista,
    Administrador,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum EstadoUsuario {
    Activo,
    Inactivo,
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
pub struct RegisterInput {
    pub nombre: String,
    pub correo: String,
    pub password: String,
    pub rol: Rol,
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
pub struct LoginInput {
    pub correo: String,
    pub password: String,
}

/// El correo identifica la cuenta y queda inmutable en este módulo inicial.
#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
pub struct ProfileInput {
    pub nombre: String,
}

// No deriva Debug: evita mostrar hashes accidentalmente en diagnósticos.
#[derive(Clone, Serialize, Deserialize)]
pub struct UsuarioDocumento {
    #[serde(rename = "_id")]
    pub id: String,
    #[serde(rename = "_rev", skip_serializing_if = "Option::is_none")]
    pub rev: Option<String>,
    pub nombre: String,
    pub correo: String,
    pub password_hash: String,
    pub rol: Rol,
    pub estado: EstadoUsuario,
    pub fecha_creacion: DateTime<Utc>,
    pub fecha_actualizacion: DateTime<Utc>,
}

#[derive(Clone, Serialize)]
pub struct Usuario {
    pub id: String,
    pub nombre: String,
    pub correo: String,
    pub rol: Rol,
    pub estado: EstadoUsuario,
    pub fecha_creacion: DateTime<Utc>,
    pub fecha_actualizacion: DateTime<Utc>,
}

impl From<UsuarioDocumento> for Usuario {
    fn from(doc: UsuarioDocumento) -> Self {
        Self {
            id: doc.id,
            nombre: doc.nombre,
            correo: doc.correo,
            rol: doc.rol,
            estado: doc.estado,
            fecha_creacion: doc.fecha_creacion,
            fecha_actualizacion: doc.fecha_actualizacion,
        }
    }
}

#[derive(Serialize)]
pub struct LoginResponse {
    pub access_token: String,
    pub token_type: &'static str,
    pub expires_in: u64,
    pub usuario: Usuario,
}
