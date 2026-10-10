# Inversiones y ofertas de factoring

URL local: `http://127.0.0.1:3000`. Todas las rutas requieren `Authorization: Bearer <valor recibido al iniciar sesión>` y un usuario activo. El módulo utiliza las bases CouchDB `ofertas`, `operaciones` y `facturas`.

La base `ofertas` almacena las ofertas de factoring y `operaciones` almacena las inversiones registradas. La base `facturas` se consulta para comprobar que la factura relacionada puede ofrecerse para financiación. La estructura de índices se encuentra en [Ofertas](../../database/ofertas/README.md) y [Operaciones](../../database/operaciones/README.md).

## Rutas y permisos

| Método y ruta               | PYME                                 | Inversionista              | Administrador                                                                | Respuesta exitosa             |
| --------------------------- | ------------------------------------ | -------------------------- | ---------------------------------------------------------------------------- | ----------------------------- |
| `POST /api/ofertas`         | Crear oferta para una factura propia | No permitido               | No permitido                                                                 | `201`, oferta creada.         |
| `GET /api/ofertas`          | Consultar ofertas abiertas           | Consultar ofertas abiertas | Consultar ofertas abiertas                                                   | `200`, página de ofertas.     |
| `GET /api/ofertas/{id}`     | Consultar oferta                     | Consultar oferta           | Consultar oferta                                                             | `200`, oferta.                |
| `POST /api/inversiones`     | No permitido                         | Registrar inversión        | No permitido                                                                 | `201`, inversión creada.      |
| `GET /api/inversiones/mias` | No permitido                         | Consultar sus inversiones  | Permitido por rol, pero actualmente filtra por el ID del usuario autenticado | `200`, página de inversiones. |
| `GET /api/inversiones/{id}` | No permitido                         | Consultar inversión propia | Consultar cualquier inversión                                                | `200`, inversión.             |

Las rutas protegidas requieren un JWT válido. Las operaciones de creación se limitan por rol: las PYMEs publican ofertas y los inversionistas registran aportes.

**Alcance actual:** este módulo permite crear ofertas y registrar inversiones. No implementa todavía un proceso completo de pagos, liquidación, reembolso o distribución automática de rendimientos.

## Crear una oferta de factoring

`POST /api/ofertas` permite que una PYME publique una oferta asociada a una factura.

Enviar `Content-Type: application/json`:

```json
{
  "factura_id": "factura:identificador_ficticio",
  "monto_objetivo_centavos": 100000,
  "tasa_rendimiento_anual_bp": 800,
  "fecha_cierre": "2026-11-30T23:59:59Z"
}
```

Todos los campos son obligatorios y se rechazan campos adicionales.

Validaciones aplicadas:

* `factura_id`: debe ser un identificador válido.
* `monto_objetivo_centavos`: debe ser mayor que cero y representa el objetivo en centavos.
* `tasa_rendimiento_anual_bp`: tasa anual expresada en puntos básicos. `100` equivale a `1 %`; `800` equivale a `8 %`. No se admiten valores superiores a `10000` (`100 %`).
* `fecha_cierre`: fecha y hora con zona horaria; debe ser posterior al momento actual.
* La factura debe existir y haber sido creada por la PYME autenticada.
* El DTE de la factura debe estar marcado como verificado.
* La factura debe estar en estado `disponible` o `parcialmente_financiada`.
* El objetivo no puede superar el saldo elegible de la factura.
* No debe existir otra oferta para esa factura.

La oferta se crea en estado `abierta`, con moneda `USD`, monto recaudado y comprometido en cero, y fecha de apertura asignada por el servidor.

Respuesta `201` de ejemplo:

