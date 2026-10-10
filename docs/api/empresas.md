# Empresas

URL local: `http://127.0.0.1:3000`. Todas las rutas requieren `Authorization: Bearer <valor recibido al iniciar sesión>`. El backend crea la base `empresas` y los índices `empresas-nit/por-nit` y `empresas-responsable/por-responsable` al iniciar; si existen, continúa sin borrarlos. La estructura interna está en [la documentación de empresas](../../database/empresas/README.md).

## Rutas y permisos

| Método y ruta | PYME | Administrador | Respuesta exitosa |
|---|---|---|---|
| `POST /api/empresas` | Crear para sí misma | No permitido | `201`, empresa. |
| `GET /api/empresas` | Solo sus empresas | Todas | `200`, página. |
| `GET /api/empresas/{id}` | Solo propia | Cualquiera | `200`, empresa y ETag. |
| `PUT /api/empresas/{id}` | Solo propia | Cualquiera | `200`, empresa. |
| `PATCH /api/empresas/{id}/desactivar` | Solo propia | Cualquiera | `200`, empresa. |
| `PATCH /api/empresas/{id}/aprobar` | No permitido | Según estado y revisión | `200`, empresa y ETag. |
| `PATCH /api/empresas/{id}/rechazar` | No permitido | Según estado y revisión | `200`, empresa y ETag. |

Los inversionistas no tienen acceso a estas operaciones (`403`). Una PYME que consulta, edita o desactiva una empresa ajena recibe `404`; el listado se filtra por responsable incluso con bookmarks. Los documentos antiguos sin responsable no son accesibles para PYMEs y no se migran automáticamente.

## Crear y editar

POST y PUT reciben los mismos cinco campos obligatorios, todos cadenas. PUT no es una actualización parcial. Enviar `Content-Type: application/json`:

```json
{
  "nombre": "Empresa ficticia",
  "nit": "NIT-FICTICIO-001",
  "correo": "contacto@example.test",
  "telefono": "0000-0000",
  "direccion": "Dirección ficticia"
}
```

Se recortan espacios externos. Nombre y NIT deben quedar no vacíos, con máximos de 250 y 64 bytes. Correo debe tener formato ASCII válido con dominio de al menos dos partes y máximo 254 bytes. Teléfono y dirección deben estar presentes, pero pueden ser cadenas vacías; sus máximos son 50 y 1000 bytes. El correo de contacto no se convierte a minúsculas. El NIT se compara tal como queda tras recortar espacios; no hay validación tributaria oficial ni garantía de unicidad bajo registros concurrentes.

Se rechazan campos adicionales, incluidos `id`, `_id`, `_rev`, `estado`, `usuario_responsable_id` y fechas. En POST el servidor asigna responsable desde la PYME autenticada, estado `pendiente`, ID y fechas.

Respuesta `201` de POST; ID y fechas son ilustrativos y deben tomarse de la respuesta real:

```json
{
  "id": "empresa_ficticia_001",
  "nombre": "Empresa ficticia",
  "nit": "NIT-FICTICIO-001",
  "correo": "contacto@example.test",
  "telefono": "0000-0000",
  "direccion": "Dirección ficticia",
  "estado": "pendiente",
  "usuario_responsable_id": "usuario:63eb9cd45e0f3a8f895141aeac8810840bc12ae3d939b752766b7ea52bff76f9",
  "fecha_creacion": "2026-10-09T18:00:00Z",
  "fecha_actualizacion": "2026-10-09T18:00:00Z"
}
```

Para editar, enviar ese cuerpo de cinco campos a `PUT /api/empresas/{id}`. Devuelve `200` con el mismo objeto público y los datos actuales. Conserva ID, responsable y fecha de creación. Una edición efectiva de una empresa `activa` o `rechazada` la devuelve a `pendiente` en la misma escritura; datos iguales después de normalizarlos no cambian estado, fechas ni revisión. Una empresa `inactiva` sigue inactiva aunque se edite. PUT no exige If-Match ni entrega ETag; CouchDB puede responder con conflicto concurrente (`409`).

## Listado paginado

Primera solicitud: `GET /api/empresas?limit=10`. El límite predeterminado es 25 y admite 1–100. Solo se aceptan `limit` y `bookmark`. Se ordena por NIT ascendente; para una PYME la consulta incluye su responsable.

Respuesta `200` de ejemplo:

```json
{
  "empresas": [
    {
      "id": "empresa_ficticia_001",
      "nombre": "Empresa ficticia",
      "nit": "NIT-FICTICIO-001",
      "correo": "contacto@example.test",
      "telefono": "0000-0000",
      "direccion": "Dirección ficticia",
      "estado": "pendiente",
      "usuario_responsable_id": "usuario:63eb9cd45e0f3a8f895141aeac8810840bc12ae3d939b752766b7ea52bff76f9",
      "fecha_creacion": "2026-10-09T18:00:00Z",
      "fecha_actualizacion": "2026-10-09T18:00:00Z"
    }
  ],
  "bookmark": "<valor opaco devuelto por CouchDB>",
  "limit": 10
}
```

