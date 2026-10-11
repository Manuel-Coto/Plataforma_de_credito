# Créditos y pagos simulados

URL local: `http://127.0.0.1:3000`. Todas las rutas requieren `Authorization: Bearer <token>` y un usuario activo. El módulo conserva la organización de los anteriores: rutas, manejadores, servicios, repositorio y modelos. Utiliza las bases CouchDB `operaciones`, `ofertas`, `facturas`, `empresas` y `auditoria`.

## Rutas y permisos

| Método y ruta | PYME | Inversionista | Administrador |
| --- | --- | --- | --- |
| `POST /api/creditos/aportes/{id}/confirmar` | No permitido | Confirmar su propio aporte | Confirmar cualquier aporte |
| `POST /api/creditos` | No permitido | No permitido | Crear crédito desde una oferta completamente financiada |
| `GET /api/creditos` | Sus créditos | Créditos en los que participa | Todos los créditos |
| `GET /api/creditos/{id}` | Su crédito | Crédito en el que participa | Cualquier crédito |
| `POST /api/creditos/{id}/pagos` | Registrar un pago de su crédito | No permitido | Registrar un pago de cualquier crédito |
| `POST /api/creditos/{id}/sincronizar` | No permitido | No permitido | Reintentar las actualizaciones relacionadas |

Las confirmaciones y pagos son simulados. No se realiza un cobro bancario ni se solicita información de tarjetas.

La creación devuelve `201` (también al repetirla para recuperar el crédito existente). Las consultas, confirmaciones, pagos y sincronizaciones devuelven `200` cuando se completan. Un resultado exitoso puede tener sincronización pendiente, según se detalla más adelante.

## Flujo previo y confirmación del aporte

El flujo comienza con los módulos existentes: una PYME registra su empresa y factura, un administrador aprueba la empresa y verifica el DTE, la PYME publica una oferta y los inversionistas registran sus aportes.

La API actual de inversiones recibe `monto_objetivo` y `tasa_rendimiento_anual` al crear una oferta, y `monto` al registrar un aporte. Estos importes se expresan en unidades monetarias; la tasa se expresa como porcentaje anual. Créditos convierte los importes a centavos y la tasa a puntos básicos antes de calcular. Por ejemplo, USD 1000.00 se convierten en `100000` centavos y una tasa de `8.0` % se convierte en `800` puntos básicos. Los importes de origen con fracciones menores a un centavo no son elegibles.

Confirmar el aporte usando su ID de inversión:

```http
POST /api/creditos/aportes/inversion:identificador_ficticio/confirmar
Authorization: Bearer <token_inversionista_o_administrador>
```

No se envía cuerpo. La operación acepta aportes `registrada` o `pago_pendiente` y los cambia a `confirmada`. Repetir una confirmación ya realizada no vuelve a registrar el aporte. La respuesta identifica la inversión e indica si queda pendiente la auditoría:

```json
{
  "inversion_id": "inversion:identificador_ficticio",
  "estado": "confirmada",
  "simulado": true,
  "sincronizacion_pendiente": false
}
```

## Crear el crédito

El administrador envía `POST /api/creditos`, con `Content-Type: application/json`:

```json
{
  "oferta_id": "oferta:identificador_ficticio"
}
```

Se comprueba que la oferta tenga el objetivo alcanzado, que todos sus aportes estén confirmados y que sus importes sumen exactamente el capital objetivo. Se admiten hasta 5000 aportes por crédito. La factura debe tener DTE verificado, estar en estado `disponible` y vencer en una fecha posterior a la creación del crédito. La empresa debe estar activa y corresponder a la factura y oferta. Los importes deben estar expresados en USD. Los datos incompatibles de los módulos anteriores no se convierten silenciosamente en un crédito.

El crédito tiene un ID determinista por factura, un único capital y un interés fijo. Repetir la creación de la misma oferta devuelve el crédito existente y reintenta las actualizaciones pendientes.

### Cálculo

Se utilizan días calendario desde la fecha UTC de creación hasta el vencimiento de la factura. El interés simple es:

```text
interes_centavos = redondear_mitad_arriba(
  capital_centavos * tasa_anual_bp * dias / (10000 * 365)
)
total_centavos = capital_centavos + interes_centavos
saldo_centavos = total_centavos - pagado_centavos
```

Para USD 1000.00, tasa anual de 8 % y 30 días, el interés es `658` centavos, el total es `100658` centavos y el saldo inicial es USD 1006.58. La tasa de la oferta se redondea a puntos básicos. No se agregan recargos ni se recalcula el interés por un pago anticipado.

El interés se distribuye proporcionalmente al capital de cada aporte. Los ajustes por redondeo conservan el interés total del crédito.

## Consultar créditos

```http
GET /api/creditos?limit=10&estado=activo
GET /api/creditos/{id}
```

| Parámetro de listado | Descripción |
| --- | --- |
| `limit` | Entero sin signo; predeterminado `20`. `0` se ajusta a `1` y valores superiores a `100` se ajustan a `100`. |
| `bookmark` | Marcador opaco de CouchDB, de hasta 8192 bytes, para continuar la consulta; conservar los filtros al paginar. |
| `estado` | Opcional: `activo` o `pagado`. |

