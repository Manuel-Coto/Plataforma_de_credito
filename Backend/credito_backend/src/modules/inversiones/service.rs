use std::collections::BTreeMap;

use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use sha2::{Digest, Sha256};

use crate::modules::usuarios::model::{EstadoUsuario, Rol, Usuario};

use super::{
    model::{
        CrearInversion, CrearOferta, EstadoInversion, EstadoOferta, Inversion, InversionPagina,
        ListarOfertas, Oferta, OfertaPagina, RecuperacionPagina, RecuperarInversiones,
    },
    repository::InversionRepository,
    InversionError,
};

#[derive(Clone)]
pub struct InversionService {
    repository: Option<InversionRepository>,
}

/// Claims a user's key before touching an offer. It is not an investment and
/// therefore cannot be listed, confirmed, or counted as funded by Credits.
#[derive(Serialize, Deserialize)]
struct SolicitudInversion {
    #[serde(rename = "_id")]
    id: String,
    tipo: String,
    inversionista_id: String,
    oferta_id: String,
    monto_centavos: i64,
    fecha_creacion: DateTime<Utc>,
}

/// Source of truth for a committed reservation. The snapshot and collected
/// amount are written atomically in one offer revision; its investment document
/// is a recoverable projection. This ledger is never part of Oferta's public DTO.
#[derive(Clone, Serialize, Deserialize)]
struct ReservaInversion {
    monto_centavos: i64,
    inversion: Inversion,
}

const RESERVAS: &str = "reservas_inversiones";
const MAX_REINTENTOS: usize = 8;

impl InversionService {
    pub fn new(repository: Option<InversionRepository>) -> Self {
        Self { repository }
    }

    fn repo(&self) -> Result<&InversionRepository, InversionError> {
        self.repository.as_ref().ok_or(InversionError::Unavailable)
    }

    fn require_role(user: &Usuario, allowed: &[Rol]) -> Result<(), InversionError> {
        if user.estado == EstadoUsuario::Activo && allowed.contains(&user.rol) {
            Ok(())
        } else {
            Err(InversionError::Forbidden)
        }
    }

    pub async fn crear_oferta(
        &self,
        user: &Usuario,
        input: CrearOferta,
    ) -> Result<Oferta, InversionError> {
        Self::require_role(user, &[Rol::Pyme, Rol::Administrador])?;

        validar_id(&input.factura_id)?;
        let objetivo = centavos(input.monto_objetivo, false)?;

        if !input.tasa_rendimiento_anual.is_finite()
            || !(0.0..=100.0).contains(&input.tasa_rendimiento_anual)
        {
            return Err(InversionError::Invalid(
                "La tasa anual debe estar entre 0 y 100",
            ));
        }

        let repo = self.repo()?;
        let id = format!("oferta-{:x}", Sha256::digest(input.factura_id.as_bytes()));
        match repo.oferta_document(&id).await {
            Ok(document) => return Self::repetir_oferta(user, &input, document),
            Err(InversionError::NotFound) => (),
            Err(error) => return Err(error),
        }
        // Older versions used timestamp IDs. Never publish a second offer for
        // an invoice that already has such a legacy offer.
        let anteriores = repo.ofertas_por_factura(&input.factura_id).await?;
        if anteriores.len() > 1 {
            return Err(InversionError::Conflict);
        }
        if let Some(anterior) = anteriores.into_iter().next() {
            return Self::repetir_oferta(
                user,
                &input,
                serde_json::to_value(anterior).map_err(|_| InversionError::Upstream)?,
            );
        }
        let ahora = Utc::now();

        if input.fecha_cierre <= ahora {
            return Err(InversionError::Invalid(
                "La fecha de cierre debe estar en el futuro",
            ));
        }

        let factura = repo.get_factura(input.factura_id.trim()).await?;

        let estado = factura["estado"].as_str().unwrap_or("");

        if estado != "disponible" {
            return Err(InversionError::Conflict);
        }

        let creador_factura = factura["creado_por"].as_str().unwrap_or("");

        if user.rol != Rol::Administrador && creador_factura != user.id {
            return Err(InversionError::Forbidden);
        }
        if factura["moneda"] != "USD" {
            return Err(InversionError::Invalid(
                "Solo se pueden publicar facturas en USD",
            ));
        }
        if factura["dte"]["verificado"] != true {
            return Err(InversionError::Invalid(
                "La factura debe tener un DTE verificado",
            ));
        }

        let empresa_id = factura["empresa_id"]
            .as_str()
            .ok_or(InversionError::Upstream)?
            .to_string();

        let monto_factura_centavos = factura["monto_total_centavos"]
            .as_i64()
            .ok_or(InversionError::Upstream)?;

        if objetivo > monto_factura_centavos {
            return Err(InversionError::Invalid(
                "El objetivo no puede superar el monto total de la factura",
            ));
        }

        let oferta = Oferta {
            id: id.clone(),
            revision: None,
            tipo: "oferta".to_string(),
            factura_id: input.factura_id.trim().to_string(),
            empresa_id,
            monto_objetivo: objetivo as f64 / 100.0,
            monto_recaudado: 0.0,
            moneda: "USD".to_string(),
            tasa_rendimiento_anual: input.tasa_rendimiento_anual,
            estado: EstadoOferta::Abierta,
            fecha_apertura: ahora,
            fecha_cierre: input.fecha_cierre,
            creado_por: user.id.clone(),
        };

        match repo.save_oferta(oferta).await {
            Ok(oferta) => Ok(oferta),
            Err(error) => match repo.oferta_document(&id).await {
                Ok(document) => Self::repetir_oferta(user, &input, document),
                Err(InversionError::NotFound) => Err(error),
                Err(error) => Err(error),
            },
        }
    }

