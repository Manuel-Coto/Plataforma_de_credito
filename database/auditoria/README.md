# Base de datos CouchDB: auditoria

Registra eventos del flujo de créditos y pagos simulados para su consulta administrativa. Los datos permanecen en CouchDB; esta carpeta conserva las definiciones de índices. El backend crea la base y sus índices al iniciar.

Los documentos tienen `tipo: "evento"` e incluyen el usuario que realizó la acción (`actor_id`), la acción (`accion`), el tipo e identificador del recurso afectado (`recurso_tipo`, `recurso_id`), la fecha (`fecha`) y detalles estructurados (`detalles`). Los identificadores de eventos del flujo de crédito permiten reintentar la sincronización sin duplicar su auditoría.

## Índices Mango

| Archivo | Campos | Uso |
| --- | --- | --- |
| `indexes/por_fecha.json` | `tipo`, `fecha` | Consulta de eventos. |
| `indexes/por_actor.json` | `tipo`, `actor_id` | Consulta de acciones de un usuario. |
| `indexes/por_recurso.json` | `tipo`, `recurso_id` | Consulta de eventos de un recurso. |

Las consultas requieren un usuario activo con rol de administrador. La auditoría no admite escrituras arbitrarias desde una ruta pública. Las acciones de módulos anteriores a créditos conservan su comportamiento existente; estos índices no generan un historial retroactivo.

El historial de pagos en `operaciones` es la fuente de verdad del crédito. Si una escritura de auditoría falla, la respuesta del flujo de créditos marca `sincronizacion_pendiente` para permitir la recuperación posterior.
