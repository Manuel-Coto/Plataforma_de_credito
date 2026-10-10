use axum::{
    extract::{
        rejection::{JsonRejection, QueryRejection},
        Path, Query, State,
    },
    http::StatusCode,
    Json,
};

use super::{
    model::{Empresa, EmpresaInput, EmpresaPagina, ListQuery},
    service::EmpresaService,
    EmpresaError,
};
use crate::modules::usuarios::auth::AuthenticatedUser;

pub async fn create(
    State(service): State<EmpresaService>,
    user: AuthenticatedUser,
    body: Result<Json<EmpresaInput>, JsonRejection>,
) -> Result<(StatusCode, Json<Empresa>), EmpresaError> {
    let Json(input) = body.map_err(|_| {
        EmpresaError::Invalid(
            "JSON inválido; revise los campos requeridos y no envíe estado, id o fechas",
        )
    })?;
    Ok((
        StatusCode::CREATED,
        Json(service.create(&user.0, input).await?),
    ))
}

pub async fn list(
    State(service): State<EmpresaService>,
    user: AuthenticatedUser,
    query: Result<Query<ListQuery>, QueryRejection>,
) -> Result<Json<EmpresaPagina>, EmpresaError> {
    let Query(query) =
        query.map_err(|_| EmpresaError::Invalid("Parámetros de paginación inválidos"))?;
    Ok(Json(service.list(&user.0, query).await?))
}

pub async fn get(
    State(service): State<EmpresaService>,
    user: AuthenticatedUser,
    Path(id): Path<String>,
) -> Result<Json<Empresa>, EmpresaError> {
    Ok(Json(service.get(&user.0, &id).await?))
}

pub async fn update(
    State(service): State<EmpresaService>,
    user: AuthenticatedUser,
    Path(id): Path<String>,
    body: Result<Json<EmpresaInput>, JsonRejection>,
) -> Result<Json<Empresa>, EmpresaError> {
    let Json(input) = body.map_err(|_| {
        EmpresaError::Invalid(
            "JSON inválido; revise los campos requeridos y no envíe estado, id o fechas",
        )
    })?;
    Ok(Json(service.update(&user.0, &id, input).await?))
}

pub async fn deactivate(
    State(service): State<EmpresaService>,
    user: AuthenticatedUser,
    Path(id): Path<String>,
) -> Result<Json<Empresa>, EmpresaError> {
    Ok(Json(service.deactivate(&user.0, &id).await?))
}
