use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum EstadoOferta {
    Abierta,
    ObjetivoAlcanzado,
    Cerrada,
    Cancelada,
    Financiada,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Oferta {
    #[serde(rename = "_id")]
    pub id: String,

    #[serde(rename = "_rev", skip_serializing_if = "Option::is_none")]
    pub revision: Option<String>,

    pub tipo: String,
    pub factura_id: String,
    pub empresa_id: String,
    pub monto_objetivo: f64,
    pub monto_recaudado: f64,
    pub moneda: String,
    pub tasa_rendimiento_anual: f64,
    pub estado: EstadoOferta,
    pub fecha_apertura: DateTime<Utc>,
    pub fecha_cierre: DateTime<Utc>,
    pub creado_por: String,
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct CrearOferta {
    pub factura_id: String,
    pub monto_objetivo: f64,
    pub tasa_rendimiento_anual: f64,
    pub fecha_cierre: DateTime<Utc>,
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct CrearInversion {
    pub oferta_id: String,
    pub monto: f64,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum EstadoInversion {
    Registrada,
    PagoPendiente,
    Confirmada,
    Liquidada,
    Reembolsada,
    Fallida,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Inversion {
    #[serde(rename = "_id")]
    pub id: String,

    #[serde(rename = "_rev", skip_serializing_if = "Option::is_none")]
    pub revision: Option<String>,

    pub tipo: String,
    pub oferta_id: String,
    pub factura_id: String,
    pub inversionista_id: String,
    pub monto: f64,
    pub moneda: String,
    pub estado: EstadoInversion,
    pub fecha_creacion: DateTime<Utc>,
    pub fecha_liquidacion: Option<DateTime<Utc>>,
    pub rendimiento_real: Option<f64>,
}

#[derive(Debug, Default, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct ListarOfertas {
    pub limit: Option<u32>,
    pub bookmark: Option<String>,
    pub estado: Option<EstadoOferta>,
}

#[derive(Debug, Serialize)]
pub struct OfertaPagina {
    pub ofertas: Vec<Oferta>,
    pub bookmark: String,
    pub limit: u32,
}

#[derive(Debug, Serialize)]
pub struct InversionPagina {
    pub inversiones: Vec<Inversion>,
    pub bookmark: String,
    pub limit: u32,
}