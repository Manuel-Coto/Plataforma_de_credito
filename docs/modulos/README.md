# Distribución de los 6 módulos

| Módulo | Flutter | Rust | CouchDB |
|---|---|---|---|
| 1. Usuarios | Login, registro, perfiles | Roles, autenticación | usuarios |
| 2. Empresas | Formularios y listados | CRUD y validación | empresas |
| 3. Facturas | Registro y consulta | Reglas y verificación | facturas |
| 4. Inversiones | Catálogo y ofertas | Evaluación de ofertas | ofertas |
| 5. Créditos | Seguimiento, pagos simulados | Estados y cálculos | operaciones |
| 6. Administración | Dashboard y reportes | Estadística y auditoría | auditoria |

Esta matriz describe la organización implementada. El modo local es transversal a las lecturas y a una cola limitada de empresas y facturas; las mutaciones financieras y administrativas permanecen en línea. Su alcance exacto está en [Trabajo local Windows](../integracion/offline_windows.md).
