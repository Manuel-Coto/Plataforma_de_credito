# Plataforma de Crédito Colaborativo

Aplicación académica para Windows: interfaz Flutter, API Rust/Axum y Apache CouchDB local. Implementa los seis módulos del proyecto, con separación de permisos entre PYME, inversionista y administrador.

## Qué permite hacer

- **Usuarios:** registro e inicio de sesión, edición del nombre y gestión administrativa de roles/estados con control de revisión.
- **Empresas:** registro de empresas propias, consulta, edición y desactivación; revisión administrativa con aprobación o rechazo.
- **Facturas:** registro, consulta y verificación administrativa del DTE.
- **Inversiones:** publicación de ofertas, aportes idempotentes, confirmación simulada y recuperación explícita de reservas.
- **Créditos:** emisión administrativa, seguimiento, pagos simulados y reintentos de sincronización sin duplicar pagos.
- **Administración:** resumen, reportes por módulo, importes separados por moneda y consulta de auditoría con filtros y cursores.

La verificación del DTE es una decisión administrativa manual. Los pagos y aportes son simulados; la aplicación no realiza cobros bancarios ni consultas oficiales a Hacienda.

## Preparar el entorno local

Se necesitan Flutter con soporte Windows, Visual Studio con herramientas de C++, Rust/Cargo y Apache CouchDB. Las dependencias exactas están en Cargo.lock y pubspec.lock. Este repositorio ya contiene el proyecto Flutter; no es necesario regenerarlo.

1. Iniciar el servicio de CouchDB y comprobar [Fauxton](http://127.0.0.1:5984/_utils/).
2. Preparar la configuración del backend desde la raíz:

```powershell
cd Backend/credito_backend
if (-not (Test-Path .env)) { Copy-Item .env.example .env }
```

Completar COUCHDB_URL, COUCHDB_USERNAME y COUCHDB_PASSWORD con la configuración local. JWT_SECRET debe ser una clave aleatoria de al menos 32 caracteres, sin espacios externos ni la palabra CAMBIAR; JWT_TTL_SECONDS es 3600 por defecto. La plantilla .env.example no se carga como configuración. No subir .env a Git ni compartir su contenido.

Para generar una clave JWT propia en PowerShell:

```powershell
$jwtBytes = New-Object byte[] 48
$jwtRng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
$jwtRng.GetBytes($jwtBytes)
$jwtRng.Dispose()
[Convert]::ToBase64String($jwtBytes)
```

Guardar el resultado únicamente en JWT_SECRET del .env local.

3. Ejecutar la API desde Backend/credito_backend:

```powershell
cargo run --locked
```

La API escucha en http://127.0.0.1:3000. Al arrancar crea las seis bases y sus índices si faltan; conserva los datos existentes. [/api/health](http://127.0.0.1:3000/api/health) confirma que la API responde, pero no certifica la disponibilidad de CouchDB ni la autenticación.

4. En otra terminal:

```powershell
cd Frontend/plataforma_credito
flutter pub get
flutter run -d windows
```

Tras cambiar .env hay que reiniciar la API. La URL del cliente está en Frontend/plataforma_credito/lib/core/config/api_config.dart. Flutter se comunica exclusivamente con la API, sin recibir credenciales de CouchDB.

## Recorrido funcional

Una PYME registra su empresa. Un administrador la aprueba. La PYME registra una factura y el administrador verifica su DTE. Se publica una oferta; un inversionista registra y confirma su aporte simulado. Cuando la oferta está financiada, el administrador emite el crédito. La PYME o un administrador registra los pagos. Al completar el pago se actualizan factura e inversiones y se registran los eventos de auditoría.

El registro público permite PYME e inversionista. La preparación de la primera cuenta administradora está descrita en [Usuarios](docs/api/usuarios.md#cuenta-administradora-de-prueba); las siguientes se gestionan desde una cuenta administradora existente.

## Trabajo sin conexión

El modo local para Windows requiere un inicio de sesión inicial en línea. No persiste JWT ni contraseñas. Las instantáneas y la cola de cambios se cifran mediante DPAPI para el usuario de Windows. La sincronización es explícita y comprueba conflictos; las mutaciones financieras y administrativas requieren conexión. Cerrar sesión, recibir 401 o cambiar de rol elimina los datos y pendientes anteriores con aviso en la interfaz.

El alcance y las limitaciones están en [Trabajo sin conexión](docs/integracion/offline_windows.md). Este modo local no es replicación de CouchDB.

## Comprobaciones

```powershell
cd Backend/credito_backend
cargo fmt --check
cargo test --locked
```

```powershell
cd Frontend/plataforma_credito
flutter analyze
flutter test
```

Las pruebas que necesitan CouchDB real están ignoradas por defecto. Para ejecutar el recorrido completo de forma aislada, consultar [Prueba con CouchDB real](docs/integracion/couchdb_real.md). Esa prueba crea seis bases nuevas con nombre aleatorio y elimina únicamente las que ha creado; nunca usa las seis bases habituales de la aplicación.

## Contratos y documentación

- [Usuarios y permisos](docs/api/usuarios.md)
- [Empresas](docs/api/empresas.md)
- [Facturas](docs/api/facturas.md)
- [Ofertas e inversiones](docs/api/inversiones.md)
- [Créditos y pagos](docs/api/creditos.md)
- [Reportes y auditoría](docs/api/administracion.md)
- [Frontend de créditos y administración](docs/modulos/frontend_modulos_5_6.md)
