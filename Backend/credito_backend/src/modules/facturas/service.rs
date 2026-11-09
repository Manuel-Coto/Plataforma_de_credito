use chrono::Utc;

use crate::modules::usuarios::model::{Rol, Usuario};

use super::{
    model::{
        CrearFactura, DatosDte, EstadoFactura, Factura, FacturaDocumento, FacturaPagina, ListQuery,
        VerificarDte,
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
        self.repository.as_ref().ok_or(FacturaError::Unavailable)
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
        key: Option<&str>,
    ) -> Result<Factura, FacturaError> {
        Self::require_role(user, &[Rol::Pyme, Rol::Administrador])?;

        validar_factura(&input).map_err(FacturaError::Invalid)?;

        let repo = self.repo()?;

        let request_id = key.map(|key| crate::idempotency::document_id("factura", &user.id, key));
        let fingerprint = crate::idempotency::fingerprint(serde_json::json!({
            "empresa_id": input.empresa_id.trim(), "numero": input.numero.trim(),
            "codigo_generacion": input.codigo_generacion.trim(), "moneda": input.moneda.trim().to_uppercase(),
            "monto_total_centavos": input.monto_total_centavos, "fecha_emision": input.fecha_emision,
            "fecha_vencimiento": input.fecha_vencimiento,
        }));
        if let Some(id) = &request_id {
            match repo.get(id).await {
                Ok(existing) => return replay(existing, &user.id, &fingerprint),
                Err(FacturaError::NotFound) => {}
                Err(error) => return Err(error),
            }
        }

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
            if let Some(id) = &request_id {
                if let Ok(existing) = repo.get(id).await {
                    return replay(existing, &user.id, &fingerprint);
                }
            }
            return Err(FacturaError::Duplicate);
        }

        let ahora = Utc::now();

        let documento = FacturaDocumento {
            id: request_id.clone().or_else(|| {
                Some(format!(
                    "factura-{}",
                    ahora.timestamp_nanos_opt().unwrap_or_default()
                ))
            }),
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
            extra: request_id
                .as_ref()
                .map(|_| {
                    [(
                        "solicitud_creacion_huella".into(),
                        serde_json::json!(fingerprint),
                    )]
                    .into()
                })
                .unwrap_or_default(),
        };

        match repo.save(documento).await {
            Ok(document) => document.into_factura(),
            Err(FacturaError::Conflict) if request_id.is_some() => replay(
                repo.get(request_id.as_deref().unwrap()).await?,
                &user.id,
                &fingerprint,
            ),
            Err(error) => Err(error),
        }
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
            .list(
                limit,
                query.bookmark,
                query.estado,
                owner,
                (user.rol == Rol::Inversionista).then_some(user.id.as_str()),
            )
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

    pub async fn get(&self, user: &Usuario, id: &str) -> Result<Factura, FacturaError> {
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

        if factura.dte.verificado || factura.estado != EstadoFactura::PendienteVerificacion {
            return Err(FacturaError::Conflict);
        }

        factura.dte.sello_recepcion = Some(input.sello_recepcion.trim().to_string());
        factura.dte.verificado = true;
        factura.dte.fecha_verificacion = Some(Utc::now());
        factura.estado = EstadoFactura::Disponible;
        factura.fecha_actualizacion = Some(Utc::now());

        repo.save(factura).await?.into_factura()
    }
}

fn replay(
    document: FacturaDocumento,
    actor: &str,
    fingerprint: &str,
) -> Result<Factura, FacturaError> {
    if document.creado_por != actor
        || document
            .extra
            .get("solicitud_creacion_huella")
            .and_then(serde_json::Value::as_str)
            != Some(fingerprint)
    {
        return Err(FacturaError::Conflict);
    }
    document.into_factura()
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

#[cfg(test)]
mod dte_tests {
    use super::*;
    use axum::{routing::get, Json, Router};
    use serde_json::json;
    use std::sync::{Arc, Mutex};

    #[tokio::test]
    async fn verification_only_writes_pending_documents_and_requires_admin() {
        use crate::modules::usuarios::model::EstadoUsuario;
        let now = Utc::now();
        let mut user = Usuario {
            id: "admin-test".into(),
            nombre: "Prueba".into(),
            correo: "prueba@example.test".into(),
            rol: Rol::Administrador,
            estado: EstadoUsuario::Activo,
            fecha_creacion: now,
            fecha_actualizacion: now,
        };
        user.rol = Rol::Pyme;
        assert!(matches!(
            FacturaService::new(None)
                .verify_dte(
                    &user,
                    "factura-1",
                    VerificarDte {
                        sello_recepcion: "sello".into()
                    }
                )
                .await,
            Err(FacturaError::Forbidden)
        ));
        user.rol = Rol::Administrador;
        for estado in ["pendiente_verificacion", "pagada", "rechazada"] {
            let doc = json!({"_id":"factura-1","_rev":"1-test","tipo":"factura","empresa_id":"empresa-1","numero":"F-1","dte":{"codigo_generacion":"codigo","verificado":false,"sello_recepcion":null,"fecha_verificacion":null},"moneda":"USD","monto_total_centavos":10000,"monto_financiado_centavos":0,"fecha_emision":"2026-11-01","fecha_vencimiento":"2026-12-01","estado":estado,"creado_por":"pyme-test","fecha_creacion":"2026-11-01T12:00:00Z","fecha_actualizacion":null});
            let writes = Arc::new(Mutex::new(Vec::new()));
            let saved = writes.clone();
            let app = Router::new().route(
                "/facturas/factura-1",
                get(move || {
                    let doc = doc.clone();
                    async move { Json(doc) }
                })
                .put(move |Json(body): Json<serde_json::Value>| {
                    let saved = saved.clone();
                    async move {
                        saved.lock().unwrap().push(body);
                        Json(json!({"ok":true,"id":"factura-1","rev":"2-test"}))
                    }
                }),
            );
            let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
            let addr = listener.local_addr().unwrap();
            let task = tokio::spawn(async move {
                axum::serve(listener, app).await.unwrap();
            });
            let db = crate::database::connection::CouchDb::from_parts(
                format!("http://{addr}"),
                "test".into(),
                "test".into(),
            )
            .unwrap();
            let repo = FacturaRepository::from_connection(&db).unwrap();
            let result = FacturaService::new(Some(repo))
                .verify_dte(
                    &user,
                    "factura-1",
                    VerificarDte {
                        sello_recepcion: " sello-test ".into(),
                    },
                )
                .await;
            task.abort();
            if estado == "pendiente_verificacion" {
                let factura = result.unwrap();
                assert!(factura.datos.dte.verificado);
                assert_eq!(writes.lock().unwrap()[0]["estado"], "disponible");
                assert_eq!(
                    writes.lock().unwrap()[0]["dte"]["sello_recepcion"],
                    "sello-test"
                );
            } else {
                assert!(matches!(result, Err(FacturaError::Conflict)));
                assert!(writes.lock().unwrap().is_empty());
            }
        }
    }
}
