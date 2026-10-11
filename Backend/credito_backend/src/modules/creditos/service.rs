use super::{model::*, repository::CreditoRepository, CreditoError};
use crate::modules::{
    facturas::model::{EstadoFactura, FacturaDocumento},
    inversiones::model::{EstadoInversion, EstadoOferta, Inversion, Oferta},
    usuarios::model::{Rol, Usuario},
};
use chrono::{NaiveDate, Utc};
use serde_json::{json, Value};
use sha2::{Digest, Sha256};

#[derive(Clone)]
pub struct CreditoService {
    repository: Option<CreditoRepository>,
}

impl CreditoService {
    pub fn new(repository: Option<CreditoRepository>) -> Self {
        Self { repository }
    }
    fn repo(&self) -> Result<&CreditoRepository, CreditoError> {
        self.repository.as_ref().ok_or(CreditoError::Unavailable)
    }

    pub async fn create(
        &self,
        user: &Usuario,
        input: CrearCredito,
    ) -> Result<CreditoResultado, CreditoError> {
        require_admin(user)?;
        validar_id(&input.oferta_id)?;
        let repo = self.repo()?;
        let oferta: Oferta = repo.get("ofertas", &input.oferta_id).await?;
        if oferta.tipo != "oferta" || oferta.id != input.oferta_id {
            return Err(CreditoError::NotFound);
        }
        validar_id(&oferta.factura_id)?;
        // Una sola deuda por factura, incluso si existen varias ofertas para ella.
        let id = stable_id("credito", &oferta.factura_id);
        match repo.credito(&id).await {
            Ok(existing) => {
                if existing.oferta_id != oferta.id {
                    return Err(CreditoError::Conflict);
                }
                return Ok(self.resultado(user, existing).await);
            }
            Err(CreditoError::NotFound) => {}
            Err(error) => return Err(error),
        }
        if oferta.estado != EstadoOferta::ObjetivoAlcanzado || oferta.moneda != "USD" {
            return Err(CreditoError::Conflict);
        }
        let factura: FacturaDocumento = repo.get("facturas", &oferta.factura_id).await?;
        if factura.tipo != "factura" || factura.id.as_deref() != Some(oferta.factura_id.as_str()) {
            return Err(CreditoError::NotFound);
        }
        if !factura.dte.verificado
            || factura.estado != EstadoFactura::Disponible
            || factura.moneda != "USD"
            || factura.empresa_id != oferta.empresa_id
        {
            return Err(CreditoError::Conflict);
        }
        validar_id(&factura.empresa_id)?;
        let empresa: Value = repo.get("empresas", &factura.empresa_id).await?;
        if empresa["_id"] != factura.empresa_id {
            return Err(CreditoError::Upstream);
        }
        if empresa["estado"] != "activa" {
            return Err(CreditoError::Conflict);
        }
        let responsable = empresa["usuario_responsable_id"]
            .as_str()
            .filter(|s| !s.is_empty())
            .ok_or(CreditoError::Conflict)?;
        let capital = centavos(oferta.monto_objetivo)?;
        if capital > factura.monto_total_centavos || capital != centavos(oferta.monto_recaudado)? {
            return Err(CreditoError::Conflict);
        }
        let ahora = Utc::now();
        let dias = factura
            .fecha_vencimiento
            .signed_duration_since(ahora.date_naive())
            .num_days();
        if dias <= 0 {
            return Err(CreditoError::Invalid(
                "La factura debe vencer después de hoy",
            ));
        }
        if !oferta.tasa_rendimiento_anual.is_finite()
            || !(0.0..=100.0).contains(&oferta.tasa_rendimiento_anual)
        {
            return Err(CreditoError::Upstream);
        }
        let tasa = (oferta.tasa_rendimiento_anual * 100.0).round() as i64;
        let interes = calcular_interes(capital, tasa, dias)?;
        let total = capital.checked_add(interes).ok_or(CreditoError::Upstream)?;
        let mut inversiones: Vec<Inversion> = repo
            .all(
                "operaciones",
                json!({"tipo":"inversion", "oferta_id":oferta.id}),
            )
            .await?;
        inversiones.sort_by(|a, b| a.id.cmp(&b.id));
        if inversiones.is_empty() || inversiones.len() > 5000 {
            return Err(CreditoError::Conflict);
        }
        let mut seen = std::collections::HashSet::new();
        let mut participaciones = Vec::new();
        let mut suma: i64 = 0;
        for inversion in inversiones {
            if inversion.tipo != "inversion"
                || inversion.oferta_id != oferta.id
                || inversion.factura_id != oferta.factura_id
                || inversion.moneda != "USD"
                || inversion.estado != EstadoInversion::Confirmada
                || !seen.insert(inversion.id.clone())
            {
                return Err(CreditoError::Conflict);
            }
            validar_id(&inversion.id)?;
            validar_id(&inversion.inversionista_id)?;
            let monto = centavos(inversion.monto)?;
            suma = suma.checked_add(monto).ok_or(CreditoError::Upstream)?;
            participaciones.push(Participacion {
                inversion_id: inversion.id,
                inversionista_id: inversion.inversionista_id,
                capital_centavos: monto,
                interes_centavos: 0,
            });
        }
        if suma != capital {
            return Err(CreditoError::Conflict);
        }
        distribuir_interes(&mut participaciones, capital, interes);
        let mut inversionistas_ids: Vec<_> = participaciones
            .iter()
            .map(|p| p.inversionista_id.clone())
            .collect();
        inversionistas_ids.sort();
        inversionistas_ids.dedup();
        let doc = CreditoDocumento {
            id: id.clone(),
            revision: None,
            tipo: "credito".into(),
            oferta_id: oferta.id.clone(),
            factura_id: oferta.factura_id,
            empresa_id: factura.empresa_id,
            responsable_id: responsable.into(),
            inversionistas_ids,
            moneda: "USD".into(),
            capital_centavos: capital,
            interes_centavos: interes,
            total_centavos: total,
            pagado_centavos: 0,
            tasa_anual_bp: tasa,
            estado: EstadoCredito::Activo,
            version: 1,
            creado_por: user.id.clone(),
            fecha_creacion: ahora,
            fecha_vencimiento: factura.fecha_vencimiento,
            fecha_pago_total: None,
            pagos: Vec::new(),
            participaciones,
        };
        let saved = match repo.save(doc).await {
            Ok(saved) => saved,
            Err(CreditoError::Conflict) => {
                let existing = repo.credito(&id).await?;
                if existing.oferta_id != oferta.id {
                    return Err(CreditoError::Conflict);
                }
                existing
            }
            Err(error) => return Err(error),
        };
        Ok(self.resultado(user, saved).await)
    }

