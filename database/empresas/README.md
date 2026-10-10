# Base de datos: empresas

La base `empresas` guarda los datos de contacto, el NIT y el estado de las empresas registradas.

## Campos del documento

| Campo | Tipo en JSON | Obligatorio u opcional |
|---|---|---|
| `_id` | Cadena | CouchDB lo genera al crear el documento. Identifica la empresa. |
| `_rev` | Cadena | CouchDB lo genera al guardar; se necesita para actualizar. |
| `nombre` | Cadena | Obligatorio. |
| `nit` | Cadena | Obligatorio. |
| `correo` | Cadena | Puede faltar en documentos antiguos; se lee como `""`. |
| `telefono` | Cadena | Puede faltar en documentos antiguos; se lee como `""`. |
| `direccion` | Cadena | Puede faltar en documentos antiguos; se lee como `""`. |
| `estado` | Cadena | Si falta, se lee como `pendiente`. Valores: `pendiente`, `activa`, `rechazada`, `inactiva`. |
| `usuario_responsable_id` | Cadena o `null` | Puede faltar en documentos antiguos. En nuevos registros lo asigna el backend con el ID de la PYME autenticada. |
| `fecha_creacion` | Fecha UTC en cadena o `null` | Opcional para documentos antiguos. |
| `fecha_actualizacion` | Fecha UTC en cadena o `null` | Opcional para documentos antiguos. |

Los registros nuevos incluyen correo, teléfono, dirección, responsable y fechas. El backend asigna el estado inicial `pendiente`. En las respuestas públicas, `_id` se muestra como `id` y `_rev` no se incluye en el JSON; la consulta individual entrega esa revisión como `ETag`.

## Ejemplo ficticio

Documento al crearse, antes de que CouchDB asigne la revisión:

```json
{
  "_id": "empresa_ejemplo_001",
  "nombre": "Empresa ficticia",
  "nit": "NIT-FICTICIO-001",
  "correo": "contacto@example.test",
  "telefono": "0000-0000",
  "direccion": "Dirección ficticia",
  "estado": "pendiente",
  "usuario_responsable_id": "usuario_pyme_ficticio",
  "fecha_creacion": "2026-10-09T18:00:00Z",
  "fecha_actualizacion": "2026-10-09T18:00:00Z"
}
```

## Índices Mango

| Documento de diseño | Nombre | Campos | Tipo |
|---|---|---|---|
| `empresas-nit` | `por-nit` | `nit` | `json` |
| `empresas-responsable` | `por-responsable` | `usuario_responsable_id`, `nit` | `json` |

Las definiciones están en [por_nit.json](indexes/por_nit.json) y [por_responsable.json](indexes/por_responsable.json). Permiten buscar por NIT y paginar las empresas de cada responsable. Los índices no imponen unicidad; el backend comprueba los duplicados secuenciales.

El backend crea la base y ambos índices al iniciar. Si ya existen, continúa sin borrarlos ni reemplazar documentos.

Solo administradores pueden aprobar o rechazar empresas pendientes con responsable, usando `If-Match` con la revisión consultada. Una edición efectiva de datos devuelve empresas activas o rechazadas a `pendiente`; una edición idéntica no escribe. Las inactivas no se reactivan. Se conservan ID, responsable, fecha de creación y propiedades adicionales del documento. No hay migraciones automáticas ni verificación tributaria o DTE. Las rutas y errores están en [la documentación de la API](../../docs/api/empresas.md).
