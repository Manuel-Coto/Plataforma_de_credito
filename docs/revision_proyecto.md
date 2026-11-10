# Revisión del proyecto contra su documentación

Fecha: 9 de noviembre de 2026. Alcance: estado local del repositorio, incluidos los cambios sin commit de esta sesión.

## Dictamen

Los seis módulos principales están implementados y el recorrido académico documentado cuenta con evidencia automatizada. No se detectó un módulo principal ausente. Retry-After está corregido y probado. La segunda revisión encontró tres consumidores de paginación que aún terminan prematuramente ante una página vacía con cursor válido; por ello no se considera cerrado al 100 %. La aceptación funcional automatizada de los tres roles pasó; una pasada manual integral de todas las pantallas sigue sin acreditarse.

La referencia fue README.md, docs/api, docs/modulos, docs/integracion, los README del cliente y de las bases, Docker y el código/pruebas asociados. No se encontró un pliego externo PDF/DOCX en el repositorio. Esta revisión no certifica requisitos de una rúbrica externa ni ausencia de cualquier defecto.

## Cobertura encontrada

| Área | Implementación y evidencia | Evaluación |
|---|---|---|
| Usuarios | Registro, login, Argon2id, JWT, perfil y gestión administrativa con revisión en src/modules/usuarios; pantallas y pruebas de sesión/usuarios en Flutter. | Implementado; Retry-After corregido y probado. |
| Empresas | Creación, consulta propia, edición, desactivación y aprobación/rechazo con ETag; protección por responsable e idempotencia. Pruebas de permisos, carreras, paginación y documentos antiguos. | Implementado. |
| Facturas | Creación, listado, detalle, permisos y verificación administrativa del DTE; formulario y filtros del cliente. | Implementado dentro de la verificación manual declarada. |
| Ofertas e inversiones | Publicación, catálogo, aportes idempotentes, reservas y recuperación; roles y proyecciones recuperables. | Implementado dentro del alcance simulado. |
| Créditos y pagos | Emisión administrativa, confirmación de aportes, cálculos en centavos, seguimiento, pago, liquidación y recuperación de sincronización. | Implementado dentro del alcance simulado. |
| Administración | Ocho reportes, importes separados por moneda, auditoría con filtros y gestión de usuarios. | Implementado. |
| Modo local Windows | Caché y cola limitada, aislamiento por sesión/rol/servidor, DPAPI CurrentUser, sincronización explícita y conflictos. | Implementado; no es funcionamiento completamente desconectado. |
| Docker y bases | Backend y CouchDB, variables obligatorias, espera de disponibilidad, volumen persistente e inicialización de índices. | Arranque y compilación comprobados en esta sesión. |

Las rutas backend están en Backend/credito_backend/src/modules; la navegación y los proveedores del cliente están en Frontend/plataforma_credito/lib. Los contratos compartidos y el recorrido real tienen pruebas propias.

## Hallazgos corregidos

### Resuelto: espera de autenticación ante HTTP 429

ApiClient conserva Retry-After en ApiException, tanto en segundos como en fecha HTTP. Una cabecera ausente o inválida aplica la espera predeterminada de 60 segundos. SesionProvider comparte el bloqueo entre login y registro, impide nuevas solicitudes durante la espera y libera el estado al terminar. Ambos formularios muestran la cuenta regresiva y deshabilitan el envío.

La regresión test/auth_retry_after_test.dart verifica interpretación de cabeceras, bloqueo de ambos formularios y del proveedor, ausencia de solicitudes extra durante la espera y posibilidad de reenviar al finalizar. Los temporizadores se cancelan al destruir el proveedor.

### Documentación unificada; implementación de paginación todavía parcial

Las guías de Empresas, Usuarios, Inversiones, Administración, Facturas y Créditos ahora describen el mismo contrato: mantener filtros/límite, continuar con un cursor nuevo válido aunque haya páginas vacías, y terminar ante cursor vacío o repetido.

Se documentó que la API representa la ausencia de cursor como una cadena vacía y normaliza el sentinel interno nil de CouchDB. No se modificó la lógica financiera para resolver este hallazgo documental.

La revisión anterior cerró este punto demasiado pronto: no todos los consumidores del contrato lo cumplen. Hallazgos P2 reproducidos en la segunda revisión:

| Ubicación | Diferencia con el contrato | Consecuencia |
|---|---|---|
| lib/modules/inversiones/screens/publicar_oferta_screen.dart:69 | Exige una página no vacía para ofrecer continuar. | Una página vacía intermedia oculta Cargar más facturas y puede impedir elegir una factura posterior. |
| lib/modules/creditos/widgets/crear_credito_dialog.dart:43 | Exige una página no vacía para ofrecer continuar. | Puede mostrar que no hay ofertas financiadas y ocultar Cargar más ofertas aunque exista cursor válido. |
| lib/services/inversion_service.dart:26 | actualizarOferta corta el recorrido por items.isEmpty. | Devuelve 404 al actualizar una oferta que podría estar en una página posterior; se llama antes de aportar. |

