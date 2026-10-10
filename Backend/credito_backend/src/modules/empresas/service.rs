use chrono::Utc;

use super::{
    model::{
        Empresa, EmpresaDatos, EmpresaDocumento, EmpresaInput, EmpresaPagina, EstadoEmpresa,
        ListQuery,
    },
    repository::EmpresaRepository,
    EmpresaError,
};

#[derive(Clone)]
pub struct EmpresaService {
    repository: Option<EmpresaRepository>,
}

impl EmpresaService {
    pub fn new(repository: Option<EmpresaRepository>) -> Self {
        Self { repository }
    }

    fn repository(&self) -> Result<&EmpresaRepository, EmpresaError> {
        self.repository.as_ref().ok_or(EmpresaError::Configuration)
    }

    pub async fn create(&self, input: EmpresaInput) -> Result<Empresa, EmpresaError> {
        let input = validate(input)?;
        let repository = self.repository()?;
        if repository.nit_exists(&input.nit, None).await? {
            return Err(EmpresaError::Duplicate);
        }
        let now = Utc::now();
        let document = EmpresaDocumento {
            id: None,
            rev: None,
            datos: EmpresaDatos {
                nombre: input.nombre,
                nit: input.nit,
                correo: input.correo,
                telefono: input.telefono,
                direccion: input.direccion,
                estado: EstadoEmpresa::Pendiente,
                usuario_responsable_id: input.usuario_responsable_id,
                fecha_creacion: Some(now),
                fecha_actualizacion: Some(now),
            },
        };
        repository.save(document).await?.into_empresa()
    }

    pub async fn get(&self, id: &str) -> Result<Empresa, EmpresaError> {
        validate_id(id)?;
        self.repository()?.get(id).await?.into_empresa()
    }

    pub async fn list(&self, query: ListQuery) -> Result<EmpresaPagina, EmpresaError> {
        let limit = query.limit.unwrap_or(25);
        if !(1..=100).contains(&limit) {
            return Err(EmpresaError::Invalid("limit debe estar entre 1 y 100"));
        }
        if query.bookmark.as_ref().is_some_and(|b| b.len() > 8192) {
            return Err(EmpresaError::Invalid("bookmark demasiado largo"));
        }
        let (documents, bookmark) = self.repository()?.list(limit, query.bookmark).await?;
        let empresas = documents
            .into_iter()
            .map(EmpresaDocumento::into_empresa)
            .collect::<Result<_, _>>()?;
        Ok(EmpresaPagina {
            empresas,
            bookmark,
            limit,
        })
    }

    pub async fn update(&self, id: &str, input: EmpresaInput) -> Result<Empresa, EmpresaError> {
        validate_id(id)?;
        let input = validate(input)?;
        let repository = self.repository()?;
        let mut document = repository.get(id).await?;
        if repository.nit_exists(&input.nit, Some(id)).await? {
            return Err(EmpresaError::Duplicate);
        }
        document.datos.nombre = input.nombre;
        document.datos.nit = input.nit;
        document.datos.correo = input.correo;
        document.datos.telefono = input.telefono;
        document.datos.direccion = input.direccion;
        document.datos.usuario_responsable_id = input.usuario_responsable_id;
        document.datos.fecha_actualizacion = Some(Utc::now());
        repository.save(document).await?.into_empresa()
    }

    pub async fn deactivate(&self, id: &str) -> Result<Empresa, EmpresaError> {
        validate_id(id)?;
        let repository = self.repository()?;
        let mut document = repository.get(id).await?;
        if document.datos.estado != EstadoEmpresa::Inactiva {
            document.datos.estado = EstadoEmpresa::Inactiva;
            document.datos.fecha_actualizacion = Some(Utc::now());
            document = repository.save(document).await?;
        }
        document.into_empresa()
    }
}

fn validate_id(id: &str) -> Result<(), EmpresaError> {
    if id.is_empty()
        || id.len() > 512
        || id.starts_with('_')
        || id == "."
        || id == ".."
        || id.contains('/')
        || id.chars().any(char::is_control)
    {
        return Err(EmpresaError::Invalid("Identificador de empresa inválido"));
    }
    Ok(())
}