    pub async fn get(&self, user: &Usuario, id: &str) -> Result<CreditoVista, CreditoError> {
        validar_id(id)?;
        let doc = self.repo()?.credito(id).await?;
        require_view(user, &doc)?;
        Ok(vista(user, doc, Utc::now().date_naive()))
    }

    pub async fn list(
        &self,
        user: &Usuario,
        query: ListQuery,
    ) -> Result<CreditoPagina, CreditoError> {
        if query.bookmark.as_ref().is_some_and(|b| b.len() > 8192) {
            return Err(CreditoError::Invalid("bookmark demasiado largo"));
        }
        let limit = query.limit.unwrap_or(20).clamp(1, 100);
        let mut selector = json!({"tipo":"credito"});
        match user.rol {
            Rol::Pyme => selector["responsable_id"] = json!(user.id),
            Rol::Inversionista => {
                selector["inversionistas_ids"] = json!({"$elemMatch":{"$eq":user.id}})
            }
            Rol::Administrador => {}
        }
        if let Some(estado) = query.estado {
            selector["estado"] = json!(estado);
        }
        let (docs, bookmark) = self
            .repo()?
            .find::<CreditoDocumento>("operaciones", selector, limit, query.bookmark)
            .await?;
        let creditos = docs
            .into_iter()
            .filter(|d| d.tipo == "credito" && require_view(user, d).is_ok())
            .map(|d| vista(user, d, Utc::now().date_naive()))
            .collect();
        Ok(CreditoPagina {
            creditos,
            bookmark,
            limit,
        })
    }

