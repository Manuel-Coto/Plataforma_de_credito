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
| `usuario_responsable_id` | Cadena o `null` | Opcional; referencia al usuario responsable. |
| `fecha_creacion` | Fecha UTC en cadena o `null` | Opcional para documentos antiguos. |
| `fecha_actualizacion` | Fecha UTC en cadena o `null` | Opcional para documentos antiguos. |

Los registros nuevos incluyen correo, teléfono, dirección y fechas. El backend asigna el estado inicial `pendiente`. En las respuestas públicas, `_id` se muestra como `id` y `_rev` no se incluye.

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
  "usuario_responsable_id": null,
  "fecha_creacion": "2026-10-09T18:00:00Z",
  "fecha_actualizacion": "2026-10-09T18:00:00Z"
}
```

## Índice Mango

| Documento de diseño | Nombre | Campos | Tipo |
|---|---|---|---|
| `empresas-nit` | `por-nit` | `nit` | `json` |

La definición está en [indexes/por_nit.json](indexes/por_nit.json). Permite buscar y ordenar por NIT. El índice no impone unicidad; el backend comprueba los duplicados secuenciales.

El backend Rust crea la base y el índice al iniciar. Si ya existen, continúa sin borrarlos ni reemplazar documentos de empresas.