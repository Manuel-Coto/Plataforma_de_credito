use chrono::Utc;

use crate::modules::usuarios::model::{Rol, Usuario};

use super::{
    model::{
        CrearInversion, CrearOferta, EstadoInversion, EstadoOferta,
        Inversion, InversionPagina, ListarOfertas, Oferta, OfertaPagina,
    },
    repository::InversionRepository,
    InversionError,
};

#[derive(Clone)]
pub struct InversionService {
    repository: Option<InversionRepository>,
}

impl InversionService {
    pub fn new(repository: Option<InversionRepository>) -> Self {
        Self { repository }
    }

    fn repo(&self) -> Result<&InversionRepository, InversionError> {
        self.repository
            .as_ref()
            .ok_or(InversionError::Unavailable)
    }

    fn require_role(
        user: &Usuario,
        allowed: &[Rol],
    ) -> Result<(), InversionError> {
        if allowed.contains(&user.rol) {
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

        if input.factura_id.trim().is_empty() {
            return Err(InversionError::Invalid(
                "La factura es obligatoria",
            ));
        }

        if !input.monto_objetivo.is_finite()
            || input.monto_objetivo <= 0.0
        {
            return Err(InversionError::Invalid(
                "El monto objetivo debe ser mayor que cero",
            ));
        }

        if !input.tasa_rendimiento_anual.is_finite()
            || !(0.0..=100.0).contains(&input.tasa_rendimiento_anual)
        {
            return Err(InversionError::Invalid(
                "La tasa anual debe estar entre 0 y 100",
            ));
        }

        let ahora = Utc::now();

        if input.fecha_cierre <= ahora {
            return Err(InversionError::Invalid(
                "La fecha de cierre debe estar en el futuro",
            ));
        }

        let repo = self.repo()?;
        let factura = repo.get_factura(input.factura_id.trim()).await?;

        let estado = factura["estado"].as_str().unwrap_or("");

        if estado != "disponible" {
            return Err(InversionError::Conflict);
        }

        let creador_factura = factura["creado_por"].as_str().unwrap_or("");

        if user.rol != Rol::Administrador
            && creador_factura != user.id
        {
            return Err(InversionError::Forbidden);
        }

        let empresa_id = factura["empresa_id"]
            .as_str()
            .ok_or(InversionError::Upstream)?
            .to_string();

        let monto_factura_centavos = factura["monto_total_centavos"]
            .as_i64()
            .ok_or(InversionError::Upstream)?;

        let monto_factura = monto_factura_centavos as f64 / 100.0;

        if input.monto_objetivo > monto_factura {
            return Err(InversionError::Invalid(
                "El objetivo no puede superar el monto total de la factura",
            ));
        }

        let oferta = Oferta {
            id: format!(
                "oferta-{}",
                ahora.timestamp_nanos_opt().unwrap_or_default()
            ),
            revision: None,
            tipo: "oferta".to_string(),
            factura_id: input.factura_id.trim().to_string(),
            empresa_id,
            monto_objetivo: redondear_dos(input.monto_objetivo),
            monto_recaudado: 0.0,
            moneda: "USD".to_string(),
            tasa_rendimiento_anual: input.tasa_rendimiento_anual,
            estado: EstadoOferta::Abierta,
            fecha_apertura: ahora,
            fecha_cierre: input.fecha_cierre,
            creado_por: user.id.clone(),
        };

        repo.save_oferta(oferta).await
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
    ) -> Result<Inversion, InversionError> {
        Self::require_role(user, &[Rol::Inversionista])?;

        if input.oferta_id.trim().is_empty() {
            return Err(InversionError::Invalid(
                "La oferta es obligatoria",
            ));
        }

        if !input.monto.is_finite() || input.monto <= 0.0 {
            return Err(InversionError::Invalid(
                "El monto de inversión debe ser mayor que cero",
            ));
        }

        let monto = redondear_dos(input.monto);
        let ahora = Utc::now();
        let repo = self.repo()?;

        let mut oferta = repo.get_oferta(input.oferta_id.trim()).await?;

        if oferta.estado != EstadoOferta::Abierta
            || oferta.fecha_cierre <= ahora
        {
            return Err(InversionError::Conflict);
        }

        let nuevo_total = redondear_dos(oferta.monto_recaudado + monto);

        if nuevo_total > oferta.monto_objetivo {
            return Err(InversionError::Invalid(
                "La inversión supera el saldo disponible de la oferta",
            ));
        }

        // Actualizar la oferta con su _rev permite que CouchDB detecte
        // escrituras concurrentes y rechace revisiones obsoletas.
        oferta.monto_recaudado = nuevo_total;

        if nuevo_total >= oferta.monto_objetivo {
            oferta.estado = EstadoOferta::ObjetivoAlcanzado;
        }

        let oferta_id = oferta.id.clone();
        let factura_id = oferta.factura_id.clone();

        repo.save_oferta(oferta).await?;

        let inversion = Inversion {
            id: format!(
                "inversion-{}",
                ahora.timestamp_nanos_opt().unwrap_or_default()
            ),
            revision: None,
            tipo: "inversion".to_string(),
            oferta_id,
            factura_id,
            inversionista_id: user.id.clone(),
            monto,
            moneda: "USD".to_string(),
            estado: EstadoInversion::PagoPendiente,
            fecha_creacion: ahora,
            fecha_liquidacion: None,
            rendimiento_real: None,
        };

        repo.save_inversion(&inversion).await?;

        Ok(inversion)
    }

    pub async fn listar_mis_inversiones(
        &self,
        user: &Usuario,
        limit: Option<u32>,
        bookmark: Option<String>,
    ) -> Result<InversionPagina, InversionError> {
        Self::require_role(
            user,
            &[Rol::Inversionista, Rol::Administrador],
        )?;

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

fn redondear_dos(valor: f64) -> f64 {
    (valor * 100.0).round() / 100.0
}