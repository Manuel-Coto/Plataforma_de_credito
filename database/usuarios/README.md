# Base de datos: usuarios

La base `usuarios` guarda las cuentas, sus roles y los hashes de contraseña usados para iniciar sesión.

## Campos del documento

| Campo | Tipo en JSON | Obligatorio u opcional |
|---|---|---|
| `_id` | Cadena | Obligatorio; el backend lo calcula a partir del correo normalizado. |
| `_rev` | Cadena | Se omite al crear; CouchDB lo genera y se necesita para actualizar. |
| `nombre` | Cadena | Obligatorio. |
| `correo` | Cadena | Obligatorio; se guarda sin espacios externos y en minúsculas ASCII. |
| `password_hash` | Cadena | Obligatorio; hash Argon2id, nunca contraseña en texto plano. |
| `rol` | Cadena | Obligatorio: `pyme`, `inversionista` o `administrador`. |
| `estado` | Cadena | Obligatorio: `activo` o `inactivo`. |
| `fecha_creacion` | Fecha UTC en cadena | Obligatorio. |
| `fecha_actualizacion` | Fecha UTC en cadena | Obligatorio. |

El backend asigna `activo` al registrar una cuenta. Las respuestas públicas muestran `id` en lugar de `_id` y no incluyen `_rev` ni `password_hash`.

## Ejemplo ficticio

Documento de una cuenta con correo `demo@example.test`, antes de que CouchDB asigne la revisión. El hash está abreviado para el ejemplo; el backend guarda la cadena PHC completa.

```json
{
  "_id": "usuario:63eb9cd45e0f3a8f895141aeac8810840bc12ae3d939b752766b7ea52bff76f9",
  "nombre": "Usuario ficticio",
  "correo": "demo@example.test",
  "password_hash": "$argon2id$v=19$m=19456,t=2,p=1$SAL$HASH",
  "rol": "pyme",
  "estado": "activo",
  "fecha_creacion": "2026-10-09T18:00:00Z",
  "fecha_actualizacion": "2026-10-09T18:00:00Z"
}
```

## Índice Mango

| Documento de diseño | Nombre | Campos | Tipo |
|---|---|---|---|
| `usuarios-correo` | `por-correo` | `correo` | `json` |

La definición está en [indexes/por_correo.json](indexes/por_correo.json). El índice permite consultar cuentas por correo, pero no impone unicidad.

Para evitar registros concurrentes del mismo correo, el backend usa `usuario:<SHA-256 del correo normalizado>` como ID y crea el documento sin `_rev`. Dos registros de la API con el mismo correo compiten por el mismo documento. El correo no se modifica desde el perfil.

El backend Rust crea la base y el índice al iniciar. Si ya existen, continúa sin borrarlos ni reemplazar documentos de usuarios.