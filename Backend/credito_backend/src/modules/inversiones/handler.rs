use axum::{
    extract::{
        rejection::{JsonRejection, QueryRejection},
        Query, State,
    },
    http::StatusCode,
    Json,
};

use crate::modules::usuarios::auth::AuthenticatedUser;

use super::{
    model::{
        CrearInversion, CrearOferta, Inversion, InversionPagina, ListarOfertas, Oferta,
        OfertaPagina,
    },
    service::InversionService,
    InversionError,
};

pub async fn crear_oferta(
    State(service): State<InversionService>,
    user: AuthenticatedUser,
    body: Result<Json<CrearOferta>, JsonRejection>,
) -> Result<(StatusCode, Json<Oferta>), InversionError> {
    let Json(input) = body.map_err(|_| InversionError::Invalid("JSON de oferta inválido"))?;

    let oferta = service.crear_oferta(&user.0, input).await?;

    Ok((StatusCode::CREATED, Json(oferta)))
}

pub async fn listar_ofertas(
    State(service): State<InversionService>,
    user: AuthenticatedUser,
    query: Result<Query<ListarOfertas>, QueryRejection>,
) -> Result<Json<OfertaPagina>, InversionError> {
    let Query(query) =
        query.map_err(|_| InversionError::Invalid("Parámetros de consulta inválidos"))?;

    Ok(Json(service.listar_ofertas(&user.0, query).await?))
}

pub async fn invertir(
    State(service): State<InversionService>,
    user: AuthenticatedUser,
    body: Result<Json<CrearInversion>, JsonRejection>,
) -> Result<(StatusCode, Json<Inversion>), InversionError> {
    let Json(input) = body.map_err(|_| InversionError::Invalid("JSON de inversión inválido"))?;

    let inversion = service.invertir(&user.0, input).await?;

    Ok((StatusCode::CREATED, Json(inversion)))
}

pub async fn listar_mis_inversiones(
    State(service): State<InversionService>,
    user: AuthenticatedUser,
    query: Result<Query<ListarOfertas>, QueryRejection>,
) -> Result<Json<InversionPagina>, InversionError> {
    let Query(query) =
        query.map_err(|_| InversionError::Invalid("Parámetros de consulta inválidos"))?;

    Ok(Json(
        service
            .listar_mis_inversiones(&user.0, query.limit, query.bookmark)
            .await?,
    ))
}
