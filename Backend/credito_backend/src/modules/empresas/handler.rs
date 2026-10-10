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

pub async fn create(
    State(service): State<EmpresaService>,
    body: Result<Json<EmpresaInput>, JsonRejection>,
) -> Result<(StatusCode, Json<Empresa>), EmpresaError> {
    let Json(input) = body.map_err(|_| {
        EmpresaError::Invalid(
            "JSON inválido; revise los campos requeridos y no envíe estado, id o fechas",
        )
    })?;
    Ok((StatusCode::CREATED, Json(service.create(input).await?)))
}

pub async fn list(
    State(service): State<EmpresaService>,
    query: Result<Query<ListQuery>, QueryRejection>,
) -> Result<Json<EmpresaPagina>, EmpresaError> {
    let Query(query) =
        query.map_err(|_| EmpresaError::Invalid("Parámetros de paginación inválidos"))?;
    Ok(Json(service.list(query).await?))
}

pub async fn get(
    State(service): State<EmpresaService>,
    Path(id): Path<String>,
) -> Result<Json<Empresa>, EmpresaError> {
    Ok(Json(service.get(&id).await?))
}

pub async fn update(
    State(service): State<EmpresaService>,
    Path(id): Path<String>,
    body: Result<Json<EmpresaInput>, JsonRejection>,
) -> Result<Json<Empresa>, EmpresaError> {
    let Json(input) = body.map_err(|_| {
        EmpresaError::Invalid(
            "JSON inválido; revise los campos requeridos y no envíe estado, id o fechas",
        )
    })?;
    Ok(Json(service.update(&id, input).await?))
}

pub async fn deactivate(
    State(service): State<EmpresaService>,
    Path(id): Path<String>,
) -> Result<Json<Empresa>, EmpresaError> {
    Ok(Json(service.deactivate(&id).await?))
}