fn validate(mut input: EmpresaInput) -> Result<EmpresaInput, EmpresaError> {
    input.nombre = input.nombre.trim().to_owned();
    input.nit = input.nit.trim().to_owned();
    input.correo = input.correo.trim().to_owned();
    input.telefono = input.telefono.trim().to_owned();
    input.direccion = input.direccion.trim().to_owned();
    input.usuario_responsable_id = input.usuario_responsable_id.map(|id| id.trim().to_owned());
    if input.nombre.is_empty() {
        return Err(EmpresaError::Invalid("El nombre no puede estar vacío"));
    }
    if input.nit.is_empty() {
        return Err(EmpresaError::Invalid("El NIT no puede estar vacío"));
    }
    if !valid_email(&input.correo) {
        return Err(EmpresaError::Invalid(
            "El correo no tiene un formato válido",
        ));
    }
    if input.nombre.len() > 250
        || input.nit.len() > 64
        || input.telefono.len() > 50
        || input.direccion.len() > 1000
        || input
            .usuario_responsable_id
            .as_ref()
            .is_some_and(|id| id.is_empty() || id.len() > 512)
    {
        return Err(EmpresaError::Invalid(
            "Campos demasiado largos o responsable vacío",
        ));
    }
    Ok(input)
}

/// Subconjunto habitual de correo ASCII; no comprueba que el buzón exista.
fn valid_email(email: &str) -> bool {
    if email.len() > 254 || !email.is_ascii() {
        return false;
    }
    let Some((local, domain)) = email.split_once('@') else {
        return false;
    };
    if local.is_empty()
        || local.len() > 64
        || local.starts_with('.')
        || local.ends_with('.')
        || local.contains("..")
        || !local
            .bytes()
            .all(|c| c.is_ascii_alphanumeric() || b".!#$%&'*+-/=?^_`{|}~".contains(&c))
    {
        return false;
    }
    let labels: Vec<_> = domain.split('.').collect();
    labels.len() >= 2
        && labels.iter().all(|label| {
            !label.is_empty()
                && label.len() <= 63
                && !label.starts_with('-')
                && !label.ends_with('-')
                && label
                    .bytes()
                    .all(|c| c.is_ascii_alphanumeric() || c == b'-')
        })
}

#[cfg(test)]
mod tests {
    use super::*;

    fn input() -> EmpresaInput {
        EmpresaInput {
            nombre: " Empresa ficticia ".into(),
            nit: " NIT-PRUEBA ".into(),
            correo: " contacto@example.test ".into(),
            telefono: " 0000-0000 ".into(),
            direccion: " Dirección ficticia ".into(),
            usuario_responsable_id: None,
        }
    }

    #[test]
    fn normalizes_and_rejects_empty_required_fields() {
        let normalized = validate(input()).unwrap();
        assert_eq!(normalized.nombre, "Empresa ficticia");
        assert_eq!(normalized.nit, "NIT-PRUEBA");
        for field in ["nombre", "nit"] {
            let mut value = input();
            if field == "nombre" {
                value.nombre = " \t".into();
            } else {
                value.nit = " \n".into();
            }
            assert!(matches!(validate(value), Err(EmpresaError::Invalid(_))));
        }
    }

    #[test]
    fn validates_email_format() {
        for value in ["a@example.test", "a+b@sub.example.test"] {
            assert!(valid_email(value));
        }
        for value in [
            "",
            "a",
            "@example.test",
            "a@",
            "a@@example.test",
            "a b@example.test",
            "a@example",
            "a@-example.test",
            ".a@example.test",
            "a..b@example.test",
            "a@example..test",
        ] {
            assert!(!valid_email(value), "{value}");
        }
    }

    #[test]
    fn rejects_reserved_ids() {
        for id in ["", "_design", "_all_docs", "..", "a/b", "a\n"] {
            assert!(validate_id(id).is_err());
        }
        assert!(validate_id("empresa_prueba_001").is_ok());
    }
}
