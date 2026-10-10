use axum::{
    extract::{
        rejection::{JsonRejection, QueryRejection},
        Path, Query, State,
    },
    http::{header, HeaderMap, HeaderValue, StatusCode},
    Json,
};

use super::{
    model::{Empresa, EmpresaInput, EmpresaPagina, ListQuery},
    service::EmpresaService,
    EmpresaError,
};
use crate::modules::usuarios::auth::AuthenticatedUser;
use crate::modules::usuarios::model::Rol;

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
) -> Result<(HeaderMap, Json<Empresa>), EmpresaError> {
    with_etag(service.get(&user.0, &id).await?)
}

pub async fn approve(
    State(service): State<EmpresaService>,
    user: AuthenticatedUser,
    Path(id): Path<String>,
    headers: HeaderMap,
) -> Result<(HeaderMap, Json<Empresa>), EmpresaError> {
    review(service, user, id, headers, true).await
}

pub async fn reject(
    State(service): State<EmpresaService>,
    user: AuthenticatedUser,
    Path(id): Path<String>,
    headers: HeaderMap,
) -> Result<(HeaderMap, Json<Empresa>), EmpresaError> {
    review(service, user, id, headers, false).await
}

async fn review(
    service: EmpresaService,
    user: AuthenticatedUser,
    id: String,
    headers: HeaderMap,
    approved: bool,
) -> Result<(HeaderMap, Json<Empresa>), EmpresaError> {
    user.require_roles(&[Rol::Administrador])
        .map_err(|_| EmpresaError::Forbidden)?;
    let revision = expected_revision(&headers)?;
    with_etag(service.review(&user.0, &id, revision, approved).await?)
}

fn expected_revision(headers: &HeaderMap) -> Result<&str, EmpresaError> {
    let mut values = headers.get_all(header::IF_MATCH).iter();
    let value = values.next().ok_or(EmpresaError::PreconditionRequired)?;
    if values.next().is_some() {
        return Err(EmpresaError::Invalid(
            "If-Match debe contener un único ETag fuerte",
        ));
    }
    let value = value
        .to_str()
        .map_err(|_| EmpresaError::Invalid("If-Match inválido"))?
        .trim();
    let revision = value
        .strip_prefix('"')
        .and_then(|v| v.strip_suffix('"'))
        .filter(|rev| {
            !rev.is_empty()
                && rev.len() <= 128
                && rev.bytes().all(|b| b.is_ascii_alphanumeric() || b == b'-')
        })
        .ok_or(EmpresaError::Invalid(
            "If-Match debe contener un único ETag fuerte",
        ))?;
    Ok(revision)
}

fn with_etag(
    (empresa, revision): (Empresa, String),
) -> Result<(HeaderMap, Json<Empresa>), EmpresaError> {
    let mut headers = HeaderMap::new();
    headers.insert(
        header::ETAG,
        HeaderValue::from_str(&format!("\"{revision}\"")).map_err(|_| EmpresaError::Upstream)?,
    );
    headers.insert(header::CACHE_CONTROL, HeaderValue::from_static("no-store"));
    Ok((headers, Json(empresa)))
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
