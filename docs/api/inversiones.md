# Ofertas e inversiones

Todas las rutas requieren una cuenta activa y Authorization: Bearer <token>. El catálogo vive en ofertas; las inversiones, solicitudes idempotentes y créditos comparten operaciones, separados por tipo. La API base local es http://127.0.0.1:3000.

## Rutas reales

| Método y ruta | PYME | Inversionista | Administrador |
|---|---|---|---|
| POST /api/ofertas | Publicar para su factura | No | Publicar para una factura disponible |
| GET /api/ofertas | Consultar | Consultar | Consultar |
| POST /api/inversiones | No | Registrar su aporte | No |
| GET /api/inversiones | No | Sus inversiones | Todas las inversiones |
| POST /api/inversiones/recuperar | No | Sus reservas | Reservas de todos los inversionistas |

No existen GET /api/ofertas/{id}, GET /api/inversiones/{id} ni /api/inversiones/mias. La consulta usa las páginas de los dos listados.

## Publicar una oferta

```json
{
  "factura_id": "factura-ficticia",
  "monto_objetivo": 1000.00,
  "tasa_rendimiento_anual": 8.0,
  "fecha_cierre": "2027-01-15T23:59:59Z"
}
```

monto_objetivo está en unidades monetarias, con un máximo de dos decimales, y debe ser positivo. tasa_rendimiento_anual es un porcentaje entre 0 y 100. No enviar campos *_centavos o *_bp a este endpoint. La fecha debe incluir zona horaria y estar en el futuro al crear la oferta.

La factura debe estar disponible, en USD y con DTE verificado. La PYME debe ser su creadora; un administrador puede publicar para otra cuenta. El objetivo no puede superar el monto de la factura. Al emitir el crédito se vuelve a comprobar la empresa activa y las condiciones de la factura.

Se admite una oferta por factura. El ID se deriva de esa factura y también se comprueban las ofertas con identificadores antiguos. Repetir exactamente la publicación por el mismo creador recupera la oferta existente; contenido o creador diferentes producen 409. Repetir no reabre una oferta cerrada ni reinicia su recaudación.

La respuesta 201 contiene la oferta:

```json
{
  "_id": "oferta-identificador-ficticio",
  "_rev": "1-revision-ficticia",
  "tipo": "oferta",
  "factura_id": "factura-ficticia",
  "empresa_id": "empresa-ficticia",
  "monto_objetivo": 1000.0,
  "monto_recaudado": 0.0,
  "moneda": "USD",
  "tasa_rendimiento_anual": 8.0,
  "estado": "abierta",
  "fecha_apertura": "2026-11-08T18:00:00Z",
  "fecha_cierre": "2027-01-15T23:59:59Z",
  "creado_por": "usuario:ficticio"
}
```

Los valores son ilustrativos. La revisión de CouchDB no es un token de autenticación. Las reservas internas no aparecen en el DTO público de oferta.

## Consultar páginas

GET /api/ofertas admite limit (20 por defecto, entre 1 y 100), bookmark y estado. Sin estado no se limita automáticamente a ofertas abiertas: el cliente puede pedir estado=abierta para el catálogo disponible.

GET /api/inversiones admite limit y bookmark; aplica la propiedad del usuario en el servidor. El administrador obtiene el listado global.

```json
{"ofertas": [], "bookmark": "<cursor opaco>", "limit": 20}
```

```json
{"inversiones": [], "bookmark": "<cursor opaco>", "limit": 20}
```

Conservar los filtros al paginar. El bookmark es opaco; una página vacía termina el recorrido. Una página corta no demuestra que se haya llegado al final.

## Aportar y reintentar sin duplicar

POST /api/inversiones requiere una única cabecera Idempotency-Key de 1 a 128 caracteres ASCII sin espacios y un cuerpo:

```json
{"oferta_id": "oferta-ficticia", "monto": 250.00}
```

monto está en unidades monetarias, debe ser positivo y tener como máximo dos decimales. La oferta debe estar abierta, sin haber cerrado y con saldo suficiente. La respuesta es 201 con la inversión, tipo inversion, estado pago_pendiente y campos monto, moneda, inversionista_id, fecha_creacion, fecha_liquidacion y rendimiento_real.

Conservar la clave para reintentar la misma solicitud si se pierde la respuesta. La clave pertenece al usuario: reutilizarla para otra oferta o importe produce 409. Una repetición devuelve la misma inversión y conserva una confirmación o liquidación ya realizada.

La reserva y la recaudación se comprometen en una sola revisión de la oferta. El documento público de inversión es una proyección recuperable. Las solicitudes y el libro de reservas no se presentan como inversiones ni se cuentan como aportes confirmados para emitir créditos. Los conflictos de revisión se reintentan dentro de un límite; nunca se debe crear un aporte diferente para compensar una respuesta perdida.

## Recuperar una reserva

Si una reserva quedó comprometida pero faltó proyectar su inversión, repetir POST /api/inversiones con la misma clave vuelve a materializarla.

Si se perdió la clave, usar POST /api/inversiones/recuperar?limit=25&bookmark=... sin cuerpo. Solo materializa reservas ya comprometidas y no reserva fondos nuevos. La respuesta contiene:

```json
{"recuperadas": 1, "pendientes": 0, "omitidas": 0, "bookmark": "<cursor opaco>"}
```

Continuar con el cursor mientras se recorre el conjunto de ofertas. Esta recuperación requiere conexión y no sustituye la confirmación del aporte.

## Confirmación, crédito y liquidación

El inversionista dueño o un administrador confirma el aporte simulado con POST /api/creditos/aportes/{id}/confirmar. Repetir la confirmación es idempotente.

Cuando el objetivo está cubierto y todos los aportes están confirmados, el administrador puede emitir el crédito desde la oferta. Al completar sus pagos se sincroniza la inversión a liquidada y se calcula su rendimiento. Ver [Créditos y pagos](creditos.md).

cerrada, cancelada, reembolsada y fallida existen en los modelos, pero su existencia no implica endpoints para ejecutar todas esas transiciones. No hay cobros bancarios reales ni garantía de rentabilidad.

## Errores

400 indica campos, importe, fecha o clave inválidos; 401 exige iniciar sesión; 403 indica rol insuficiente; 404 indica documento inexistente; 409 indica clave/contenido incompatible, oferta sin saldo o estado incompatible. 502 señala datos de CouchDB incompatibles y 503 un servicio, conexión o índice no disponible.

No reintentar errores de validación como si fueran desconexiones. Inversiones y recuperación se ejecutan en línea; la cola local de empresas/facturas no envía aportes financieros.