    pub async fn pagar(
        &self,
        user: &Usuario,
        id: &str,
        input: RegistrarPago,
    ) -> Result<CreditoResultado, CreditoError> {
        validar_id(id)?;
        if input.monto_centavos <= 0 {
            return Err(CreditoError::Invalid("El pago debe ser mayor que cero"));
        }
        if input.referencia.is_empty()
            || input.referencia.len() > 100
            || !input
                .referencia
                .bytes()
                .all(|c| c.is_ascii_alphanumeric() || c == b'-' || c == b'_')
        {
            return Err(CreditoError::Invalid("La referencia debe contener entre 1 y 100 letras, números, guiones o guiones bajos"));
        }
        let repo = self.repo()?;
        let mut doc = repo.credito(id).await?;
        if user.rol != Rol::Administrador
            && !(user.rol == Rol::Pyme && doc.responsable_id == user.id)
        {
            return Err(CreditoError::Forbidden);
        }
        if let Some(existing) = doc.pagos.iter().find(|p| p.referencia == input.referencia) {
            if existing.monto_centavos != input.monto_centavos || existing.registrado_por != user.id
            {
                return Err(CreditoError::Conflict);
            }
            return Ok(self.resultado(user, doc).await);
        }
        if doc.estado != EstadoCredito::Activo {
            return Err(CreditoError::Conflict);
        }
        if doc.pagos.len() >= 1000 {
            return Err(CreditoError::Invalid(
                "Se alcanzó el límite de 1000 pagos del crédito",
            ));
        }
        let nuevo = doc
            .pagado_centavos
            .checked_add(input.monto_centavos)
            .ok_or(CreditoError::Invalid("Monto de pago fuera de rango"))?;
        if nuevo > doc.total_centavos {
            return Err(CreditoError::Invalid("El pago supera el saldo pendiente"));
        }
        let ahora = Utc::now();
        doc.pagos.push(Pago {
            id: stable_id("pago", &format!("{}:{}", doc.id, input.referencia)),
            referencia: input.referencia,
            monto_centavos: input.monto_centavos,
            registrado_por: user.id.clone(),
            fecha: ahora,
        });
        doc.pagado_centavos = nuevo;
        doc.version = doc.version.checked_add(1).ok_or(CreditoError::Upstream)?;
        if nuevo == doc.total_centavos {
            doc.estado = EstadoCredito::Pagado;
            doc.fecha_pago_total = Some(ahora);
        }
        let saved = repo.save(doc).await?;
        Ok(self.resultado(user, saved).await)
    }

    pub async fn confirmar_aporte(
        &self,
        user: &Usuario,
        id: &str,
    ) -> Result<AporteResultado, CreditoError> {
        validar_id(id)?;
        let repo = self.repo()?;
        let mut doc: Value = repo.get("operaciones", id).await?;
        if doc["tipo"] != "inversion" || doc["_id"] != id {
            return Err(CreditoError::NotFound);
        }
        let inversion: Inversion =
            serde_json::from_value(doc.clone()).map_err(|_| CreditoError::Upstream)?;
        if user.rol != Rol::Administrador
            && !(user.rol == Rol::Inversionista && inversion.inversionista_id == user.id)
        {
            return Err(CreditoError::Forbidden);
        }
        if inversion.moneda != "USD" {
            return Err(CreditoError::Conflict);
        }
        centavos(inversion.monto)?;
        let previously_confirmed = matches!(
            inversion.estado,
            EstadoInversion::Confirmada | EstadoInversion::Liquidada
        );
        if !previously_confirmed
            && !matches!(
                inversion.estado,
                EstadoInversion::PagoPendiente | EstadoInversion::Registrada
            )
        {
            return Err(CreditoError::Conflict);
        }
        if !previously_confirmed || doc.get("fecha_confirmacion_pago").is_none() {
            if !previously_confirmed {
                validar_id(&inversion.oferta_id)?;
                let oferta: Oferta = repo.get("ofertas", &inversion.oferta_id).await?;
                if oferta.tipo != "oferta"
                    || oferta.id != inversion.oferta_id
                    || oferta.factura_id != inversion.factura_id
                    || !matches!(
                        oferta.estado,
                        EstadoOferta::Abierta | EstadoOferta::ObjetivoAlcanzado
                    )
                {
                    return Err(CreditoError::Conflict);
                }
                doc["estado"] = json!("confirmada");
            }
            doc["fecha_confirmacion_pago"] = json!(Utc::now());
            doc["confirmado_por"] = json!(user.id);
            doc["pago_simulado"] = json!(true);
            repo.put("operaciones", id, &doc).await?;
        }
        let event = json!({"_id":stable_id("auditoria-aporte", id), "tipo":"evento", "actor_id":doc["confirmado_por"],
            "accion":"aporte_confirmado", "recurso_tipo":"inversion", "recurso_id":id, "fecha":doc["fecha_confirmacion_pago"],
            "detalles":{"oferta_id":inversion.oferta_id,"factura_id":inversion.factura_id,"monto_centavos":centavos(inversion.monto)?,"moneda":"USD"}});
        let pending = repo.audit(event).await.is_err();
        Ok(AporteResultado {
            inversion_id: id.into(),
            estado: if inversion.estado == EstadoInversion::Liquidada {
                "liquidada"
            } else {
                "confirmada"
            },
            simulado: true,
            sincronizacion_pendiente: pending,
        })
    }

