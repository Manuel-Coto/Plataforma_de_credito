use chrono::{DateTime, NaiveDate, Utc};
use serde::{Deserialize, Serialize};
use std::collections::BTreeMap;

#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum EstadoFactura {
    PendienteVerificacion,
    Verificada,
    Disponible,
    ParcialmenteFinanciada,
    Financiada,
    Pagada,
    Vencida,
    Rechazada,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct DatosDte {
    pub codigo_generacion: String,
    #[serde(default)]
    pub sello_recepcion: Option<String>,
    #[serde(default)]
    pub verificado: bool,
    #[serde(default)]
    pub fecha_verificacion: Option<DateTime<Utc>>,
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct CrearFactura {
    pub empresa_id: String,
    pub numero: String,
    pub codigo_generacion: String,
    pub moneda: String,
    /// Importe expresado en centavos para evitar errores de punto flotante.
    pub monto_total_centavos: i64,
    pub fecha_emision: NaiveDate,
    pub fecha_vencimiento: NaiveDate,
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct VerificarDte {
    pub sello_recepcion: String,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct FacturaDocumento {
    #[serde(rename = "_id", skip_serializing_if = "Option::is_none")]
    pub id: Option<String>,
    #[serde(rename = "_rev", skip_serializing_if = "Option::is_none")]
    pub rev: Option<String>,
    pub tipo: String,
    pub empresa_id: String,
    pub numero: String,
    pub dte: DatosDte,
    pub moneda: String,
    pub monto_total_centavos: i64,
    #[serde(default)]
    pub monto_financiado_centavos: i64,
    pub fecha_emision: NaiveDate,
    pub fecha_vencimiento: NaiveDate,
    pub estado: EstadoFactura,
    pub creado_por: String,
    pub fecha_creacion: DateTime<Utc>,
    #[serde(default)]
    pub fecha_actualizacion: Option<DateTime<Utc>>,
    #[serde(flatten)]
    pub extra: BTreeMap<String, serde_json::Value>,
}

#[derive(Debug, Serialize)]
pub struct Factura {
    pub id: String,
    #[serde(flatten)]
    pub datos: FacturaDocumento,
}
impl FacturaDocumento {
    pub fn into_factura(self) -> Result<Factura, super::FacturaError> {
        let id = self
            .id
            .clone()
            .filter(|s| !s.is_empty())
            .ok_or(super::FacturaError::Upstream)?;
        Ok(Factura { id, datos: self })
    }
}

#[derive(Debug, Default, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct ListQuery {
    pub limit: Option<u32>,
    pub bookmark: Option<String>,
    pub estado: Option<EstadoFactura>,
}
#[derive(Debug, Serialize)]
pub struct FacturaPagina {
    pub facturas: Vec<Factura>,
    pub bookmark: String,
    pub limit: u32,
}
