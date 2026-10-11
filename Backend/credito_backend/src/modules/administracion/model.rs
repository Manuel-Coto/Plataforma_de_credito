use std::collections::BTreeMap;

use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use serde_json::Value;

#[derive(Clone, Copy, Debug, Deserialize, Serialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum Modulo {
    Usuarios,
    Empresas,
    Facturas,
    Ofertas,
    Inversiones,
    Creditos,
    Pagos,
    Auditoria,
}

impl Modulo {
    pub const TODOS: [Self; 8] = [
        Self::Usuarios,
        Self::Empresas,
        Self::Facturas,
        Self::Ofertas,
        Self::Inversiones,
        Self::Creditos,
        Self::Pagos,
        Self::Auditoria,
    ];

    pub(super) fn database(self) -> &'static str {
        match self {
            Self::Usuarios => "usuarios",
            Self::Empresas => "empresas",
            Self::Facturas => "facturas",
            Self::Ofertas => "ofertas",
            Self::Inversiones | Self::Creditos | Self::Pagos => "operaciones",
            Self::Auditoria => "auditoria",
        }
    }

    pub(super) fn document_type(self) -> Option<&'static str> {
        match self {
            Self::Usuarios | Self::Empresas => None,
            Self::Facturas => Some("factura"),
            Self::Ofertas => Some("oferta"),
            Self::Inversiones => Some("inversion"),
            Self::Creditos | Self::Pagos => Some("credito"),
            Self::Auditoria => Some("evento"),
        }
    }
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
pub struct ReporteQuery {
    pub modulo: Modulo,
}

#[derive(Default, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct AuditoriaQuery {
    pub limit: Option<u32>,
    pub bookmark: Option<String>,
    pub actor_id: Option<String>,
    pub recurso_id: Option<String>,
}

#[derive(Serialize)]
pub struct ReporteModulo {
    pub modulo: Modulo,
    pub total: u64,
    pub por_estado: BTreeMap<String, u64>,
    pub por_rol: BTreeMap<String, u64>,
    /// Cada moneda se agrega de forma independiente; todos los importes son centavos.
    pub montos_por_moneda: BTreeMap<String, BTreeMap<String, i64>>,
}

impl ReporteModulo {
    pub(super) fn new(modulo: Modulo) -> Self {
        Self {
            modulo,
            total: 0,
            por_estado: BTreeMap::new(),
            por_rol: BTreeMap::new(),
            montos_por_moneda: BTreeMap::new(),
        }
    }
}

#[derive(Serialize)]
pub struct Resumen {
    pub generado_en: DateTime<Utc>,
    pub reportes: Vec<ReporteModulo>,
}

#[derive(Serialize)]
pub struct EventoAuditoria {
    pub id: String,
    pub actor_id: String,
    pub accion: String,
    pub recurso_tipo: String,
    pub recurso_id: String,
    pub fecha: DateTime<Utc>,
    pub detalles: BTreeMap<String, Value>,
}

#[derive(Serialize)]
pub struct AuditoriaPagina {
    pub eventos: Vec<EventoAuditoria>,
    pub bookmark: String,
    pub limit: u32,
}
