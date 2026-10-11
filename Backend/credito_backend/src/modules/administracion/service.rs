use std::collections::BTreeMap;

use chrono::{NaiveDate, Utc};
use serde_json::Value;

use super::{
    model::{AuditoriaPagina, AuditoriaQuery, EventoAuditoria, Modulo, ReporteModulo, Resumen},
    repository::AdministracionRepository,
    AdministracionError,
};
use crate::modules::usuarios::model::{EstadoUsuario, Rol, Usuario};

#[derive(Clone)]
pub struct AdministracionService {
    repository: Option<AdministracionRepository>,
}

impl AdministracionService {
    pub fn new(repository: Option<AdministracionRepository>) -> Self {
        Self { repository }
    }

    fn repository(&self) -> Result<&AdministracionRepository, AdministracionError> {
        self.repository
            .as_ref()
            .ok_or(AdministracionError::Configuration)
    }

    pub async fn resumen(&self, user: &Usuario) -> Result<Resumen, AdministracionError> {
        require_admin(user)?;
        let generado_en = Utc::now();
        let mut reportes = Vec::with_capacity(Modulo::TODOS.len());
        for modulo in Modulo::TODOS {
            reportes.push(self.aggregate(modulo, generado_en.date_naive()).await?);
        }
        Ok(Resumen {
            generado_en,
            reportes,
        })
    }

    pub async fn reporte(
        &self,
        user: &Usuario,
        modulo: Modulo,
    ) -> Result<ReporteModulo, AdministracionError> {
        require_admin(user)?;
        self.aggregate(modulo, Utc::now().date_naive()).await
    }

    async fn aggregate(
        &self,
        modulo: Modulo,
        today: NaiveDate,
    ) -> Result<ReporteModulo, AdministracionError> {
        let mut report = ReporteModulo::new(modulo);
        self.repository()?
            .scan(modulo, |document| accumulate(&mut report, &document, today))
            .await?;
        Ok(report)
    }

    pub async fn auditoria(
        &self,
        user: &Usuario,
        input: AuditoriaQuery,
    ) -> Result<AuditoriaPagina, AdministracionError> {
        require_admin(user)?;
        let limit = input.limit.unwrap_or(25);
        if !(1..=100).contains(&limit) {
            return Err(AdministracionError::Invalid(
                "limit debe estar entre 1 y 100",
            ));
        }
        if input.bookmark.as_ref().is_some_and(|b| b.len() > 8192) {
            return Err(AdministracionError::Invalid("bookmark demasiado largo"));
        }
        for id in [input.actor_id.as_deref(), input.recurso_id.as_deref()]
            .into_iter()
            .flatten()
        {
            if id.is_empty() || id.len() > 512 || id.chars().any(char::is_control) {
                return Err(AdministracionError::Invalid(
                    "Filtro de identificador inválido",
                ));
            }
        }
        let page = self.repository()?.auditoria(&input, limit).await?;
        if page.docs.len() > limit as usize {
            return Err(AdministracionError::Upstream);
        }
        let eventos = page
            .docs
            .into_iter()
            .map(|doc| {
                if doc["tipo"] != "evento"
                    || input
                        .actor_id
                        .as_ref()
                        .is_some_and(|id| doc["actor_id"] != *id)
                    || input
                        .recurso_id
                        .as_ref()
                        .is_some_and(|id| doc["recurso_id"] != *id)
                {
                    return Err(AdministracionError::Upstream);
                }
                event_from_document(doc)
            })
            .collect::<Result<Vec<_>, _>>()?;
        Ok(AuditoriaPagina {
            eventos,
            bookmark: page.bookmark,
            limit,
        })
    }
}

fn require_admin(user: &Usuario) -> Result<(), AdministracionError> {
    if user.rol != Rol::Administrador || user.estado != EstadoUsuario::Activo {
        return Err(AdministracionError::Forbidden);
    }
    Ok(())
}

fn string<'a>(doc: &'a Value, key: &str) -> Result<&'a str, AdministracionError> {
    doc.get(key)
        .and_then(Value::as_str)
        .filter(|s| !s.is_empty())
        .ok_or(AdministracionError::Upstream)
}

fn cents(doc: &Value, key: &str) -> Result<i64, AdministracionError> {
    doc.get(key)
        .and_then(Value::as_i64)
        .filter(|v| *v >= 0)
        .ok_or(AdministracionError::Upstream)
}

/// Compatibilidad con ofertas/inversiones existentes, almacenadas en unidades monetarias.
fn legacy_cents(doc: &Value, key: &str) -> Result<i64, AdministracionError> {
    let amount = doc
        .get(key)
        .and_then(Value::as_f64)
        .ok_or(AdministracionError::Upstream)?;
    let cents = (amount * 100.0).round();
    if !cents.is_finite() || cents < 0.0 || cents >= i64::MAX as f64 {
        return Err(AdministracionError::Upstream);
    }
    Ok(cents as i64)
}

fn add_count(map: &mut BTreeMap<String, u64>, key: &str) -> Result<(), AdministracionError> {
    let total = map.entry(key.into()).or_default();
    *total = total.checked_add(1).ok_or(AdministracionError::Upstream)?;
    Ok(())
}