    pub async fn sincronizar(
        &self,
        user: &Usuario,
        id: &str,
    ) -> Result<CreditoResultado, CreditoError> {
        require_admin(user)?;
        validar_id(id)?;
        let doc = self.repo()?.credito(id).await?;
        Ok(self.resultado(user, doc).await)
    }

    async fn resultado(&self, user: &Usuario, doc: CreditoDocumento) -> CreditoResultado {
        let pending = self.sincronizar_documento(&doc).await.is_err();
        if pending {
            tracing::warn!(credito_id = %doc.id, version = doc.version, "Crédito guardado; sincronización pendiente");
        }
        CreditoResultado {
            credito: vista(user, doc, Utc::now().date_naive()),
            sincronizacion_pendiente: pending,
        }
    }

    async fn sincronizar_documento(&self, doc: &CreditoDocumento) -> Result<(), CreditoError> {
        let repo = self.repo()?;
        let pagado = doc.estado == EstadoCredito::Pagado;
        repo.project(
            "ofertas",
            &doc.oferta_id,
            "oferta",
            doc,
            json!({"estado":"financiada"}),
        )
        .await?;
        repo.project("facturas", &doc.factura_id, "factura", doc, json!({
            "estado": if pagado { "pagada" } else { "financiada" }, "monto_financiado_centavos":doc.capital_centavos,
            "fecha_actualizacion":doc.fecha_pago_total.unwrap_or(doc.fecha_creacion)
        })).await?;
        for participacion in &doc.participaciones {
            let mut changes = json!({"estado":if pagado { "liquidada" } else { "confirmada" }});
            if pagado {
                changes["fecha_liquidacion"] = json!(doc.fecha_pago_total);
                changes["rendimiento_real"] = json!(participacion.interes_centavos as f64 / 100.0);
            }
            repo.project(
                "operaciones",
                &participacion.inversion_id,
                "inversion",
                doc,
                changes,
            )
            .await?;
        }
        repo.audit(json!({"_id":stable_id("auditoria-credito", &doc.id), "tipo":"evento", "actor_id":doc.creado_por,
            "accion":"credito_creado", "recurso_tipo":"credito", "recurso_id":doc.id, "fecha":doc.fecha_creacion,
            "detalles":{"oferta_id":doc.oferta_id,"factura_id":doc.factura_id,"empresa_id":doc.empresa_id,"monto_centavos":doc.capital_centavos,"moneda":doc.moneda}
        })).await?;
        for pago in &doc.pagos {
            repo.audit(json!({"_id":stable_id("auditoria-pago", &pago.id), "tipo":"evento", "actor_id":pago.registrado_por,
                "accion":"pago_registrado", "recurso_tipo":"credito", "recurso_id":doc.id,"fecha":pago.fecha,
                "detalles":{"credito_id":doc.id,"pago_id":pago.id,"monto_centavos":pago.monto_centavos,"moneda":doc.moneda}
            })).await?;
        }
        Ok(())
    }
}

