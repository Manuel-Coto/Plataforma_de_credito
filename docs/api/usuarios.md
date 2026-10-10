# Usuarios y autenticación

URL local: `http://127.0.0.1:3000`. El backend crea la base `usuarios` y el índice `usuarios-correo/por-correo` al iniciar; si existen, continúa sin borrarlos. La estructura interna está en [la documentación de usuarios](../../database/usuarios/README.md).

## Rutas

| Método y ruta | Acceso | Respuesta exitosa |
|---|---|---|
| `POST /api/auth/register` | Público; rol `pyme` o `inversionista` | `201`, usuario creado. |
| `POST /api/auth/login` | Público; cuenta activa | `200`, token y usuario. |
| `GET /api/usuarios/me` | JWT de cualquier rol activo | `200`, perfil propio. |
| `PUT /api/usuarios/me` | JWT de cualquier rol activo | `200`, perfil actualizado. |

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

Devuelve `200` con ese objeto público, nombre actualizado y nueva `fecha_actualizacion`. Conserva ID, correo, rol, estado y fecha de creación. No permite cambiar correo, contraseña, rol o estado ni consultar perfiles ajenos. No existen rutas de logout, renovación o restablecimiento de contraseña en este módulo.

## Errores

El cuerpo de error es `{"error":"mensaje"}`.

| HTTP | Motivo |
|---|---|
| `400` | JSON, campos, nombre, correo, contraseña o rol de registro inválidos. |
| `401` | Credenciales incorrectas; JWT ausente, inválido o vencido; cuenta inactiva. Incluye `WWW-Authenticate: Bearer`. |
| `403` | Permisos insuficientes al reutilizar la autorización por rol en operaciones protegidas. |
| `404` | Usuario inexistente durante una operación; en autenticación se convierte a `401`. |
| `409` | Correo registrado o conflicto de revisión al guardar perfil. |
| `429` | Límite de intentos/capacidad de hashing; incluye `Retry-After: 60`. |
| `500` | Error interno del servicio. |
| `502` | Respuesta incompatible de CouchDB. |
| `503` | Servicio/configuración de usuarios o conexión no disponible. |

Registro y login tienen límites en memoria: cinco intentos por operación y correo, y cien solicitudes combinadas por minuto, además de capacidad limitada para Argon2id. Son controles del prototipo, no límites distribuidos.

## Cuenta administradora de prueba

1. Obtener autorización del responsable del entorno local y registrar una cuenta ficticia nueva como `pyme`, con correo único `example.test` y contraseña aleatoria conservada fuera del repositorio.
2. Un operador autorizado con acceso a Fauxton puede comprobar el ID recién creado y cambiar únicamente su `rol` a `administrador`, guardando con la revisión actual. No modificar hash, contraseña, estado ni otras cuentas. Es preparación manual, no un endpoint de la API.
3. Iniciar sesión con esa cuenta y comprobar su rol mediante `/api/usuarios/me`. Sin autorización para cambiar el rol, detener la preparación y pedirla.

No publicar credenciales, hashes, documentos completos de usuarios ni JWT. Usar solo empresas ficticias nuevas para las pruebas administrativas.

## Integración con Flutter Desktop

Usar `http://127.0.0.1:3000` si Flutter y Rust se ejecutan en el mismo equipo. Registro no inicia sesión: después llamar a login, tomar `access_token` y consultar `/api/usuarios/me`. Enviar JSON con `Content-Type: application/json` y JWT en `Authorization: Bearer ...` para perfil y [Empresas](empresas.md).

Mantener el token en memoria durante la sesión; si se necesita persistencia, usar almacenamiento seguro del sistema operativo. No escribir token o contraseña en logs, archivos de configuración ni preferencias en texto plano. Al cerrar sesión, borrarlo del cliente; el backend no lo revoca y puede seguir válido hasta expirar. Ante `401`, limpiar la sesión y pedir login; ante `403`, mostrar falta de permisos. Respetar `Retry-After` en `429` y distinguir validación, conflicto y disponibilidad. No conectar Flutter directamente a CouchDB ni darle sus credenciales.

Flutter Web necesita CORS por separado: origen permitido, métodos usados, cabeceras `Content-Type`, `Authorization`, `If-Match` y exposición de `ETag`. El backend actual no configura CORS. HTTP y escucha local corresponden al prototipo; un despliegue remoto requiere HTTPS y configuración de red propia.
