# Empresas

El módulo utiliza la base CouchDB `empresas`. Todas sus rutas requieren JWT mediante `Authorization: Bearer <token>`.

La estructura de los documentos, los campos obligatorios y opcionales y un ejemplo están en [la documentación de la base empresas](../../database/empresas/README.md).

Una PYME registra empresas y consulta, actualiza o desactiva únicamente las propias. El responsable se asigna desde el usuario autenticado; no se acepta en el JSON. Los administradores pueden consultar y administrar empresas. Los inversionistas no tienen acceso a estas operaciones.

| Método y ruta | Operación |
|---|---|
| `POST /api/empresas` | Registrar en estado `pendiente` (PYME). |
| `GET /api/empresas?limit=10&bookmark=...` | Listar; una PYME recibe solo sus empresas. |
| `GET /api/empresas/{id}` | Consultar y obtener la revisión real en el encabezado `ETag`. |
| `PUT /api/empresas/{id}` | Actualizar nombre, NIT, correo, teléfono y dirección. |
| `PATCH /api/empresas/{id}/desactivar` | Pasar a `inactiva`, sin borrar el documento. |
| `PATCH /api/empresas/{id}/aprobar` | Pasar de `pendiente` a `activa` (administrador). |
| `PATCH /api/empresas/{id}/rechazar` | Pasar de `pendiente` a `rechazada` (administrador). |

Para aprobar o rechazar, consultar primero la empresa y enviar el ETag completo en `If-Match`, por ejemplo `If-Match: "1-revision"`. No se necesita cuerpo JSON. La respuesta exitosa incluye el nuevo ETag. Repetir la misma decisión no escribe de nuevo cuando el estado y la revisión coinciden.

Si una edición cambia efectivamente los datos de una empresa activa o rechazada, vuelve a `pendiente` en la misma escritura. Enviar datos iguales, después de normalizarlos, no cambia estado, fechas ni revisión. Las empresas inactivas pueden editarse según permisos, pero siguen inactivas y no pueden aprobarse, rechazarse ni reactivarse.

Los documentos sin responsable no pueden aprobarse ni rechazarse. No se migran automáticamente. Estas decisiones son una revisión interna; no certifican validación tributaria ni DTE.

Errores principales: `401` por autenticación inválida, `403` por rol sin permisos, `404` por empresa inexistente o ajena a una PYME, `400` por If-Match mal formado, `428` si falta If-Match, `412` si la revisión está obsoleta y `409` por transición inválida o conflicto concurrente de CouchDB. Ante un conflicto, consultar de nuevo antes de decidir; el backend no sobrescribe mediante reintentos automáticos.

El backend crea la base y los índices `empresas-nit/por-nit` y `empresas-responsable/por-responsable` al iniciar.
