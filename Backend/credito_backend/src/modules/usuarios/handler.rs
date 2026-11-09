use super::{
    auth::AuthenticatedUser,
    model::{
        LoginInput, LoginResponse, PermisosInput, ProfileInput, RegisterInput, Rol, Usuario,
        UsuariosPagina, UsuariosQuery,
    },
    service::UsuarioService,
    UsuarioError,
};
use axum::{
    extract::{
        rejection::{JsonRejection, QueryRejection},
        Path, Query, State,
    },
    http::{header, HeaderMap, HeaderValue, StatusCode},
    Json,
};

pub async fn register(
    State(service): State<UsuarioService>,
    body: Result<Json<RegisterInput>, JsonRejection>,
) -> Result<(StatusCode, Json<Usuario>), UsuarioError> {
    let Json(input) = body.map_err(|_| UsuarioError::Invalid("JSON de registro inválido"))?;
    Ok((StatusCode::CREATED, Json(service.register(input).await?)))
}
pub async fn login(
    State(service): State<UsuarioService>,
    body: Result<Json<LoginInput>, JsonRejection>,
) -> Result<Json<LoginResponse>, UsuarioError> {
    let Json(input) =
        body.map_err(|_| UsuarioError::Invalid("JSON de inicio de sesión inválido"))?;
    Ok(Json(service.login(input).await?))
}
pub async fn me(user: AuthenticatedUser) -> Json<Usuario> {
    Json(user.0)
}
pub async fn update(
    State(service): State<UsuarioService>,
    user: AuthenticatedUser,
    body: Result<Json<ProfileInput>, JsonRejection>,
) -> Result<Json<Usuario>, UsuarioError> {
    let Json(input) = body.map_err(|_| UsuarioError::Invalid("Solo puede actualizar nombre"))?;
    Ok(Json(service.update_profile(&user.0, input).await?))
}

pub async fn list_users(
    State(service): State<UsuarioService>,
    user: AuthenticatedUser,
    query: Result<Query<UsuariosQuery>, QueryRejection>,
) -> Result<Json<UsuariosPagina>, UsuarioError> {
    user.require_roles(&[Rol::Administrador])?;
    let Query(query) =
        query.map_err(|_| UsuarioError::Invalid("Parámetros de usuarios inválidos"))?;
    Ok(Json(service.list_users(&user.0, query).await?))
}

pub async fn get_user(
    State(service): State<UsuarioService>,
    user: AuthenticatedUser,
    Path(id): Path<String>,
) -> Result<(HeaderMap, Json<Usuario>), UsuarioError> {
    with_etag(service.get_user(&user.0, &id).await?)
}

pub async fn update_permissions(
    State(service): State<UsuarioService>,
    user: AuthenticatedUser,
    Path(id): Path<String>,
    headers: HeaderMap,
    body: Result<Json<PermisosInput>, JsonRejection>,
) -> Result<(HeaderMap, Json<Usuario>), UsuarioError> {
    user.require_roles(&[Rol::Administrador])?;
    let revision = expected_revision(&headers)?;
    let Json(input) =
        body.map_err(|_| UsuarioError::Invalid("Indique únicamente rol y estado válidos"))?;
    with_etag(
        service
            .update_permissions(&user.0, &id, revision, input)
            .await?,
    )
}

fn expected_revision(headers: &HeaderMap) -> Result<&str, UsuarioError> {
    let mut values = headers.get_all(header::IF_MATCH).iter();
    let value = values.next().ok_or(UsuarioError::PreconditionRequired)?;
    if values.next().is_some() {
        return Err(UsuarioError::Invalid(
            "If-Match debe contener un único ETag fuerte",
        ));
    }
    value
        .to_str()
        .ok()
        .map(str::trim)
        .and_then(|v| v.strip_prefix('"').and_then(|v| v.strip_suffix('"')))
        .filter(|v| {
            !v.is_empty()
                && v.len() <= 128
                && v.bytes().all(|c| c.is_ascii_alphanumeric() || c == b'-')
        })
        .ok_or(UsuarioError::Invalid(
            "If-Match debe contener un único ETag fuerte",
        ))
}

fn with_etag(
    (usuario, revision): (Usuario, String),
) -> Result<(HeaderMap, Json<Usuario>), UsuarioError> {
    let mut headers = HeaderMap::new();
    headers.insert(
        header::ETAG,
        HeaderValue::from_str(&format!("\"{revision}\"")).map_err(|_| UsuarioError::Upstream)?,
    );
    Ok((headers, Json(usuario)))
}
