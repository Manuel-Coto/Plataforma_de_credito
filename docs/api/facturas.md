# Facturas

URL local: `http://127.0.0.1:3000`. Todas las rutas requieren `Authorization: Bearer <valor recibido al iniciar sesión>` y un usuario activo. El backend utiliza la base CouchDB `facturas` y consulta también `empresas` para validar la empresa asociada. Al iniciar se deben crear la base y los índices Mango definidos para Facturas. Si las bases e índices ya existen, la inicialización debe continuar sin borrarlos.

La estructura interna de la base está en [la documentación de facturas](../../database/facturas/README.md).

## Rutas y permisos

| Método y ruta                            | PYME                         | Inversionista                     | Administrador                         | Respuesta exitosa           |
| ---------------------------------------- | ---------------------------- | --------------------------------- | ------------------------------------- | --------------------------- |
| `POST /api/facturas`                     | Crear para su empresa activa | No permitido                      | No permitido                          | `201`, factura creada.      |
| `GET /api/facturas`                      | Solo facturas propias        | Todas las facturas                | Todas las facturas                    | `200`, página de facturas.  |
| `GET /api/facturas/{id}`                 | Solo factura propia          | Puede consultar cualquier factura | Puede consultar cualquier factura     | `200`, factura.             |
| `PATCH /api/facturas/{id}/verificar-dte` | No permitido                 | No permitido                      | Registrar verificación administrativa | `200`, factura actualizada. |

Las rutas protegidas requieren un JWT válido. Si el usuario no tiene el rol necesario, recibe `403`. Una PYME que intenta consultar una factura ajena recibe `404` para no revelar si existe.

La verificación del DTE está reservada al administrador. En la implementación actual, esta operación registra el sello de recepción proporcionado y marca el DTE como verificado; no consulta automáticamente los servicios oficiales de Hacienda ni certifica por sí sola la autenticidad tributaria del documento.

## Crear una factura

`POST /api/facturas` recibe los siguientes campos obligatorios. Todos los campos adicionales se rechazan.

Enviar `Content-Type: application/json`:

```json
{
  "empresa_id": "empresa_ficticia_001",
  "numero": "FAC-2026-001",
  "codigo_generacion": "CODIGO-GENERACION-FICTICIO-001",
  "moneda": "USD",
  "monto_total_centavos": 125000,
  "fecha_emision": "2026-10-01",
  "fecha_vencimiento": "2026-11-15"
}
```

Los datos son ilustrativos. `monto_total_centavos` expresa el importe en centavos: `125000` equivale a USD 1,250.00. No se utiliza punto flotante para representar el importe.

Validaciones aplicadas:

* `empresa_id`: identificador obligatorio y válido.
* `numero`: obligatorio; se recortan los espacios externos.
* `codigo_generacion`: obligatorio; se recortan los espacios externos.
* `moneda`: se recortan los espacios y se convierten las letras a mayúsculas. Solo se admite `USD`.
* `monto_total_centavos`: debe ser mayor que cero.
* `fecha_emision` y `fecha_vencimiento`: fechas con formato `AAAA-MM-DD`. El vencimiento no puede ser anterior a la emisión.
* La empresa debe existir, estar en estado `activa` y pertenecer a la PYME autenticada.
* No debe existir otra factura con el mismo código de generación del DTE.

La creación asigna automáticamente el identificador, el usuario creador, las fechas iniciales, el importe financiado en cero y el estado `pendiente_verificacion`. El DTE comienza con `verificado: false`.

Respuesta `201` de ejemplo:

```json
{
  "id": "factura:1790877600000000-1",
  "_id": "factura:1790877600000000-1",
  "_rev": "1-revision_ficticia",
  "tipo": "factura",
  "empresa_id": "empresa_ficticia_001",
  "numero": "FAC-2026-001",
  "dte": {
    "codigo_generacion": "CODIGO-GENERACION-FICTICIO-001",
    "sello_recepcion": null,
    "verificado": false,
    "fecha_verificacion": null
  },
  "moneda": "USD",
  "monto_total_centavos": 125000,
  "monto_financiado_centavos": 0,
  "fecha_emision": "2026-10-01",
  "fecha_vencimiento": "2026-11-15",
  "estado": "pendiente_verificacion",
  "creado_por": "usuario:identificador_ficticio",
  "fecha_creacion": "2026-10-09T18:00:00Z",
  "fecha_actualizacion": null
}
```

El ID, la revisión y las fechas de la respuesta son ilustrativos. Deben tomarse los valores reales que devuelve el servidor. La implementación actual incluye `_id` y `_rev` en la representación JSON; `_rev` es una revisión interna de CouchDB y no debe utilizarse como mecanismo de autenticación.