    fn repetir_oferta(
        user: &Usuario,
        input: &CrearOferta,
        document: Value,
    ) -> Result<Oferta, InversionError> {
        let oferta: Oferta =
            serde_json::from_value(document).map_err(|_| InversionError::Upstream)?;
        if oferta.tipo != "oferta"
            || oferta.factura_id != input.factura_id
            || oferta.creado_por != user.id
            || oferta.monto_objetivo != input.monto_objetivo
            || oferta.tasa_rendimiento_anual != input.tasa_rendimiento_anual
            || oferta.fecha_cierre != input.fecha_cierre
        {
            return Err(InversionError::Conflict);
        }
        Ok(oferta)
    }

    pub async fn listar_ofertas(
        &self,
        _user: &Usuario,
        query: ListarOfertas,
    ) -> Result<OfertaPagina, InversionError> {
        let limit = query.limit.unwrap_or(20).clamp(1, 100);

        let (ofertas, bookmark) = self
            .repo()?
            .listar_ofertas(limit, query.bookmark, query.estado)
            .await?;

        Ok(OfertaPagina {
            ofertas,
            bookmark,
            limit,
        })
    }

    pub async fn invertir(
        &self,
        user: &Usuario,
        input: CrearInversion,
        key: &str,
    ) -> Result<Inversion, InversionError> {
        Self::require_role(user, &[Rol::Inversionista])?;
        validar_id(&input.oferta_id)?;
        validar_id(&user.id)?;
        if key.is_empty() || key.len() > 128 || !key.bytes().all(|byte| byte.is_ascii_graphic()) {
            return Err(InversionError::Invalid(
                "Idempotency-Key debe contener de 1 a 128 caracteres ASCII sin espacios",
            ));
        }
        let monto = centavos(input.monto, false)?;
        let repo = self.repo()?;
        let hash = format!(
            "{:x}",
            Sha256::digest(serde_json::to_vec(&(&user.id, key)).unwrap())
        );
        let solicitud = Self::solicitud(repo, user, &input.oferta_id, monto, &hash).await?;
        let inversion_id = format!("inversion-{hash}");
        // A previously projected investment is immutable to this workflow. In
        // particular, replay must never revert confirmation/liquidation fields.
        if let Some(inversion) = Self::existente(repo, &inversion_id, &solicitud).await? {
            return Ok(inversion);
        }
        let reserva = Self::reservar(repo, &solicitud, &inversion_id).await?;
        Self::materializar(repo, &solicitud, reserva).await
    }

