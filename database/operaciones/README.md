# Base de datos CouchDB: operaciones

Contiene documentos de inversiones (`tipo: "inversion"`) y créditos (`tipo: "credito"`). Los datos permanecen en CouchDB; esta carpeta conserva la estructura de índices y su documentación. El backend crea la base y los índices al iniciar.

## Créditos y pagos simulados

Un crédito relaciona `oferta_id`, `factura_id`, `empresa_id`, `responsable_id` e `inversionistas_ids`. Guarda los importes como enteros en centavos: `capital_centavos`, `interes_centavos`, `total_centavos` y `pagado_centavos`. La tasa anual se expresa en puntos básicos (`tasa_anual_bp`, donde 100 equivale a 1 %).

El documento conserva `estado` (`activo` o `pagado`), `version`, fechas, `participaciones` y el historial `pagos`. Cada participación identifica la inversión, su propietario y los centavos de capital e interés que le corresponden. Cada pago incluye ID, referencia, monto, usuario que lo registró y fecha. El vencimiento se calcula al consultar; no requiere una tarea que cambie el estado almacenado.

El ID del crédito es determinista por factura. La creación repetida no genera otro crédito para la misma factura. La referencia de un pago es única dentro de ese crédito: repetir referencia, monto y usuario devuelve el resultado existente. Cambiar el monto o el usuario con la misma referencia produce conflicto.

El saldo y el historial de pagos se actualizan en una sola escritura con la revisión `_rev` de CouchDB. El crédito es la fuente de verdad; las actualizaciones de oferta, factura, inversiones y auditoría son escrituras posteriores que pueden reintentarse. Una respuesta con `sincronizacion_pendiente: true` confirma que el crédito o pago ya fue guardado; se debe repetir la solicitud con los mismos datos o usar la ruta administrativa de sincronización.

## Índices Mango

| Archivo | Campos | Uso |
| --- | --- | --- |
| `indexes/por_estado.json` | `tipo`, `estado`, `fecha_creacion` | Inversiones por estado. |
| `indexes/por_inversionista.json` | `tipo`, `inversionista_id`, `fecha_creacion` | Inversiones del usuario autenticado. |
| `indexes/por_oferta.json` | `tipo`, `oferta_id`, `fecha_creacion` | Aportes de una oferta; conciliación previa a crear el crédito. |
| `indexes/creditos_por_responsable.json` | `tipo`, `responsable_id`, `estado` | Créditos de la PYME responsable. |
| `indexes/creditos_por_estado.json` | `tipo`, `estado` | Listado y filtro de créditos. |

La consulta del inversionista aplica el filtro de pertenencia sobre `inversionistas_ids` además de `tipo: "credito"`. No se utiliza un índice JSON de un campo de arreglo como sustituto de la comprobación de pertenencia.

Contrato HTTP, permisos y reglas de cálculo: [API de créditos y pagos](../../docs/api/creditos.md).
