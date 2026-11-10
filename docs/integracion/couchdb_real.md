# Prueba de integración con CouchDB real

La prueba real_couchdb_isolated_six_module_lifecycle, en [real_integration_tests.rs](../../Backend/credito_backend/src/real_integration_tests.rs), ejecuta el Router real construido por build_app contra una instalación local de Apache CouchDB. No utiliza respuestas simuladas de base de datos.

## Preparación

1. Iniciar CouchDB local y completar COUCHDB_URL, COUCHDB_USERNAME y COUCHDB_PASSWORD en Backend/credito_backend/.env.
2. La cuenta CouchDB debe poder crear y eliminar bases. La prueba solo admite localhost, 127.0.0.1 o ::1 y rechaza credenciales incluidas en la URL.
3. Ejecutar desde Backend/credito_backend:

```powershell
cargo test --locked real_integration_tests::real_couchdb_isolated_six_module_lifecycle -- --ignored --nocapture --test-threads=1
```

Está marcada ignore para que cargo test normal no acceda a una instalación real ni necesite .env. Ejecutar --ignored con el nombre exacto de esta prueba; otras pruebas reales antiguas del repositorio usan las bases habituales y tienen sus propias condiciones.

## Aislamiento y limpieza

- Se generan seis bases nuevas credito_codex_it_<nonce_aleatorio>_<base>.
- Un proxy HTTP de prueba, limitado a loopback, reescribe únicamente usuarios, empresas, facturas, ofertas, operaciones y auditoria hacia esas bases. No dirige solicitudes a las bases habituales.
- Solo se registra una base como propia tras recibir 201 al crearla. Una colisión 412 aborta: no se reclama ni elimina una base previa.
- Se crean cuentas, empresa, factura, oferta, aporte, crédito y pago exclusivamente ficticios. La cuenta administradora inicial se prepara dentro de la base aislada recién creada.
- El recorrido se ejecuta en una tarea controlada; tanto si termina como si una aserción falla, se intenta eliminar exclusivamente las seis bases registradas por esa ejecución. Una limpieza incompleta hace fallar la prueba.
- No se modifica .env ni la clave JWT de la API que pudiera estar ejecutándose. La clave sintética de prueba existe solo en el proceso de pruebas. No se imprimen credenciales, hashes, tokens ni errores Debug con URL de solicitudes.

## Qué verifica

Registro/login reales, permisos, paginación de usuarios, revisión de empresa con ETag, registro y verificación administrativa de DTE, publicación de oferta, aporte con clave idempotente y repetición, confirmación, emisión de crédito, pago completo y repetición, liquidación, los ocho reportes y auditoría con filtros combinados.

También comprueba que repetir la creación de empresa o factura con la misma clave conserva su ID y estado ya aprobado/verificado; reutilizar la clave con contenido diferente produce 409. Un PUT de empresa con If-Match obsoleto produce 412. Las respuestas públicas no exponen hashes ni huellas internas de creación. Los contadores finales de empresas, facturas, inversiones, créditos y pagos son uno, sin duplicados.

## Última ejecución comprobada

El 8 de noviembre de 2026 se ejecutó la versión final contra CouchDB local: **1 prueba aprobada, 0 fallos**, incluidos los controles de metadatos privados y revisión obsoleta. Se crearon y eliminaron las seis bases aisladas. La suite general del backend se ejecutó por separado con **84 pruebas aprobadas**, sin fallos; sus pruebas reales quedan excluidas por defecto. Esta evidencia cubre el recorrido indicado; no constituye una prueba de carga, de banca real ni de validación externa tributaria.

## Verificación actualizada: 9 de noviembre de 2026

Se ejecutaron nuevamente cargo fmt --check, cargo test --locked (87 aprobadas y 4 ignoradas por defecto) y el recorrido aislado real_couchdb_isolated_six_module_lifecycle (1 aprobado). El recorrido verificó los tres roles, empresa, factura, oferta, aporte, crédito, pago completo, liquidación, reportes, auditoría y listas vacías/paginación. Se confirmó la eliminación de las seis bases creadas por esa ejecución. La aceptación fue automatizada a través de la API real, separada de las pruebas de pantallas Flutter.
