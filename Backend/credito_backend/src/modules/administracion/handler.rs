use axum::{
    extract::{rejection::QueryRejection, Query, State},
    http::{header, HeaderMap, HeaderValue},
    Json,
};

use super::{
    model::{AuditoriaPagina, AuditoriaQuery, ReporteModulo, ReporteQuery, Resumen},
    service::AdministracionService,
    AdministracionError,
};
use crate::modules::usuarios::auth::AuthenticatedUser;

fn private_json<T>(value: T) -> (HeaderMap, Json<T>) {
    let mut headers = HeaderMap::new();
    headers.insert(header::CACHE_CONTROL, HeaderValue::from_static("no-store"));
    (headers, Json(value))
}

pub async fn resumen(
    State(service): State<AdministracionService>,
    user: AuthenticatedUser,
) -> Result<(HeaderMap, Json<Resumen>), AdministracionError> {
    Ok(private_json(service.resumen(&user.0).await?))
}

pub async fn reporte(
    State(service): State<AdministracionService>,
    user: AuthenticatedUser,
    query: Result<Query<ReporteQuery>, QueryRejection>,
) -> Result<(HeaderMap, Json<ReporteModulo>), AdministracionError> {
    let Query(query) = query.map_err(|_| AdministracionError::Invalid("Módulo inválido; use usuarios, empresas, facturas, ofertas, inversiones, creditos, pagos o auditoria"))?;
    Ok(private_json(service.reporte(&user.0, query.modulo).await?))
}

pub async fn auditoria(
    State(service): State<AdministracionService>,
    user: AuthenticatedUser,
    query: Result<Query<AuditoriaQuery>, QueryRejection>,
) -> Result<(HeaderMap, Json<AuditoriaPagina>), AdministracionError> {
    let Query(query) =
        query.map_err(|_| AdministracionError::Invalid("Parámetros de auditoría inválidos"))?;
    Ok(private_json(service.auditoria(&user.0, query).await?))
}