## Listado paginado

Primera solicitud:

`GET /api/facturas?limit=10`

Parámetros admitidos:

| Parámetro  | Descripción                                                             |
| ---------- | ----------------------------------------------------------------------- |
| `limit`    | Cantidad de resultados. Predeterminado: `25`. Se admite de `1` a `100`. |
| `bookmark` | Marcador opaco devuelto por CouchDB para continuar el recorrido.        |
| `estado`   | Filtro opcional por estado de factura.                                  |

Los estados admitidos para `estado` son `pendiente_verificacion`, `verificada`, `disponible`, `parcialmente_financiada`, `financiada`, `pagada`, `vencida` y `rechazada`.

Respuesta `200` de ejemplo:

```json
{
  "facturas": [],
  "bookmark": "marcador_opaco_de_ejemplo",
  "limit": 10
}
```

El ejemplo muestra una página vacía. Cuando existan resultados, `facturas` contendrá los documentos encontrados.

El listado se filtra según el rol:

* **PYME:** solo facturas cuyo `creado_por` corresponde al usuario autenticado.
* **Inversionista:** todas las facturas.
* **Administrador:** todas las facturas.

El filtro `estado` se puede combinar con `limit` y `bookmark`. Para continuar, enviar el marcador real codificado como parámetro URL y mantener el mismo límite. No interpretarlo como número de página. Se admiten marcadores de hasta 8192 bytes.

## Consultar una factura

`GET /api/facturas/{id}` devuelve `200` con la factura encontrada. El identificador debe corresponder a una factura existente y válida.

Las PYMEs solo pueden consultar sus propias facturas. Los inversionistas y administradores pueden consultar cualquier factura mediante esta ruta.

Una factura inexistente devuelve `404`. Los identificadores vacíos, demasiado largos, con barras o caracteres de control se rechazan con `400`.

## Verificar el DTE

La ruta es:

`PATCH /api/facturas/{id}/verificar-dte`

Solo puede ejecutarla un administrador. La solicitud lleva `Authorization: Bearer <token>` y `Content-Type: application/json`.

Cuerpo:

```json
{
  "sello_recepcion": "SELLO-FICTICIO-DE-RECEPCION"
}
```

El sello debe contener caracteres no blancos y tener un máximo de 256 bytes.

Cuando la factura está en `pendiente_verificacion` y todavía no está verificada, la operación registra el sello, establece `dte.verificado` en `true`, asigna `dte.fecha_verificacion`, cambia el estado a `disponible` y actualiza `fecha_actualizacion`.

Si el DTE ya aparece verificado, devuelve la factura sin efectuar una nueva escritura. Si la factura no está pendiente de verificación, devuelve `400`.

**Alcance importante:** este endpoint registra una decisión administrativa. No realiza una consulta externa a Hacienda ni verifica criptográficamente el DTE. Para usarlo en producción, deberá integrarse con una fuente oficial y comprobar su respuesta antes de marcar el documento como verificado.

## Errores

El cuerpo de error tiene la forma `{"error":"mensaje"}`.

| HTTP  | Motivo / acción del cliente                                                           |
| ----- | ------------------------------------------------------------------------------------- |
| `400` | JSON, campos, fechas, identificador, filtro o sello inválidos. Corregir la solicitud. |
| `401` | JWT ausente, inválido, vencido o usuario inactivo. Volver a iniciar sesión.           |
| `403` | Rol sin permisos o empresa no autorizada para crear la factura.                       |
| `404` | Factura inexistente o ajena a la PYME.                                                |
| `409` | DTE duplicado o conflicto de revisión al guardar. Consultar nuevamente.               |
| `502` | Respuesta o documento incompatible de CouchDB.                                        |
| `503` | Base de datos, configuración o índice Mango no disponible.                            |

## Integración con Flutter Desktop

Usar `http://127.0.0.1:3000` cuando Flutter y Rust se ejecuten en el mismo equipo. Después del login, enviar el JWT en la cabecera `Authorization` para las rutas de Facturas.

En los formularios, convertir el importe a centavos antes de enviarlo. Enviar las fechas en formato `AAAA-MM-DD` y la moneda como `USD`. La interfaz puede ocultar operaciones que no correspondan al rol, pero el backend sigue siendo responsable de validar los permisos.

No conectar Flutter directamente a CouchDB ni incluir sus credenciales en la aplicación. En Flutter Web, configurar CORS por separado si se habilita el acceso desde navegador.
