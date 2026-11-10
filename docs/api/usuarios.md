# Usuarios y autenticación

URL local: `http://127.0.0.1:3000`. El backend crea la base `usuarios` y el índice `usuarios-correo/por-correo` al iniciar; si existen, continúa sin borrarlos. La estructura interna está en [la documentación de usuarios](../../database/usuarios/README.md).

## Configuración local

Configurar `COUCHDB_URL`, `COUCHDB_USERNAME`, `COUCHDB_PASSWORD` y `JWT_SECRET` en `Backend/credito_backend/.env`. La clave JWT debe ser aleatoria, tener al menos 32 caracteres, no contener `CAMBIAR` ni espacios externos. No subir este archivo a Git. `JWT_TTL_SECONDS` es opcional (3600 por defecto; rango 60–86400).

Después de cambiar `.env`, reiniciar el backend desde `Backend/credito_backend` con `cargo run`. Si aparece `Usuarios no configurado; revisar CouchDB y JWT_SECRET`, el registro responderá 503 aunque `/api/health` esté activo.

La pantalla Flutter de usuarios envía el formulario a `POST /api/auth/register`, bloquea el botón mientras espera y muestra la respuesta de error del servidor. Al completar el registro, confirma la creación y borra la contraseña del formulario.

## Rutas

| Método y ruta | Acceso | Respuesta exitosa |
|---|---|---|
| `POST /api/auth/register` | Público; rol `pyme` o `inversionista` | `201`, usuario creado. |
| `POST /api/auth/login` | Público; cuenta activa | `200`, token y usuario. |
| `GET /api/usuarios/me` | JWT de cualquier rol activo | `200`, perfil propio. |
| `PUT /api/usuarios/me` | JWT de cualquier rol activo | `200`, perfil actualizado. |
| `GET /api/usuarios` | Administrador activo | `200`, página de perfiles públicos. |
| `GET /api/usuarios/{id}` | Administrador activo | `200`, perfil público y ETag. |
| `PATCH /api/usuarios/{id}` | Administrador activo y revisión actual | `200`, rol/estado actualizados y nuevo ETag. |

Enviar `Content-Type: application/json` en solicitudes con cuerpo. Todos los campos de entrada son obligatorios y se rechazan campos adicionales. Las respuestas del módulo llevan `Cache-Control: no-store`.

## Registro

Solicitud ficticia:

```json
{
  "nombre": "Usuario de ejemplo",
  "correo": "demo@example.test",
  "password": "Ejemplo-Ficticio-2026!",
  "rol": "pyme"
}
```

La contraseña del ejemplo no es una credencial real ni debe reutilizarse para cuentas de prueba. Generar una propia al registrar.

Respuesta `201` de ejemplo; las fechas las asigna el servidor:

```json
{
  "id": "usuario:63eb9cd45e0f3a8f895141aeac8810840bc12ae3d939b752766b7ea52bff76f9",
  "nombre": "Usuario de ejemplo",
  "correo": "demo@example.test",
  "rol": "pyme",
  "estado": "activo",
  "fecha_creacion": "2026-10-09T18:00:00Z",
  "fecha_actualizacion": "2026-10-09T18:00:00Z"
}
```

- `nombre`: se recortan espacios externos; debe quedar no vacío, sin caracteres de control y con máximo 250 bytes.
- `correo`: formato ASCII de correo con dominio de al menos dos partes, máximo 254 bytes; se recortan espacios externos y se convierte a minúsculas ASCII.
- `password`: 12–128 caracteres, máximo 512 bytes, sin caracteres de control y con al menos tres categorías entre minúsculas, mayúsculas, números y símbolos.
- `rol`: solo `pyme` o `inversionista`. `administrador` produce `400` en registro público.

El servidor asigna `activo`, fechas e ID derivado del correo normalizado. Este ID evita duplicados concurrentes de registros de la API. La contraseña se guarda con Argon2id y sal aleatoria; las respuestas nunca incluyen contraseña, hash ni `_rev`.

## Login

`POST /api/auth/login` recibe únicamente:

```json
{"correo":"demo@example.test","password":"Ejemplo-Ficticio-2026!"}
```

Respuesta `200` de ejemplo. `access_token` contiene aquí un marcador, no un JWT; `expires_in` es 3600 por defecto y depende de `JWT_TTL_SECONDS`:

```json
{
  "access_token": "<valor recibido al iniciar sesión>",
  "token_type": "Bearer",
  "expires_in": 3600,
  "usuario": {
    "id": "usuario:63eb9cd45e0f3a8f895141aeac8810840bc12ae3d939b752766b7ea52bff76f9",
    "nombre": "Usuario de ejemplo",
    "correo": "demo@example.test",
    "rol": "pyme",
    "estado": "activo",
    "fecha_creacion": "2026-10-09T18:00:00Z",
    "fecha_actualizacion": "2026-10-09T18:00:00Z"
  }
}
```

Credenciales incorrectas o cuenta inactiva producen `401` con `{"error":"Credenciales incorrectas"}`. El JWT usa HS256 y expiración; se verifican firma, algoritmo, emisor, audiencia y tiempos. Cada solicitud protegida consulta el estado y rol actuales del usuario en CouchDB.

## Perfil

Enviar `Authorization: Bearer <valor recibido al iniciar sesión>` en GET y PUT `/api/usuarios/me`. GET devuelve el mismo objeto público del registro, con valores actuales. PUT admite solo:

```json
{"nombre":"Nombre ficticio actualizado"}
```

Devuelve `200` con ese objeto público, nombre actualizado y nueva `fecha_actualizacion`. Conserva ID, correo, rol, estado y fecha de creación. Esta ruta propia no permite cambiar correo, contraseña, rol o estado ni consultar perfiles ajenos. No existen rutas de logout, renovación o restablecimiento de contraseña en este módulo.

Flutter permite editar el nombre desde Mi cuenta. Mientras el PUT está pendiente, el diálogo no se puede descartar y un segundo guardado produce un error explícito. La edición normal mantiene el token y la navegación. Si el servidor devuelve un rol diferente porque cambió desde otra cuenta, se invalidan los proveedores y rutas con los permisos anteriores, conservando el token vigente.

## Gestión administrativa de usuarios

GET /api/usuarios admite limit entre 1 y 100 (25 por defecto) y bookmark opaco de hasta 8192 bytes. Responde con usuarios, bookmark y limit. El listado solicita a CouchDB únicamente campos públicos: no solicita ni devuelve hashes, contraseñas o revisiones. Una página vacía con un cursor nuevo válido permite continuar; no usar el tamaño de una página corta como señal de fin.

Para cambiar permisos, consultar GET /api/usuarios/{id}, conservar su cabecera ETag y enviar:

```http
PATCH /api/usuarios/{id}
Authorization: Bearer <token_administrador>
If-Match: "revision-recibida-en-el-GET"
Content-Type: application/json
```

```json
{"rol":"inversionista","estado":"activo"}
```

Solo se admiten rol (pyme, inversionista o administrador) y estado (activo o inactivo), ambos obligatorios. El administrador no puede desactivar su propia cuenta ni reducir su propio rol. Se conservan ID, nombre, correo, hash, fecha de creación y propiedades internas ajenas al cambio.

Falta de If-Match produce 428; una etiqueta débil, lista o comodín produce 400; una revisión obsoleta produce 412; una carrera durante el guardado produce 409 sin sobrescribir ni reintentar automáticamente. Ante 409/412, la pantalla muestra el conflicto y exige consultar los datos actuales antes de guardar otra vez. Los cambios se confirman explícitamente en la interfaz.

El rol y estado nuevos se aplican a las solicitudes siguientes, incluso con un JWT emitido antes del cambio: el servidor vuelve a consultar la cuenta en cada operación protegida. No se incluyen roles confiados al cliente dentro del JWT.

## Errores

El cuerpo de error es `{"error":"mensaje"}`.

