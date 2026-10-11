use super::{model::*, service::CreditoService, CreditoError};
use crate::modules::usuarios::auth::AuthenticatedUser;
use axum::{
    extract::{
        rejection::{JsonRejection, QueryRejection},
        Path, Query, State,
    },
    http::StatusCode,
    Json,
};

pub async fn create(
    State(service): State<CreditoService>,
    user: AuthenticatedUser,
    body: Result<Json<CrearCredito>, JsonRejection>,
) -> Result<(StatusCode, Json<CreditoResultado>), CreditoError> {
    let Json(input) = body.map_err(|_| CreditoError::Invalid("JSON de crédito inválido"))?;
    Ok((
        StatusCode::CREATED,
        Json(service.create(&user.0, input).await?),
    ))
}
pub async fn list(
    State(service): State<CreditoService>,
    user: AuthenticatedUser,
    query: Result<Query<ListQuery>, QueryRejection>,
) -> Result<Json<CreditoPagina>, CreditoError> {
    let Query(query) =
        query.map_err(|_| CreditoError::Invalid("Parámetros de consulta inválidos"))?;
    Ok(Json(service.list(&user.0, query).await?))
}
pub async fn get(
    State(service): State<CreditoService>,
    user: AuthenticatedUser,
    Path(id): Path<String>,
) -> Result<Json<CreditoVista>, CreditoError> {
    Ok(Json(service.get(&user.0, &id).await?))
}
pub async fn pagar(
    State(service): State<CreditoService>,
    user: AuthenticatedUser,
    Path(id): Path<String>,
    body: Result<Json<RegistrarPago>, JsonRejection>,
) -> Result<Json<CreditoResultado>, CreditoError> {
    let Json(input) = body.map_err(|_| CreditoError::Invalid("JSON de pago inválido"))?;
    Ok(Json(service.pagar(&user.0, &id, input).await?))
}
pub async fn confirmar_aporte(
    State(service): State<CreditoService>,
    user: AuthenticatedUser,
    Path(id): Path<String>,
) -> Result<Json<AporteResultado>, CreditoError> {
    Ok(Json(service.confirmar_aporte(&user.0, &id).await?))
}
pub async fn sincronizar(
    State(service): State<CreditoService>,
    user: AuthenticatedUser,
    Path(id): Path<String>,
) -> Result<Json<CreditoResultado>, CreditoError> {
    Ok(Json(service.sincronizar(&user.0, &id).await?))
}