Reproducción controlada: responder a la primera consulta con lista vacía y bookmark cursor-A, y disponer de una segunda página. Dos pruebas de widget comprobaron que ambos selectores no consultan la página siguiente ni muestran una acción para continuar. Una prueba del servicio comprobó el 404 antes de consultar la segunda página, que contenía la oferta buscada. Los tres casos fallaron el contrato esperado. Se usaron respuestas ficticias, sin datos reales ni modificaciones de código productivo. La prueba temporal de revisión se retiró después de documentar la evidencia.

Corrección pendiente: continuar automáticamente sobre páginas vacías con cursores nuevos o permitir cargar la siguiente página; conservar filtros/límite y detectar todos los cursores repetidos. Agregar regresiones permanentes para los tres consumidores. No basta con modificar las guías ni con que pasen las pruebas de los listados principales.

## Comprobaciones y límites de la evidencia

- Flutter: análisis completo sin incidencias y 98 pruebas aprobadas tras las correcciones, incluidos los tres casos nuevos de Retry-After.
- Segunda revisión: tres casos adicionales temporales reprodujeron los fallos de paginación anteriores. La suite existente de 98 pruebas no cubría estos casos. Sus resultados anteriores siguen siendo evidencia válida de su propio alcance, no de ausencia de defectos.
- Backend: cargo fmt --check aprobado; cargo test --locked con 87 pruebas aprobadas y 4 ignoradas por defecto, ejecutados nuevamente tras las correcciones.
- Integración real: recorrido de seis módulos aprobado contra CouchDB; usó seis bases nuevas aisladas y confirmó su eliminación. Incluye listas vacías, paginación, permisos, revisiones e idempotencia.
- Windows: pruebas DPAPI con tamaños hasta 12 MiB, reapertura/reemplazo y compatibilidad con el cifrado anterior. Están incluidas en la suite Flutter.
- Docker: imagen compilada, backend actualizado y endpoint de salud comprobado durante esta sesión. El endpoint de salud no acredita por sí solo todos los módulos.
- No se realizó en esta revisión un recorrido manual completo de todas las pantallas con los tres roles, una prueba de carga ni una instalación limpia en otra máquina.

## Limitaciones declaradas, no funcionalidades prometidas pendientes

- Los pagos y aportes son simulados; no hay integración bancaria real.
- La verificación DTE es manual; no consulta oficialmente a Hacienda.
- El cliente soportado es Windows. Web requiere CORS adicional y no se acredita soporte móvil.
- El modo local requiere login inicial en línea y solo encola operaciones concretas de empresas/facturas.
- La primera cuenta administradora requiere preparación manual autorizada.
- Los estados del modelo de inversión no implican endpoints para todas las transiciones; la documentación lo advierte.
- La API no ofrece recuperación de contraseña ni renovación/revocación de JWT; está expresamente indicado en Usuarios.

## Mejoras de entrega recomendadas

La automatización de .github/workflows/backend-rust.yml solo cubre Rust. Incorporar Flutter en Windows y el recorrido aislado con CouchDB reduciría regresiones; su ausencia no significa que falte un módulo. Registrar la evidencia actual junto a las comprobaciones históricas de docs/integracion y hacer una aceptación manual con PYME, inversionista y administrador antes de entregar.

Las correcciones modifican el cliente y la documentación. Las pruebas reales crean y eliminan únicamente sus propias bases aisladas; no modifican datos habituales de la aplicación. No se atribuye a la aceptación automatizada el carácter de una revisión manual integral de la interfaz.

## Aceptación funcional de los tres roles

La prueba real real_couchdb_isolated_six_module_lifecycle pasó nuevamente el 9 de noviembre de 2026. Registra cuentas ficticias y prepara al administrador exclusivamente dentro de las bases aisladas.

| Paso | Rol | Resultado comprobado |
|---|---|---|
| Registro de empresa e idempotencia | PYME | Una empresa, sin duplicados; listados y paginación correctos. |
| Aprobación con revisión | Administrador | Empresa activa; decisión de PYME rechazada. |
| Registro de factura | PYME | Una factura, sin duplicados. |
| Verificación manual de DTE | Administrador | Factura disponible; verificación de PYME rechazada. |
| Publicación de oferta | PYME | Oferta creada para la factura verificada. |
| Aporte y confirmación simulados | Inversionista | Un aporte con reintento idempotente y confirmación. |
| Emisión del crédito | Administrador | Crédito emitido; emisión de PYME rechazada. |
| Pago completo y repetición | PYME | Saldo cero y un único pago. |
| Liquidación y reportes | Roles autorizados | Factura pagada, inversión liquidada, ocho reportes y evento de pago en auditoría. |

Las pruebas Flutter cubren por separado navegación por rol, formularios, permisos, conflictos, pagos, reportes y estados de error. Esto verifica las capas automáticamente; no sustituye una aceptación visual manual completa ni una prueba de instalación en otro equipo.