```json
{
  "id": "oferta:identificador_ficticio",
  "_id": "oferta:identificador_ficticio",
  "_rev": "1-revision_ficticia",
  "tipo": "oferta_factoring",
  "factura_id": "factura:identificador_ficticio",
  "empresa_id": "empresa_ficticia_001",
  "creador_id": "usuario:identificador_ficticio",
  "monto_objetivo_centavos": 100000,
  "monto_recaudado_centavos": 0,
  "monto_comprometido_centavos": 0,
  "moneda": "USD",
  "tasa_rendimiento_anual_bp": 800,
  "estado": "abierta",
  "fecha_apertura": "2026-10-09T18:00:00Z",
  "fecha_cierre": "2026-11-30T23:59:59Z",
  "fecha_actualizacion": null
}
```

Los identificadores, revisiones y fechas del ejemplo son ilustrativos. La respuesta actual incluye `_id` y `_rev`, campos internos de CouchDB. No utilizar la revisión como token de autenticación ni exponerla innecesariamente en la interfaz.

## Consultar ofertas

Primera solicitud:

`GET /api/ofertas?limit=10`

Parámetros admitidos:

| Parámetro  | Descripción                                                             |
| ---------- | ----------------------------------------------------------------------- |
| `limit`    | Cantidad de resultados. Predeterminado: `25`. Se admite de `1` a `100`. |
| `bookmark` | Marcador opaco de CouchDB para continuar el recorrido.                  |

Respuesta `200` de ejemplo:

```json
{
  "ofertas": [],
  "bookmark": "marcador_opaco_de_ejemplo",
  "limit": 10
}
```

El listado devuelve únicamente ofertas cuyo estado es `abierta`. Una oferta con el objetivo alcanzado deja de aparecer en este listado.

Para consultar una oferta específica:

`GET /api/ofertas/{id}`

Devuelve `200` con la oferta si existe. Las PYMEs, inversionistas y administradores autenticados tienen acceso a esta consulta. Una oferta inexistente devuelve `404`.

El marcador del listado es opaco: debe reutilizarse tal como lo devuelve CouchDB, codificado como parámetro URL. Se admiten hasta 8192 bytes y se recomienda conservar el mismo límite al paginar.

## Registrar una inversión

`POST /api/inversiones` permite que un inversionista registre un aporte a una oferta abierta.

Enviar `Content-Type: application/json`:

```json
{
  "oferta_id": "oferta:identificador_ficticio",
  "monto_centavos": 25000
}
```

Validaciones aplicadas:

* El usuario autenticado debe tener rol `inversionista`.
* `oferta_id` debe ser un identificador válido.
* `monto_centavos` debe ser mayor que cero.
* La oferta debe existir, estar en estado `abierta` y no haber llegado a su fecha de cierre.
* El inversionista no puede invertir en una oferta creada por su propio usuario.
* El aporte no puede superar el saldo disponible del objetivo.

El saldo disponible se calcula a partir del objetivo menos los montos recaudados y comprometidos. Al registrar el aporte, el backend incrementa el monto comprometido de la oferta. Si el objetivo queda cubierto por los montos recaudados y comprometidos, cambia el estado de la oferta a `objetivo_alcanzado`.

Respuesta `201` de ejemplo:

```json
{
  "id": "inversion:identificador_ficticio",
  "_id": "inversion:identificador_ficticio",
  "_rev": "1-revision_ficticia",
  "tipo": "inversion",
  "oferta_id": "oferta:identificador_ficticio",
  "factura_id": "factura:identificador_ficticio",
  "inversionista_id": "usuario:inversionista_ficticio",
  "monto_centavos": 25000,
  "moneda": "USD",
  "estado": "registrada",
  "fecha_creacion": "2026-10-09T18:00:00Z",
  "fecha_liquidacion": null,
  "rendimiento_real_centavos": null
}
```

El monto del ejemplo equivale a USD 250.00. El ID, la revisión y la fecha son ilustrativos.

La inversión se registra inicialmente como `registrada`. La implementación no ejecuta el cobro del dinero ni confirma que el aporte haya sido transferido.

## Consultar inversiones

Para listar inversiones:

`GET /api/inversiones/mias?limit=10`

Solo está permitido para inversionistas y administradores. La respuesta tiene esta estructura:

```json
{
  "inversiones": [],
  "bookmark": "marcador_opaco_de_ejemplo",
  "limit": 10
}
```

El límite predeterminado es `25`, admite de `1` a `100`, y el marcador puede tener como máximo 8192 bytes.

**Limitación actual:** el repositorio filtra esta consulta por `inversionista_id` igual al ID del usuario autenticado, incluso cuando el rol es administrador. Por tanto, el administrador no obtiene un listado global mediante esta ruta; la respuesta queda filtrada por su propio ID.

Para consultar una inversión específica:

`GET /api/inversiones/{id}`

* El inversionista solo puede consultar inversiones cuyo `inversionista_id` sea el suyo.
* El administrador puede consultar cualquier inversión.
* Las PYMEs no tienen acceso.
* Una inversión inexistente o ajena al inversionista devuelve `404`.

## Estados

Los estados definidos para una oferta son:

| Estado               | Significado                                                                       |
| -------------------- | --------------------------------------------------------------------------------- |
| `abierta`            | La oferta admite nuevos aportes según el saldo disponible.                        |
| `objetivo_alcanzado` | Los montos recaudados y comprometidos alcanzan el objetivo.                       |
| `cerrada`            | Estado definido en el modelo, sin una ruta pública para realizar esta transición. |
| `cancelada`          | Estado definido en el modelo, sin una ruta pública para realizar esta transición. |
| `financiada`         | Estado definido en el modelo, sin una ruta pública para realizar esta transición. |

Los estados definidos para una inversión son:

| Estado           | Significado                                     |
| ---------------- | ----------------------------------------------- |
| `registrada`     | Aporte registrado por el backend.               |
| `pago_pendiente` | Estado previsto para un pago pendiente.         |
| `confirmada`     | Estado previsto para una inversión confirmada.  |
| `liquidada`      | Estado previsto para una inversión liquidada.   |
| `reembolsada`    | Estado previsto para una inversión reembolsada. |
| `fallida`        | Estado previsto para una inversión fallida.     |

En el código actual, la creación establece la inversión en `registrada`. No existen rutas públicas para cambiar los estados de las inversiones, liquidarlas, reembolsarlas o registrar rendimientos reales. No debe interpretarse la existencia de un estado en el modelo como una operación ya implementada.

## Errores

El cuerpo de error tiene la forma `{"error":"mensaje"}`.

| HTTP  | Motivo / acción del cliente                                                                                                              |
| ----- | ---------------------------------------------------------------------------------------------------------------------------------------- |
| `400` | JSON, campos, identificadores, monto, tasa o fecha de cierre inválidos; oferta o factura no elegible. Corregir la solicitud.             |
| `401` | JWT ausente, inválido, vencido o usuario inactivo. Volver a iniciar sesión.                                                              |
| `403` | Rol sin permisos para crear, listar o consultar la operación.                                                                            |
| `404` | Oferta o inversión inexistente; inversión ajena al usuario.                                                                              |
| `409` | Oferta modificada, cerrada o sin saldo disponible; también puede indicar que ya existe una oferta para la factura. Consultar nuevamente. |
| `502` | Respuesta o documento incompatible de CouchDB.                                                                                           |
| `503` | Servicio, conexión o índice Mango no disponible.                                                                                         |

## Consideraciones de consistencia y seguridad

El registro de una inversión modifica primero la oferta para reservar el monto y después guarda el documento de inversión. Son dos escrituras separadas en CouchDB; no constituyen una transacción atómica. Si la segunda escritura falla, el monto comprometido puede quedar actualizado sin que se haya guardado la inversión. Además, ante aportes simultáneos pueden ocurrir conflictos de revisión.

Antes de usar el módulo con dinero real, deben implementarse controles de concurrencia y recuperación de operaciones, integración con un mecanismo de pago, conciliación de aportes, cierre de ofertas, liquidación y cálculo de rendimientos. La tasa almacenada no significa que el rendimiento haya sido pagado ni garantiza una rentabilidad.