    async fn materializar(
        repo: &InversionRepository,
        solicitud: &SolicitudInversion,
        reserva: ReservaInversion,
    ) -> Result<Inversion, InversionError> {
        let inversion_id = reserva.inversion.id.clone();
        let mut projection = reserva.inversion;
        // Always create-only: a concurrent confirmation can never be replaced
        // by an older reservation snapshot, even if its stored revision is stale.
        projection.revision = None;
        match repo.save_inversion(projection).await {
            Ok(inversion) => Ok(inversion),
            Err(error) => match Self::existente(repo, &inversion_id, solicitud).await? {
                Some(inversion) => Ok(inversion),
                None => Err(error),
            },
        }
    }

    /// Explicit recovery after a client loses its key. Only materializes
    /// reservations already committed to an offer; never allocates new funds.
    pub async fn recuperar(
        &self,
        user: &Usuario,
        query: RecuperarInversiones,
    ) -> Result<RecuperacionPagina, InversionError> {
        Self::require_role(user, &[Rol::Inversionista, Rol::Administrador])?;
        let limit = query.limit.unwrap_or(25);
        if !(1..=100).contains(&limit)
            || query
                .bookmark
                .as_ref()
                .is_some_and(|bookmark| bookmark.len() > 8192)
        {
            return Err(InversionError::Invalid(
                "Límite o marcador de recuperación inválido",
            ));
        }
        let repo = self.repo()?;
        let (documents, bookmark) = repo
            .listar_solicitudes(&user.id, limit, query.bookmark)
            .await?;
        let mut result = RecuperacionPagina {
            recuperadas: 0,
            pendientes: 0,
            omitidas: 0,
            bookmark,
        };
        for document in documents {
            let solicitud: SolicitudInversion =
                serde_json::from_value(document).map_err(|_| InversionError::Upstream)?;
            let hash = solicitud
                .id
                .strip_prefix("solicitud-inversion-")
                .filter(|hash| {
                    hash.len() == 64 && hash.bytes().all(|byte| byte.is_ascii_hexdigit())
                })
                .ok_or(InversionError::Upstream)?;
            if solicitud.tipo != "solicitud_inversion"
                || solicitud.inversionista_id != user.id
                || solicitud.monto_centavos <= 0
                || solicitud.monto_centavos > 9_000_000_000_000
            {
                return Err(InversionError::Upstream);
            }
            let id = format!("inversion-{hash}");
            match Self::recuperar_solicitud(repo, &solicitud, &id).await {
                Ok(true) => result.recuperadas += 1,
                Ok(false) => result.omitidas += 1,
                Err(_) => result.pendientes += 1,
            }
        }
        Ok(result)
    }

    async fn recuperar_solicitud(
        repo: &InversionRepository,
        solicitud: &SolicitudInversion,
        id: &str,
    ) -> Result<bool, InversionError> {
        if Self::existente(repo, id, solicitud).await?.is_some() {
            return Ok(false);
        }
        let document = repo.oferta_document(&solicitud.oferta_id).await?;
        if document["_id"] != solicitud.oferta_id || document["tipo"] != "oferta" {
            return Err(InversionError::Upstream);
        }
        let Some(reserva) = Self::reserva_existente(&document, solicitud, id)? else {
            return Ok(false);
        };
        Self::materializar(repo, solicitud, reserva).await?;
        Ok(true)
    }