El bookmark del ejemplo es un marcador. Para continuar, enviar el valor real codificado como parámetro URL: `GET /api/empresas?limit=10&bookmark=...`. No interpretarlo ni compartirlo entre sesiones; mantener el mismo límite. Se admiten hasta 8192 bytes. Una página vacía indica fin de recorrido; el bookmark no es un número de página. No hay filtro de estado en esta API: el listado también incluye empresas rechazadas e inactivas según permisos.

## Consulta y revisión administrativa

`GET /api/empresas/{id}` devuelve `200` con el objeto empresa mostrado arriba, sus valores actuales, `Cache-Control: no-store` y ETag con la revisión real. `_rev` no aparece en el JSON. Fechas y responsable pueden ser `null` en documentos antiguos; correo, teléfono o dirección ausentes se leen como `""` y estado ausente como `pendiente`.

Para decidir, el administrador debe consultar primero la empresa y copiar el ETag completo, incluidas las comillas. Ejemplo ficticio de cabecera:

```http
ETag: "1-0123456789abcdef0123456789abcdef"
```

Enviar una de estas solicitudes, sin cuerpo JSON:

```http
PATCH /api/empresas/{id}/aprobar
If-Match: "1-0123456789abcdef0123456789abcdef"
```

```http
PATCH /api/empresas/{id}/rechazar
If-Match: "1-0123456789abcdef0123456789abcdef"
```

Ambas llevan también la cabecera Authorization. If-Match debe ser un único ETag fuerte entre comillas; no se aceptan `*`, etiquetas débiles (`W/`) ni listas. Usar siempre la cabecera HTTP del GET, no una revisión inventada o consultada directamente en CouchDB.

La respuesta `200` mantiene la estructura completa de empresa del ejemplo: aprobación cambia `estado` a `activa`, rechazo a `rechazada`, y ambos actualizan `fecha_actualizacion` y entregan el nuevo ETag. Se conservan responsable, ID, fecha de creación y demás datos. Propiedades adicionales de CouchDB se conservan internamente pero no aparecen en la respuesta pública.

| Estado actual | Acción | Resultado |
|---|---|---|
| `pendiente` con responsable no vacío | Aprobar / rechazar | `activa` / `rechazada`. |
| `activa` | Aprobar otra vez con revisión actual | `200`, sin nueva escritura. |
| `rechazada` | Rechazar otra vez con revisión actual | `200`, sin nueva escritura. |
| `activa` / `rechazada` | Decisión contraria | `409`; primero deben editarse efectivamente y volver a pendiente. |
| `inactiva` o cualquier estado sin responsable válido | Aprobar / rechazar | `409`. |

Una revisión obsoleta siempre produce `412`, incluso si la decisión ya coincide. Una carrera al guardar produce `409` sin sobrescribir ni reintentar automáticamente. Estas decisiones son revisión interna; no certifican validación tributaria ni DTE.

## Desactivar

`PATCH /api/empresas/{id}/desactivar` no necesita cuerpo ni If-Match. Devuelve `200` con el objeto público de empresa, `estado: "inactiva"` y fecha de actualización renovada. Si ya estaba inactiva, devuelve `200` sin escribir de nuevo. No elimina el documento y no existe endpoint para reactivarlo.

## Errores e integración con Flutter

El cuerpo de error es `{"error":"mensaje"}`; por ejemplo, una PYME que intenta aprobar recibe `403` con `{"error":"Permisos insuficientes"}`.

| HTTP | Motivo / acción del cliente |
|---|---|
| `400` | JSON, campos, paginación, ID o If-Match inválidos; corregir solicitud. |
| `401` | JWT ausente, inválido, vencido o usuario inactivo; volver a login. |
| `403` | Rol sin permisos; no repetir como si fuera error de conexión. |
| `404` | Empresa inexistente o ajena a la PYME. |
| `409` | NIT duplicado, transición inválida o conflicto concurrente; revisar mensaje y consultar de nuevo. |
| `412` | If-Match obsoleto; obtener datos y ETag nuevos antes de decidir. |
| `428` | Falta If-Match en aprobación/rechazo. |
| `502` | Respuesta/documento de CouchDB incompatible. |
| `503` | Servicio, conexión, configuración o índice no disponible. |

En Flutter Desktop usar la URL local y el flujo de token descrito en [Usuarios](usuarios.md#integración-con-flutter-desktop). Guardar el ETag del GET junto a la empresa y reemplazarlo con el recibido después de una decisión. No quitar comillas ni usar la fecha como revisión. Tras editar, consultar nuevamente antes de revisar. Adaptar la interfaz al rol, aunque el backend sigue comprobando los permisos. Flutter Web requiere configurar CORS por separado para enviar If-Match y leer ETag.