fn require_admin(user: &Usuario) -> Result<(), CreditoError> {
    if user.rol == Rol::Administrador {
        Ok(())
    } else {
        Err(CreditoError::Forbidden)
    }
}
fn require_view(user: &Usuario, doc: &CreditoDocumento) -> Result<(), CreditoError> {
    if user.rol == Rol::Administrador
        || (user.rol == Rol::Pyme && user.id == doc.responsable_id)
        || (user.rol == Rol::Inversionista && doc.inversionistas_ids.contains(&user.id))
    {
        Ok(())
    } else {
        Err(CreditoError::Forbidden)
    }
}
fn validar_id(id: &str) -> Result<(), CreditoError> {
    if id.is_empty()
        || id.len() > 512
        || id.starts_with('_')
        || id == "."
        || id == ".."
        || id.contains(['/', '\\'])
        || id.trim() != id
        || id.chars().any(char::is_control)
    {
        Err(CreditoError::Invalid("Identificador inválido"))
    } else {
        Ok(())
    }
}
pub(super) fn stable_id(prefix: &str, source: &str) -> String {
    format!("{prefix}-{:x}", Sha256::digest(source.as_bytes()))
}

// Adaptación en el límite con el módulo anterior, que almacena dólares como f64.
pub(super) fn centavos(monto: f64) -> Result<i64, CreditoError> {
    let value = monto * 100.0;
    if !value.is_finite()
        || !(1.0..=9_000_000_000_000.0).contains(&value)
        || (value.round() - value).abs() > 0.001
    {
        return Err(CreditoError::Invalid("El importe debe ser positivo, estar dentro del rango admitido y tener como máximo dos decimales"));
    }
    Ok(value.round() as i64)
}

pub(super) fn calcular_interes(capital: i64, tasa_bp: i64, dias: i64) -> Result<i64, CreditoError> {
    if capital <= 0 || !(0..=10000).contains(&tasa_bp) || dias <= 0 {
        return Err(CreditoError::Invalid("Capital, tasa o plazo inválido"));
    }
    let divisor = 10000_i128 * 365;
    let numerator = i128::from(capital)
        .checked_mul(i128::from(tasa_bp))
        .and_then(|n| n.checked_mul(i128::from(dias)))
        .ok_or(CreditoError::Upstream)?;
    i64::try_from((numerator + divisor / 2) / divisor).map_err(|_| CreditoError::Upstream)
}

fn distribuir_interes(participaciones: &mut [Participacion], capital: i64, interes: i64) {
    let mut remainders = Vec::new();
    let mut allocated = 0;
    for (index, item) in participaciones.iter_mut().enumerate() {
        let value = i128::from(item.capital_centavos) * i128::from(interes);
        item.interes_centavos = (value / i128::from(capital)) as i64;
        allocated += item.interes_centavos;
        remainders.push((index, value % i128::from(capital)));
    }
    remainders.sort_by(|a, b| b.1.cmp(&a.1).then_with(|| a.0.cmp(&b.0)));
    for (index, _) in remainders.into_iter().take((interes - allocated) as usize) {
        participaciones[index].interes_centavos += 1;
    }
}

pub(super) fn vista(user: &Usuario, doc: CreditoDocumento, hoy: NaiveDate) -> CreditoVista {
    let dias_mora = if doc.estado == EstadoCredito::Activo {
        hoy.signed_duration_since(doc.fecha_vencimiento)
            .num_days()
            .max(0)
    } else {
        0
    };
    let investor = user.rol == Rol::Inversionista;
    CreditoVista {
        id: doc.id,
        oferta_id: doc.oferta_id,
        factura_id: doc.factura_id,
        empresa_id: doc.empresa_id,
        moneda: doc.moneda,
        capital_centavos: doc.capital_centavos,
        interes_centavos: doc.interes_centavos,
        total_centavos: doc.total_centavos,
        pagado_centavos: doc.pagado_centavos,
        saldo_centavos: doc.total_centavos - doc.pagado_centavos,
        tasa_anual_bp: doc.tasa_anual_bp,
        estado: doc.estado,
        vencido: dias_mora > 0,
        dias_mora,
        version: doc.version,
        fecha_creacion: doc.fecha_creacion,
        fecha_vencimiento: doc.fecha_vencimiento,
        fecha_pago_total: doc.fecha_pago_total,
        pagos: if investor { None } else { Some(doc.pagos) },
        participaciones: doc
            .participaciones
            .into_iter()
            .filter(|p| !investor || p.inversionista_id == user.id)
            .collect(),
    }
}