    async fn solicitud(
        repo: &InversionRepository,
        user: &Usuario,
        oferta_id: &str,
        monto: i64,
        hash: &str,
    ) -> Result<SolicitudInversion, InversionError> {
        let id = format!("solicitud-inversion-{hash}");
        let saved = match repo.operacion_document(&id).await {
            Ok(document) => document,
            Err(InversionError::NotFound) => {
                let solicitud = SolicitudInversion {
                    id: id.clone(),
                    tipo: "solicitud_inversion".into(),
                    inversionista_id: user.id.clone(),
                    oferta_id: oferta_id.into(),
                    monto_centavos: monto,
                    fecha_creacion: Utc::now(),
                };
                let document =
                    serde_json::to_value(&solicitud).map_err(|_| InversionError::Upstream)?;
                match repo.save_operacion_document(&id, &document).await {
                    Ok(()) => return Ok(solicitud),
                    Err(error) => match repo.operacion_document(&id).await {
                        Ok(document) => document,
                        Err(InversionError::NotFound) => return Err(error),
                        Err(error) => return Err(error),
                    },
                }
            }
            Err(error) => return Err(error),
        };
        let solicitud: SolicitudInversion =
            serde_json::from_value(saved).map_err(|_| InversionError::Upstream)?;
        if solicitud.id != id || solicitud.tipo != "solicitud_inversion" {
            return Err(InversionError::Upstream);
        }
        if solicitud.inversionista_id != user.id
            || solicitud.oferta_id != oferta_id
            || solicitud.monto_centavos != monto
        {
            return Err(InversionError::Conflict);
        }
        Ok(solicitud)
    }

    async fn existente(
        repo: &InversionRepository,
        id: &str,
        solicitud: &SolicitudInversion,
    ) -> Result<Option<Inversion>, InversionError> {
        let document = match repo.operacion_document(id).await {
            Ok(document) => document,
            Err(InversionError::NotFound) => return Ok(None),
            Err(error) => return Err(error),
        };
        let inversion: Inversion =
            serde_json::from_value(document).map_err(|_| InversionError::Upstream)?;
        if inversion.id != id
            || inversion.tipo != "inversion"
            || inversion.inversionista_id != solicitud.inversionista_id
            || inversion.oferta_id != solicitud.oferta_id
            || inversion.fecha_creacion != solicitud.fecha_creacion
            || centavos(inversion.monto, false).map_err(|_| InversionError::Upstream)?
                != solicitud.monto_centavos
        {
            return Err(InversionError::Upstream);
        }
        Ok(Some(inversion))
    }

    fn reserva_existente(
        document: &Value,
        solicitud: &SolicitudInversion,
        id: &str,
    ) -> Result<Option<ReservaInversion>, InversionError> {
        let reservas: BTreeMap<String, ReservaInversion> = match document.get(RESERVAS) {
            None => return Ok(None),
            Some(value) => {
                serde_json::from_value(value.clone()).map_err(|_| InversionError::Upstream)?
            }
        };
        let Some(reserva) = reservas.get(id) else {
            return Ok(None);
        };
        if reserva.monto_centavos != solicitud.monto_centavos
            || reserva.inversion.id != id
            || reserva.inversion.tipo != "inversion"
            || reserva.inversion.oferta_id != solicitud.oferta_id
            || reserva.inversion.inversionista_id != solicitud.inversionista_id
            || reserva.inversion.fecha_creacion != solicitud.fecha_creacion
            || centavos(reserva.inversion.monto, false).map_err(|_| InversionError::Upstream)?
                != solicitud.monto_centavos
        {
            return Err(InversionError::Upstream);
        }
        Ok(Some(reserva.clone()))
    }

