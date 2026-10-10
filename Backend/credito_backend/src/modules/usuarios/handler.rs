use super::{
    auth::AuthenticatedUser,
    model::{LoginInput, LoginResponse, ProfileInput, RegisterInput, Usuario},
    service::UsuarioService,
    UsuarioError,
};
use axum::{
    extract::{rejection::JsonRejection, State},
    http::StatusCode,
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
