# Frontend de Créditos y Administración

Flutter consume el backend Rust mediante `ApiClient`. La dirección local está en `Frontend/plataforma_credito/lib/core/config/api_config.dart`: `http://127.0.0.1:3000`. Las solicitudes protegidas envían el token de la sesión en `Authorization: Bearer ...`.

## Créditos y pagos simulados

- `GET /api/creditos` devuelve `{ "creditos": [...], "bookmark": "...", "limit": 20 }`.
- Cada crédito publica `capital_centavos`, `interes_centavos`, `total_centavos`, `pagado_centavos` y `saldo_centavos`. Todos son enteros en centavos.
- El monto mostrado es `total_centavos`. El avance se calcula con `pagado_centavos / total_centavos`, usando los totales del servidor.
- `estado` es `activo` o `pagado`. Si `vencido` es verdadero, la interfaz lo muestra como Vencido y permite filtrar esa vista. El cliente no vuelve a calcular la mora con su reloj local.
- Cada pago registrado contiene `id`, `referencia`, `monto_centavos`, `registrado_por` y `fecha`. El contrato no contiene un campo `estado` del pago.
- El historial `pagos` se omite para inversionistas. Esto no cambia los importes agregados del crédito. La interfaz diferencia historial no compartido de historial vacío.
- Un formato incompatible muestra un error en lugar de sustituir datos ausentes por ceros.

Contrato completo: [API de Créditos](../api/creditos.md).

## Panel de administración

`GET /api/administracion/resumen` devuelve `generado_en` y ocho `reportes`: usuarios, empresas, facturas, ofertas, inversiones, creditos, pagos y auditoria. Cada reporte incluye `modulo`, `total`, `por_estado`, `por_rol` y `montos_por_moneda`.

Los indicadores se obtienen así:

| Indicador | Fuente |
|---|---|
| Créditos | `creditos.total` |
| Total de créditos | `creditos.montos_por_moneda[moneda].total_centavos`, separado por moneda |
| Empresas verificadas | `empresas.por_estado.activa` |
| Facturas pendientes | `facturas.por_estado.pendiente_verificacion` |
| Distribución por estado | `creditos.por_estado` |

Los reportes de bases vacías tienen `total: 0` y mapas vacíos. Una respuesta incompleta o con el formato plano antiguo se rechaza; no representa un resumen vacío válido. Los importes de monedas diferentes nunca se suman en un único indicador.

Contrato completo y permisos: [API de Administración](../api/administracion.md).

## Verificación

Desde `Frontend/plataforma_credito`:

```powershell
flutter analyze --no-pub
flutter test --no-pub
flutter run -d windows
```

`test/fixtures/api/` contiene respuestas ficticias compartidas por las pruebas Flutter y Rust. Las pruebas de contrato del backend comprueban que la serialización real coincide con esos JSON; Flutter comprueba los importes visibles, monedas, historial restringido, formatos inválidos y respuestas pendientes de una sesión cerrada.

Desde `Backend/credito_backend`, `cargo test --locked` ejecuta esas comprobaciones junto a las demás pruebas. Estas usan servicios locales ficticios; la integración con CouchDB real tiene pruebas específicas marcadas como ignoradas y debe verificarse por separado.

## Acciones y páginas implementadas

La interfaz incluye emisión administrativa de créditos desde ofertas elegibles, confirmación de aportes simulados, registro de pagos y recuperación explícita de sincronizaciones. Las referencias y claves se conservan al reintentar para no duplicar operaciones. Un resultado con sincronización pendiente sigue indicando que el cambio principal ya se guardó.

El listado de créditos conserva cursores y permite cargar más páginas; los filtros incluyen la vista derivada Vencido. Un historial omitido para inversionistas no se representa como una lista de pagos vacía ni altera los importes agregados.

El panel administrativo integra Resumen, Reportes y auditoría y Usuarios. Los reportes seleccionan uno de los ocho módulos y muestran cada moneda por separado. La auditoría permite combinar actor y recurso, recorrer cursores y consultar la fecha local del evento sin prometer orden cronológico. La gestión de usuarios confirma cambios de rol/estado y exige recargar revisiones en conflicto.

Las mutaciones financieras y administrativas requieren conexión. Las instantáneas de lecturas y la cola limitada de empresas/facturas se describen en [Modo local Windows](../integracion/offline_windows.md).

El [recorrido con CouchDB real](../integracion/couchdb_real.md) se ejecutó en bases aisladas para verificar la integración de los seis módulos. No sustituye las pruebas de concurrencia, permisos y fallos que siguen formando parte de la suite con servidores ficticios.
