# Plataforma de Crédito Colaborativo — Proyecto 2

Estructura inicial para Windows. Frontend Flutter (IntelliJ), backend Rust (RustRover), datos Apache CouchDB (Fauxton).

## Pasos iniciales
1. Instalar Flutter SDK, Visual Studio (Desktop development with C++), Rust toolchain y Apache CouchDB.
2. Para generar el proyecto Flutter completo: desde `frontend/` ejecutar `flutter create --platforms=windows plataforma_credito` **solo si aún no existe el proyecto**. Este ZIP ya incluye una base Flutter funcional; ejecutar `flutter pub get` dentro de `frontend/plataforma_credito` y, si falta la carpeta windows, `flutter create --platforms=windows .`.
3. Abrir `frontend/plataforma_credito` en IntelliJ y `backend/credito_backend` en RustRover.
4. En `backend/credito_backend` ejecutar `cargo run`; probar http://127.0.0.1:3000/api/health.
5. Entrar a Fauxton: http://127.0.0.1:5984/_utils/; crear bases usuarios, empresas, facturas, ofertas, operaciones y auditoria.

**Nota:** archivos de los módulos son plantillas, no funcionalidades financieras implementadas. Mantener claves en variables de entorno, nunca en Git.