fn add_amount(
    report: &mut ReporteModulo,
    currency: &str,
    key: &str,
    amount: i64,
) -> Result<(), AdministracionError> {
    let total = report
        .montos_por_moneda
        .entry(currency.into())
        .or_default()
        .entry(key.into())
        .or_default();
    *total = total
        .checked_add(amount)
        .ok_or(AdministracionError::Upstream)?;
    Ok(())
}

pub(super) fn accumulate(
    report: &mut ReporteModulo,
    doc: &Value,
    today: NaiveDate,
) -> Result<(), AdministracionError> {
    let modulo = report.modulo;
    if modulo == Modulo::Pagos {
        let currency = string(doc, "moneda")?;
        let pagos = doc["pagos"]
            .as_array()
            .ok_or(AdministracionError::Upstream)?;
        for pago in pagos {
            report.total = report
                .total
                .checked_add(1)
                .ok_or(AdministracionError::Upstream)?;
            add_amount(
                report,
                currency,
                "pagado_centavos",
                cents(pago, "monto_centavos")?,
            )?;
        }
        return Ok(());
    }
    report.total = report
        .total
        .checked_add(1)
        .ok_or(AdministracionError::Upstream)?;
    if modulo == Modulo::Auditoria {
        return Ok(());
    }
    // EmpresaDatos admite documentos anteriores al campo estado como pendientes.
    let mut estado = if modulo == Modulo::Empresas && doc.get("estado").is_none() {
        "pendiente"
    } else {
        string(doc, "estado")?
    };
    if modulo == Modulo::Creditos {
        let total = cents(doc, "total_centavos")?;
        let paid = cents(doc, "pagado_centavos")?;
        let due = NaiveDate::parse_from_str(string(doc, "fecha_vencimiento")?, "%Y-%m-%d")
            .map_err(|_| AdministracionError::Upstream)?;
        if paid > total {
            return Err(AdministracionError::Upstream);
        }
        if estado == "activo" && due < today && paid < total {
            estado = "vencido";
        }
    }
    add_count(&mut report.por_estado, estado)?;
    match modulo {
        Modulo::Usuarios => add_count(&mut report.por_rol, string(doc, "rol")?)?,
        Modulo::Empresas => (),
        Modulo::Facturas => {
            let currency = string(doc, "moneda")?;
            add_amount(
                report,
                currency,
                "total_centavos",
                cents(doc, "monto_total_centavos")?,
            )?;
            let financed = if doc.get("monto_financiado_centavos").is_some() {
                cents(doc, "monto_financiado_centavos")?
            } else {
                0
            };
            add_amount(report, currency, "financiado_centavos", financed)?;
        }
        Modulo::Ofertas => {
            let currency = string(doc, "moneda")?;
            add_amount(
                report,
                currency,
                "objetivo_centavos",
                legacy_cents(doc, "monto_objetivo")?,
            )?;
            add_amount(
                report,
                currency,
                "recaudado_centavos",
                legacy_cents(doc, "monto_recaudado")?,
            )?;
        }
        Modulo::Inversiones => add_amount(
            report,
            string(doc, "moneda")?,
            "invertido_centavos",
            legacy_cents(doc, "monto")?,
        )?,
        Modulo::Creditos => {
            let currency = string(doc, "moneda")?;
            for key in [
                "capital_centavos",
                "interes_centavos",
                "total_centavos",
                "pagado_centavos",
            ] {
                add_amount(report, currency, key, cents(doc, key)?)?;
            }
            add_amount(
                report,
                currency,
                "saldo_centavos",
                cents(doc, "total_centavos")? - cents(doc, "pagado_centavos")?,
            )?;
        }
        Modulo::Pagos | Modulo::Auditoria => (),
    }
    Ok(())
}

fn event_from_document(doc: Value) -> Result<EventoAuditoria, AdministracionError> {
    let mut detalles = BTreeMap::new();
    if let Some(source) = doc.get("detalles").and_then(Value::as_object) {
        // No propagar campos arbitrarios: auditoría puede contener eventos de otros módulos.
        for key in [
            "estado_anterior",
            "estado_nuevo",
            "moneda",
            "credito_id",
            "pago_id",
            "oferta_id",
            "factura_id",
            "empresa_id",
        ] {
            if let Some(value) = source
                .get(key)
                .filter(|v| v.as_str().is_some_and(|s| s.len() <= 512))
            {
                detalles.insert(key.into(), value.clone());
            }
        }
        if let Some(value) = source
            .get("monto_centavos")
            .filter(|v| v.as_i64().is_some_and(|m| m >= 0))
        {
            detalles.insert("monto_centavos".into(), value.clone());
        }
    }
    Ok(EventoAuditoria {
        id: string(&doc, "_id")?.into(),
        actor_id: string(&doc, "actor_id")?.into(),
        accion: string(&doc, "accion")?.into(),
        recurso_tipo: string(&doc, "recurso_tipo")?.into(),
        recurso_id: string(&doc, "recurso_id")?.into(),
        fecha: string(&doc, "fecha")?
            .parse()
            .map_err(|_| AdministracionError::Upstream)?,
        detalles,
    })
}