El listado responde con `creditos`, `bookmark` y `limit`. El detalle devuelve una vista del crédito con los importes en centavos, `saldo_centavos`, `tasa_anual_bp`, estado, versión y fechas. Se calculan `vencido` y `dias_mora` al consultar: un crédito activo con saldo pendiente y fecha anterior al día UTC actual está vencido. `vencido` no es un estado almacenado ni un filtro de listado.

La PYME responsable y el administrador pueden consultar el historial `pagos` y las participaciones del crédito. El inversionista ve solo sus participaciones; la respuesta omite el historial de pagos y las participaciones de otros inversionistas. Las vistas no incluyen `_rev` de CouchDB. Consultar el detalle de un crédito que no corresponde al usuario devuelve `403`.

## Registrar pagos parciales o totales

La PYME responsable o el administrador envían `POST /api/creditos/{id}/pagos`:

```json
{
  "referencia": "pago-simulado-001",
  "monto_centavos": 50000
}
```

El monto debe ser un entero positivo y no superar el saldo. La referencia debe contener de 1 a 100 caracteres ASCII: letras, números, guiones o guiones bajos. El servidor asigna la fecha, el ID del pago y el usuario que lo registra. Cada pago actualiza el saldo y su historial dentro de la misma revisión del documento del crédito. Se admiten hasta 1000 pagos por crédito.

La referencia permite reintentar una solicitud cuya respuesta se perdió. Debe mantenerse idéntica para el mismo pago: referencia, monto y usuario deben coincidir. Cambiar monto o usuario con una referencia existente devuelve `409`. Para un pago nuevo se utiliza una referencia nueva.

Al cubrir el total, el estado pasa de `activo` a `pagado`, se registra `fecha_pago_total` y se sincronizan la factura como pagada y las inversiones como liquidadas con su rendimiento. Los pagos parciales no liquidan las inversiones.

Las mutaciones del crédito responden con esta estructura:

```json
{
  "credito": {
    "id": "credito:identificador_ficticio",
    "oferta_id": "oferta:identificador_ficticio",
    "factura_id": "factura:identificador_ficticio",
    "empresa_id": "empresa_ficticia_001",
    "moneda": "USD",
    "capital_centavos": 100000,
    "interes_centavos": 658,
    "total_centavos": 100658,
    "pagado_centavos": 50000,
    "saldo_centavos": 50658,
    "tasa_anual_bp": 800,
    "estado": "activo",
    "vencido": false,
    "dias_mora": 0,
    "version": 2,
    "fecha_creacion": "2026-10-10T18:00:00Z",
    "fecha_vencimiento": "2026-11-09",
    "fecha_pago_total": null,
    "pagos": [
      {
        "id": "pago:identificador_ficticio",
        "referencia": "pago-simulado-001",
        "monto_centavos": 50000,
        "registrado_por": "usuario:pyme_ficticia",
        "fecha": "2026-10-11T18:00:00Z"
      }
    ],
    "participaciones": [
      {
        "inversion_id": "inversion:identificador_ficticio",
        "inversionista_id": "usuario:inversionista_ficticio",
        "capital_centavos": 100000,
        "interes_centavos": 658
      }
    ]
  },
  "sincronizacion_pendiente": false
}
```

Los identificadores y fechas del ejemplo son ficticios. El detalle contiene directamente el objeto `credito`; la envoltura con `sincronizacion_pendiente` se utiliza para las mutaciones.

## Recuperación de escrituras relacionadas

CouchDB garantiza el cambio de una revisión de un documento; no existe una transacción entre todas las bases. El documento del crédito en `operaciones` conserva el saldo y los pagos confirmados. Después se actualizan los documentos relacionados y la auditoría.

Si alguna actualización posterior falla, la respuesta exitosa tiene `sincronizacion_pendiente: true`. El pago ya está registrado: no se debe crear otro pago para compensar la falta de sincronización. Se puede repetir la misma solicitud con la misma referencia o solicitar al administrador:

```http
POST /api/creditos/{id}/sincronizar
Authorization: Bearer <token_administrador>
```

Esta ruta no recibe cuerpo. Reintenta las actualizaciones y devuelve el crédito y el indicador actual de sincronización. Los eventos de auditoría tienen identificadores estables para que el reintento no duplique eventos.

Si la confirmación de un aporte devuelve sincronización pendiente, se repite su ruta `/api/creditos/aportes/{id}/confirmar` para recuperar ese evento. La sincronización del crédito repara los eventos de creación del crédito y de sus pagos.

## Errores

El cuerpo de error tiene la forma `{"error":"mensaje"}`.

| HTTP | Motivo |
| --- | --- |
| `400` | JSON, campos, identificadores, consulta, referencia o monto inválidos; pago superior al saldo; límite de 1000 pagos alcanzado. |
| `401` | JWT ausente, inválido, vencido o usuario inactivo. |
| `403` | Rol sin permisos para ejecutar la acción o usuario sin acceso al recurso. |
| `404` | Recurso inexistente. |
| `409` | Estado o revisión incompatible, aportes no conciliados o referencia reutilizada con datos distintos. |
| `502` | Documento o respuesta incompatible de CouchDB. |
| `503` | Configuración, conexión o servicio de datos no disponible. |

La confirmación y las mutaciones rechazan condiciones incompatibles antes de comprometer el cambio principal. Si la respuesta fue exitosa con sincronización pendiente, se utiliza el mecanismo de recuperación descrito arriba.