    async fn reservar(
        repo: &InversionRepository,
        solicitud: &SolicitudInversion,
        id: &str,
    ) -> Result<ReservaInversion, InversionError> {
        for _ in 0..MAX_REINTENTOS {
            let mut document = repo.oferta_document(&solicitud.oferta_id).await?;
            let oferta: Oferta =
                serde_json::from_value(document.clone()).map_err(|_| InversionError::Upstream)?;
            if oferta.id != solicitud.oferta_id || oferta.tipo != "oferta" {
                return Err(InversionError::NotFound);
            }
            if let Some(reserva) = Self::reserva_existente(&document, solicitud, id)? {
                return Ok(reserva);
            }
            if oferta.estado != EstadoOferta::Abierta || oferta.fecha_cierre <= Utc::now() {
                return Err(InversionError::Conflict);
            }
            if oferta.creado_por == solicitud.inversionista_id {
                return Err(InversionError::Forbidden);
            }
            if oferta.moneda != "USD" {
                return Err(InversionError::Conflict);
            }
            let objetivo =
                centavos(oferta.monto_objetivo, false).map_err(|_| InversionError::Upstream)?;
            let recaudado =
                centavos(oferta.monto_recaudado, true).map_err(|_| InversionError::Upstream)?;
            let total = recaudado
                .checked_add(solicitud.monto_centavos)
                .ok_or(InversionError::Upstream)?;
            if total > objetivo {
                return Err(InversionError::Invalid(
                    "La inversión supera el saldo disponible de la oferta",
                ));
            }
            let reserva = ReservaInversion {
                monto_centavos: solicitud.monto_centavos,
                inversion: Inversion {
                    id: id.into(),
                    revision: None,
                    tipo: "inversion".into(),
                    oferta_id: oferta.id,
                    factura_id: oferta.factura_id,
                    inversionista_id: solicitud.inversionista_id.clone(),
                    monto: solicitud.monto_centavos as f64 / 100.0,
                    moneda: oferta.moneda,
                    estado: EstadoInversion::PagoPendiente,
                    fecha_creacion: solicitud.fecha_creacion,
                    fecha_liquidacion: None,
                    rendimiento_real: None,
                },
            };
            if document.get(RESERVAS).is_none() {
                document[RESERVAS] = json!({});
            }
            let reservas = document[RESERVAS]
                .as_object_mut()
                .ok_or(InversionError::Upstream)?;
            if reservas.len() >= 5000 {
                return Err(InversionError::Conflict);
            }
            reservas.insert(
                id.into(),
                serde_json::to_value(&reserva).map_err(|_| InversionError::Upstream)?,
            );
            document["monto_recaudado"] = json!(total as f64 / 100.0);
            if total == objetivo {
                document["estado"] = json!("objetivo_alcanzado");
            }
            match repo
                .save_oferta_document(&solicitud.oferta_id, &document)
                .await
            {
                Ok(()) => return Ok(reserva),
                Err(InversionError::Conflict) => continue,
                Err(error) => {
                    // A transport failure may have happened after CouchDB
                    // committed. Read the ledger before reporting a retry.
                    let stored = repo.oferta_document(&solicitud.oferta_id).await?;
                    if let Some(reserva) = Self::reserva_existente(&stored, solicitud, id)? {
                        return Ok(reserva);
                    }
                    return Err(error);
                }
            }
        }
        Err(InversionError::Conflict)
    }

    pub async fn listar_mis_inversiones(
        &self,
        user: &Usuario,
        limit: Option<u32>,
        bookmark: Option<String>,
    ) -> Result<InversionPagina, InversionError> {
        Self::require_role(user, &[Rol::Inversionista, Rol::Administrador])?;

        let limit = limit.unwrap_or(20).clamp(1, 100);

        let owner = if user.rol == Rol::Administrador {
            None
        } else {
            Some(user.id.as_str())
        };

        let (inversiones, bookmark) = self
            .repo()?
            .listar_inversiones(limit, bookmark, owner)
            .await?;

        Ok(InversionPagina {
            inversiones,
            bookmark,
            limit,
        })
    }
}

fn validar_id(id: &str) -> Result<(), InversionError> {
    if id.is_empty()
        || id.len() > 512
        || id.starts_with('_')
        || matches!(id, "." | "..")
        || id.contains(['/', '\\'])
        || id.trim() != id
        || id.chars().any(char::is_control)
    {
        return Err(InversionError::Invalid("Identificador inválido"));
    }
    Ok(())
}

/// f64 remains the legacy wire format; accounting uses canonical integer
/// cents. Comparing its round trip rejects subcent fractions instead of rounding.
pub(super) fn centavos(amount: f64, allow_zero: bool) -> Result<i64, InversionError> {
    let scaled = amount * 100.0;
    let minimum = if allow_zero { 0.0 } else { 1.0 };
    if !scaled.is_finite() || !(minimum..=9_000_000_000_000.0).contains(&scaled.round()) {
        return Err(InversionError::Invalid(
            "El monto debe ser positivo y tener como máximo dos decimales",
        ));
    }
    let cents = scaled.round() as i64;
    if cents as f64 / 100.0 != amount {
        return Err(InversionError::Invalid(
            "El monto debe ser positivo y tener como máximo dos decimales",
        ));
    }
    Ok(cents)
}
