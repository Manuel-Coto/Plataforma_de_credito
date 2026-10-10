use chrono::Utc;

use crate::modules::{
    empresas::model::EstadoEmpresa,
    usuarios::model::{Rol, Usuario},
};

use super::{
    model::{
        CrearFactura, DatosDte, EstadoFactura, Factura, FacturaDocumento,
        FacturaPagina, ListQuery, VerificarDte,
    },
    repository::FacturaRepository,
    FacturaError,
};

#[derive(Clone)]
pub struct FacturaService {
    repository: Option<FacturaRepository>,
}

impl FacturaService {
    pub fn new(repository: Option<FacturaRepository>) -> Self {
        Self { repository }
    }

    fn repo(&self) -> Result<&FacturaRepository, FacturaError> {
        self.repository
            .as_ref()
            .ok_or(FacturaError::Unavailable)
    }

    fn require_role(user: &Usuario, allowed: &[Rol]) -> Result<(), FacturaError> {
        if allowed.contains(&user.rol) {
            Ok(())
        } else {
            Err(FacturaError::Forbidden)
        }
    }

    fn is_admin(user: &Usuario) -> bool {
        user.rol == Rol::Administrador
    }

    fn puede_ver(user: &Usuario, factura: &FacturaDocumento) -> bool {
        Self::is_admin(user)
            || factura.creado_por == user.id
            || (user.rol == Rol::Inversionista
            && matches!(
                    factura.estado,
                    EstadoFactura::Disponible
                        | EstadoFactura::ParcialmenteFinanciada
                        | EstadoFactura::Financiada
                ))
    }

    pub async fn create(
        &self,
        user: &Usuario,
        input: CrearFactura,
    ) -> Result<Factura, FacturaError> {
        Self::require_role(user, &[Rol::Pyme, Rol::Administrador])?;

        validar_factura(&input).map_err(FacturaError::Invalid)?;

        let repo = self.repo()?;

        let empresa = repo.get_empresa(&input.empresa_id).await?;

        // No permitir facturar con una empresa que no esté activa.
        let estado = empresa["estado"]
            .as_str()
            .or_else(|| empresa["datos"]["estado"].as_str())
            .unwrap_or("");

        if estado != "activa" && !Self::is_admin(user) {
            return Err(FacturaError::Forbidden);
        }

        // Una PYME solamente registra facturas para su propia empresa.
        if !Self::is_admin(user) {
            let responsable = empresa["usuario_responsable_id"]
                .as_str()
                .or_else(|| empresa["datos"]["usuario_responsable_id"].as_str());

            if responsable != Some(user.id.as_str()) {
                return Err(FacturaError::Forbidden);
            }
        }

        if repo.dte_exists(input.codigo_generacion.trim()).await? {
            return Err(FacturaError::Duplicate);
        }

        let ahora = Utc::now();

        let documento = FacturaDocumento {
            id: Some(format!(
                "factura-{}",
                ahora.timestamp_nanos_opt().unwrap_or_default()
            )),
            rev: None,
            tipo: "factura".to_string(),
            empresa_id: input.empresa_id.trim().to_string(),
            numero: input.numero.trim().to_string(),
            dte: DatosDte {
                codigo_generacion: input.codigo_generacion.trim().to_string(),
                sello_recepcion: None,
                verificado: false,
                fecha_verificacion: None,
            },
            moneda: input.moneda.trim().to_uppercase(),
            monto_total_centavos: input.monto_total_centavos,
            monto_financiado_centavos: 0,
            fecha_emision: input.fecha_emision,
            fecha_vencimiento: input.fecha_vencimiento,
            estado: EstadoFactura::PendienteVerificacion,
            creado_por: user.id.clone(),
            fecha_creacion: ahora,
            fecha_actualizacion: None,
            extra: Default::default(),
        };

        repo.save(documento).await?.into_factura()
    }

    pub async fn list(
        &self,
        user: &Usuario,
        query: ListQuery,
    ) -> Result<FacturaPagina, FacturaError> {
        let limit = query.limit.unwrap_or(20).clamp(1, 100);

        let owner = match user.rol {
            Rol::Pyme => Some(user.id.as_str()),
            Rol::Inversionista | Rol::Administrador => None,
        };

        let (documentos, bookmark) = self
            .repo()?
            .list(limit, query.bookmark, query.estado, owner)
            .await?;

        let facturas = documentos
            .into_iter()
            .filter(|f| Self::puede_ver(user, f))
            .map(FacturaDocumento::into_factura)
            .collect::<Result<Vec<_>, _>>()?;

        Ok(FacturaPagina {
            facturas,
            bookmark,
            limit,
        })
    }

    pub async fn get(
        &self,
        user: &Usuario,
        id: &str,
    ) -> Result<Factura, FacturaError> {
        let documento = self.repo()?.get(id).await?;

        if !Self::puede_ver(user, &documento) {
            return Err(FacturaError::Forbidden);
        }

        documento.into_factura()
    }

    pub async fn verify_dte(
        &self,
        user: &Usuario,
        id: &str,
        input: VerificarDte,
    ) -> Result<Factura, FacturaError> {
        Self::require_role(user, &[Rol::Administrador])?;

        let repo = self.repo()?;
        let mut factura = repo.get(id).await?;

        if input.sello_recepcion.trim().is_empty() {
            return Err(FacturaError::Invalid(
                "El sello de recepción del DTE es obligatorio",
            ));
        }

        if factura.dte.verificado {
            return Err(FacturaError::Conflict);
        }

        factura.dte.sello_recepcion =
            Some(input.sello_recepcion.trim().to_string());
        factura.dte.verificado = true;
        factura.dte.fecha_verificacion = Some(Utc::now());
        factura.estado = EstadoFactura::Disponible;
        factura.fecha_actualizacion = Some(Utc::now());

        repo.save(factura).await?.into_factura()
    }
}

pub fn validar_factura(input: &CrearFactura) -> Result<(), &'static str> {
    if input.empresa_id.trim().is_empty() {
        return Err("La empresa es obligatoria");
    }

    if input.numero.trim().is_empty() {
        return Err("El número de factura es obligatorio");
    }

    if input.codigo_generacion.trim().is_empty() {
        return Err("El código de generación del DTE es obligatorio");
    }

    if input.codigo_generacion.len() > 100 {
        return Err("El código de generación del DTE es demasiado largo");
    }

    if input.monto_total_centavos <= 0 {
        return Err("El monto debe ser mayor que cero");
    }

    if input.moneda.trim().to_uppercase() != "USD" {
        return Err("La moneda admitida actualmente es USD");
    }

    if input.fecha_vencimiento < input.fecha_emision {
        return Err("El vencimiento no puede ser anterior a la emisión");
    }

    Ok(())
}