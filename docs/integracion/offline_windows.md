# Trabajo local sin conexión en Windows

El modo local es una caché de lecturas y una cola limitada del cliente Flutter. La API sigue aplicando la autorización y las reglas al sincronizar. No es replicación de CouchDB, no elimina la necesidad de iniciar sesión y no convierte un cambio pendiente en uno aceptado por el servidor.

## Sesión y aislamiento

Cada ejecución requiere un login inicial en línea. El JWT permanece en memoria: no se guarda en instantáneas, solicitudes pendientes, preferencias ni archivos. Los datos se separan por URL de API, ID de usuario y rol.

Cerrar la aplicación conserva el archivo cifrado, pero volver a acceder requiere autenticación en línea. El cierre manual de sesión avisa antes de descartar pendientes. Recibir 401, caducar la sesión, cambiar de cuenta o cambiar de rol purga automáticamente los datos y solicitudes del contexto anterior; la interfaz informa el estado resultante, sin una aprobación previa para esas purgas de seguridad. Los pendientes no son un respaldo independiente de la sesión.

## Lecturas guardadas

Los GET protegidos bajo /api, excepto autenticación, pueden conservar su JSON y ETag. Solo se usa una instantánea ante error de transporte, timeout o indisponibilidad 503. Un 401/403, una respuesta inválida o un error de validación no se sustituye por un éxito local.

Una instantánea muestra la última información obtenida; puede estar desactualizada. No acredita que una empresa siga activa ni que una oferta conserve saldo. Las decisiones sensibles y sus precondiciones se comprueban otra vez en el servidor.

## Solicitudes que pueden quedar pendientes

| Operación | Condición y protección |
|---|---|
| POST /api/empresas | Cinco campos de empresa, Idempotency-Key estable y cuerpo inmutable. |
| POST /api/facturas | Siete campos del formulario, Idempotency-Key estable y cuerpo inmutable. |
| PUT /api/empresas/{id} | Cuerpo completo de cinco campos e If-Match fuerte observado previamente. |

La intención se persiste cifrada antes del primer envío para poder recuperar una respuesta perdida. La cola no guarda contraseñas, JWT ni cabeceras Authorization. Al enviar utiliza la sesión activa validada en línea.

Los cambios de perfil, roles, estados de usuario, aprobación/rechazo/desactivación de empresas, verificación de DTE, publicación de ofertas, aportes, confirmaciones, emisión de créditos, pagos y reintentos administrativos no se encolan. Requieren conexión.

La lista local de pendientes no crea empresas o facturas falsas en los resultados del servidor. Confirmar una operación pendiente sigue requiriendo respuesta válida de la API.

## Sincronización y conflictos

La sincronización es explícita. Primero verifica el perfil en línea y después intenta una vez cada operación elegible por acción del usuario. Existe un máximo persistido de tres intentos por operación; no hay un bucle de reintentos ilimitado en segundo plano.

- Un éxito elimina el pendiente y actualiza el estado local correspondiente.
- Un 409 o 412 se presenta como conflicto y no se reenvía automáticamente.
- Otros errores permanentes conservan el pendiente con su explicación; no se transforman en éxito ni se repiten como si fueran desconexiones.
- En un PUT en conflicto se debe consultar la empresa en línea, comparar el contenido y confirmar expresamente la resolución usando el nuevo ETag observado.
- Un POST en conflicto no se transforma en una nueva creación con otra clave. Puede descartarse explícitamente.
- Los pendientes se pueden descartar desde la interfaz. Purga de sesión y descarte son acciones diferentes de una sincronización exitosa.

## Cifrado y límites

La persistencia usa DPAPI con alcance CurrentUser de Windows. El archivo se cifra para la cuenta de Windows; copiarlo a otra cuenta o equipo no ofrece una recuperación portable. No se utiliza cifrado ficticio ni un archivo JSON en texto plano como alternativa cuando DPAPI falla.

El presupuesto del almacenamiento es 12 MiB y el de la cola 8 MiB. Una indisponibilidad, corrupción o límite debe presentarse al usuario; no se promete guardar cambios que no se pudieron persistir.

Este alcance es específico de Windows. No demuestra soporte offline en Web, Android, macOS o Linux ni recuperación tras pérdida del perfil de Windows. Tampoco incluye replicación, conciliación de fondos reales o sincronización automática de toda la base.

## Verificación

El 8 de noviembre de 2026 se aprobaron las 14 pruebas de `test/offline_core_test.dart` en Windows. Incluyeron DPAPI real: archivo cifrado sin contenido legible, reapertura y reemplazo, además de recuperación de pendientes, aislamiento, permisos y concurrencia. Desde `Frontend/plataforma_credito` se ejecutan con `flutter test --no-pub test/offline_core_test.dart`.

Las pruebas unitarias y de interfaz usan transporte y persistencia controlados para comprobar caché, permisos, conflictos, reintentos, purgas y avisos. La comprobación real de DPAPI debe ejecutarse en Windows. El [recorrido CouchDB real](couchdb_real.md) verifica los endpoints e idempotencia de la API en seis bases aisladas; no acredita por sí solo la persistencia DPAPI del cliente.

## Verificación actualizada: 9 de noviembre de 2026

La suite completa Flutter terminó con 98 pruebas aprobadas y flutter analyze sin incidencias. Incluye DPAPI nativo en un isolate, cargas desde 1 KiB hasta 12 MiB y compatibilidad bidireccional con el formato previo de PowerShell. También se verificaron los botones de login/registro y el bloqueo compartido por Retry-After. Esta evidencia automatizada no acredita una pasada manual completa de todas las pantallas.
