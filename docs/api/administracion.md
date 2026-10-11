# API de Administración

El módulo mantiene las capas `routes`, `handler`, `service`, `repository` y `model`. Todas las rutas requieren `Authorization: Bearer <access_token>` y un usuario activo con rol `administrador`, comprobado con el servicio de Usuarios y el estado actual en CouchDB. Las respuestas exitosas incluyen `Cache-Control: no-store`.

## Rutas

| Método | Ruta | Resultado |
|---|---|---|
| GET | `/api/administracion/resumen` | Estadísticas de todos los módulos |
| GET | `/api/administracion/reportes?modulo=creditos` | Reporte agregado de un módulo |
| GET | `/api/administracion/auditoria` | Página de eventos de auditoría |

## Resumen y reportes

Los valores admitidos de `modulo` son `usuarios`, `empresas`, `facturas`, `ofertas`, `inversiones`, `creditos`, `pagos` y `auditoria`. El parámetro es obligatorio en `/reportes`.

El resumen devuelve `{ "generado_en": "<fecha UTC>", "reportes": [...] }`; cada elemento tiene la misma estructura que `/reportes`:

```json
{
  "modulo": "creditos",
  "total": 2,
  "por_estado": { "activo": 1, "vencido": 1 },
  "por_rol": {},
  "montos_por_moneda": {
    "USD": {
      "capital_centavos": 20000,
      "interes_centavos": 1000,
      "total_centavos": 21000,
      "pagado_centavos": 2500,
      "saldo_centavos": 18500
    }
  }
}
```

- `usuarios`: cantidad total, por estado y por rol; no incluye nombres, correos ni hashes.
- `empresas`: cantidad total y por estado; documentos anteriores sin `estado` cuentan como `pendiente`, igual que en el módulo Empresas.
- `facturas`: cantidad total, por estado, `total_centavos` y `financiado_centavos`.
- `ofertas`: cantidad total, por estado, `objetivo_centavos` y `recaudado_centavos`.
- `inversiones`: cantidad total, por estado e `invertido_centavos`.
- `creditos`: cantidad total, por estado y capital, interés, total, pagado y saldo en centavos.
- `pagos`: cantidad de pagos embebidos en créditos y suma `pagado_centavos`.
- `auditoria`: cantidad de eventos almacenados.

Los importes se suman por moneda. Ofertas e inversiones conservan su almacenamiento previo en unidades monetarias; para reportar se convierten a centavos con redondeo por documento. Las sumas comprueban desbordamiento. Un crédito activo con saldo pendiente y fecha de vencimiento anterior a la fecha UTC de consulta se cuenta como `vencido`; esto no modifica el documento.

Los reportes recorren todas las páginas de CouchDB, incluso si una página intermedia tiene menos de 100 registros. No están limitados a los primeros 25 documentos. Se solicitan únicamente campos de agregación y se procesan por páginas. Los documentos de diseño no cuentan; inversiones y créditos se distinguen por `tipo` dentro de `operaciones`.

El resumen representa consultas sucesivas a las bases; no es una transacción ni una instantánea atómica entre módulos. Si una base requerida falla o devuelve datos incompatibles, se devuelve un error en vez de totales parciales. Bases vacías producen totales cero y mapas vacíos. Las sumas incluyen todos los estados; por ejemplo, `invertido_centavos` suma también inversiones fallidas o reembolsadas y no representa un saldo de caja.

## Auditoría

Parámetros opcionales: `limit` (1–100, predeterminado 25), `bookmark` (máximo 8192 caracteres), `actor_id` y `recurso_id` (identificadores exactos de 1–512 caracteres). Ambos filtros pueden combinarse. Los parámetros desconocidos se rechazan.

```json
{
  "eventos": [
    {
      "id": "evento-credito-1-pago-1",
      "actor_id": "usuario-1",
      "accion": "pago_registrado",
      "recurso_tipo": "credito",
      "recurso_id": "credito-1",
      "fecha": "2026-10-10T15:00:00Z",
      "detalles": { "moneda": "USD", "monto_centavos": 2500 }
    }
  ],
  "bookmark": "<cursor opaco>",
  "limit": 25
}
```

Para continuar, enviar el `bookmark` anterior y conservar los mismos filtros; finalizar al recibir una página vacía. El orden corresponde al índice elegido por CouchDB, sin garantía de orden cronológico. El cliente debe tratar el bookmark como un valor opaco y codificarlo en la URL.

La base `auditoria` contiene documentos `tipo: "evento"`. Solo se exponen identificadores, acción, recurso, fecha y detalles estructurales permitidos: `estado_anterior`, `estado_nuevo`, `moneda`, `credito_id`, `pago_id`, `oferta_id`, `factura_id`, `empresa_id`, `monto_centavos`. No se devuelven propiedades arbitrarias, perfiles completos, contraseñas ni tokens.

Administración consulta los eventos que los módulos productores persisten. No inventa eventos históricos ni convierte lecturas del dashboard en eventos. Créditos y pagos publican sus eventos de creación, confirmación de aporte y registro de pago; si su sincronización está pendiente, la auditoría reflejará el cambio al recuperarse esa sincronización. Los módulos anteriores conservan sus flujos existentes.

## Errores

Los errores usan `{ "error": "mensaje" }`: `400` para consultas inválidas, `401` para autenticación ausente/incorrecta o usuario inactivo, `403` para rol insuficiente, `503` para configuración o base no disponible y `502` para respuestas incompatibles de CouchDB. No se exponen credenciales ni mensajes internos del servidor de base de datos.