| HTTP | Motivo |
|---|---|
| `400` | JSON, campos, nombre, correo, contraseña o rol de registro inválidos. |
| `401` | Credenciales incorrectas; JWT ausente, inválido o vencido; cuenta inactiva. Incluye `WWW-Authenticate: Bearer`. |
| `403` | Permisos insuficientes al reutilizar la autorización por rol en operaciones protegidas. |
| `404` | Usuario inexistente durante una operación; en autenticación se convierte a `401`. |
| `409` | Correo registrado o conflicto de revisión al guardar perfil. |
| `412` | La revisión del usuario cambió; consultar el perfil administrativo de nuevo. |
| `428` | Falta If-Match al modificar permisos. |
| `429` | Límite de intentos/capacidad de hashing; incluye `Retry-After: 60`. |
| `500` | Error interno del servicio. |
| `502` | Respuesta incompatible de CouchDB. |
| `503` | Servicio/configuración de usuarios o conexión no disponible. |

Registro y login tienen límites en memoria: cinco intentos por operación y correo, y cien solicitudes combinadas por minuto, además de capacidad limitada para Argon2id. Son controles del prototipo, no límites distribuidos.

## Cuenta administradora de prueba

1. Obtener autorización del responsable del entorno local y registrar una cuenta ficticia nueva como `pyme`, con correo único `example.test` y contraseña aleatoria conservada fuera del repositorio.
2. Si todavía no existe ninguna cuenta administradora, un operador autorizado con acceso a Fauxton puede comprobar el ID recién creado y cambiar únicamente su rol a administrador, guardando con la revisión actual. No modificar hash, contraseña, estado ni otras cuentas. Esta preparación inicial es manual. Si ya existe un administrador, puede asignar el rol desde Usuarios y permisos, sin editar CouchDB directamente.
3. Iniciar sesión con esa cuenta y comprobar su rol mediante `/api/usuarios/me`. Sin autorización para cambiar el rol, detener la preparación y pedirla.

No publicar credenciales, hashes, documentos completos de usuarios ni JWT. Usar solo empresas ficticias nuevas para las pruebas administrativas.

## Integración con Flutter Desktop

Usar `http://127.0.0.1:3000` si Flutter y Rust se ejecutan en el mismo equipo. Registro no inicia sesión: después llamar a login, tomar `access_token` y consultar `/api/usuarios/me`. Enviar JSON con `Content-Type: application/json` y JWT en `Authorization: Bearer ...` para perfil y [Empresas](empresas.md).

El cliente actual mantiene el token exclusivamente en memoria: no lo persiste en su archivo cifrado ni en la cola de cambios. No escribir tokens o contraseñas en logs, archivos de configuración ni preferencias. Al cerrar sesión se eliminan también instantáneas y pendientes del contexto anterior; el backend no revoca el JWT y puede seguir válido hasta expirar. Ante 401, limpiar la sesión y pedir login; ante 403, mostrar falta de permisos sin usar datos guardados como sustituto. Respetar Retry-After en 429 y distinguir validación, conflicto y disponibilidad. No conectar Flutter directamente a CouchDB ni darle sus credenciales. Ver [Modo local](../integracion/offline_windows.md).

Flutter Web necesita CORS por separado: origen permitido, métodos usados, cabeceras `Content-Type`, `Authorization`, `If-Match` y exposición de `ETag`. El backend actual no configura CORS. HTTP y escucha local corresponden al prototipo; un despliegue remoto requiere HTTPS y configuración de red propia.

## Fin de paginación

Conservar los filtros y el límite al continuar. Terminar cuando bookmark sea una cadena vacía o se repita un cursor ya recibido. Una página corta o vacía con un cursor nuevo válido permite continuar. La API representa la ausencia de cursor como una cadena vacía; el sentinel interno nil de CouchDB no se devuelve como cursor público.

## Espera ante demasiados intentos

Al recibir HTTP 429, Flutter conserva Retry-After (segundos o fecha HTTP), bloquea los envíos de login y registro y muestra una cuenta regresiva. La espera se comparte entre ambos formularios durante la ejecución. Si la cabecera falta o es inválida se aplican 60 segundos. Los datos del formulario se conservan y el botón se habilita al finalizar.
