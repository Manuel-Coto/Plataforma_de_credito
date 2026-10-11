use chrono::{DateTime, NaiveDate, Utc};
use serde::{Deserialize, Serialize};

#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum EstadoCredito {
    Activo,
    Pagado,
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct CrearCredito {
    pub oferta_id: String,
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct RegistrarPago {
    pub referencia: String,
    pub monto_centavos: i64,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct Pago {
    pub id: String,
    pub referencia: String,
    pub monto_centavos: i64,
    pub registrado_por: String,
    pub fecha: DateTime<Utc>,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct Participacion {
    pub inversion_id: String,
    pub inversionista_id: String,
    pub capital_centavos: i64,
    pub interes_centavos: i64,
}

/// Fuente de verdad: el saldo y su historial se guardan en una sola revisión.
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct CreditoDocumento {
    #[serde(rename = "_id")]
    pub id: String,
    #[serde(rename = "_rev", skip_serializing_if = "Option::is_none")]
    pub revision: Option<String>,
    pub tipo: String,
    pub oferta_id: String,
    pub factura_id: String,
    pub empresa_id: String,
    pub responsable_id: String,
    pub inversionistas_ids: Vec<String>,
    pub moneda: String,
    pub capital_centavos: i64,
    pub interes_centavos: i64,
    pub total_centavos: i64,
    pub pagado_centavos: i64,
    pub tasa_anual_bp: i64,
    pub estado: EstadoCredito,
    pub version: u64,
    pub creado_por: String,
    pub fecha_creacion: DateTime<Utc>,
    pub fecha_vencimiento: NaiveDate,
    pub fecha_pago_total: Option<DateTime<Utc>>,
    pub pagos: Vec<Pago>,
    pub participaciones: Vec<Participacion>,
}

/// La revisión de CouchDB y los participantes ajenos no se exponen al inversionista.
#[derive(Debug, Serialize)]
pub struct CreditoVista {
    pub id: String,
    pub oferta_id: String,
    pub factura_id: String,
    pub empresa_id: String,
    pub moneda: String,
    pub capital_centavos: i64,
    pub interes_centavos: i64,
    pub total_centavos: i64,
    pub pagado_centavos: i64,
    pub saldo_centavos: i64,
    pub tasa_anual_bp: i64,
    pub estado: EstadoCredito,
    pub vencido: bool,
    pub dias_mora: i64,
    pub version: u64,
    pub fecha_creacion: DateTime<Utc>,
    pub fecha_vencimiento: NaiveDate,
    pub fecha_pago_total: Option<DateTime<Utc>>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub pagos: Option<Vec<Pago>>,
    pub participaciones: Vec<Participacion>,
}

#[derive(Debug, Default, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct ListQuery {
    pub limit: Option<u32>,
    pub bookmark: Option<String>,
    pub estado: Option<EstadoCredito>,
}

#[derive(Debug, Serialize)]
pub struct CreditoPagina {
    pub creditos: Vec<CreditoVista>,
    pub bookmark: String,
    pub limit: u32,
}

#[derive(Debug, Serialize)]
pub struct CreditoResultado {
    pub credito: CreditoVista,
    /// El crédito/pago ya está guardado aunque falle una proyección relacionada.
    pub sincronizacion_pendiente: bool,
}

#[derive(Debug, Serialize)]
pub struct AporteResultado {
    pub inversion_id: String,
    pub estado: &'static str,
    pub simulado: bool,
    pub sincronizacion_pendiente: bool,
}
