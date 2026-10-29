# Módulo Usuarios

Pantallas: screens/ · Componentes: widgets/ · Estado: providers/.

## Acceso a la aplicación

La aplicación principal abre `LoginScreen`. Desde allí se puede iniciar sesión o
abrir el formulario de registro existente. Al registrar una cuenta, se regresa al
login con el correo completado; la contraseña no se conserva.

`SesionProvider` usa el `ApiClient` existente y `POST /api/auth/login`. Conserva el
usuario y el token únicamente en memoria, y comparte el cliente autenticado con
el servicio de facturas. No se necesita `API_TOKEN` en el punto de entrada principal.

La pestaña Usuarios muestra nombre, correo, rol y cierre de sesión. Al cerrar,
vencer `expires_in` o recibir un 401 en una solicitud autenticada, se elimina el
token y se reconstruye la navegación y el provider de facturas para no conservar
datos de la cuenta anterior. Un 403 se muestra como error de permisos sin cerrar
la sesión. Al volver a abrir la aplicación es necesario ingresar de nuevo.

Se mantienen las pantallas y servicios existentes de Empresas y Facturas. El
formulario de Empresas conserva su integración pendiente. `main_prueba.dart`,
Créditos y Administración no se modifican. La autorización por rol continúa en el
backend. No hay endpoints de recuperación de contraseña ni renovación de token.

Ejecutar desde `Frontend/plataforma_credito`:

```powershell
flutter run -d windows
flutter test test/sesion_test.dart test/registro_usuario_test.dart
```

El backend debe estar disponible en la URL de `ApiConfig`, con CouchDB y
`JWT_SECRET` configurados; consultar `docs/api/usuarios.md`.
