# Cliente Flutter de la Plataforma de Crédito Colaborativo

Aplicación de escritorio Windows conectada a la API Rust mediante HTTP/JSON. La dirección predeterminada es http://127.0.0.1:3000 y se configura en lib/core/config/api_config.dart.

## Ejecutar

Preparar CouchDB y el backend como indica el [README principal](../../README.md). Después:

```powershell
flutter pub get
flutter run -d windows
```

El punto de entrada es lib/main.dart. No ejecutar flutter create sobre el proyecto existente.

## Navegación y permisos

La interfaz ofrece inicio/cuenta, empresas, facturas, créditos, administración y ofertas/inversiones. Los destinos se adaptan al rol: las cuentas inversionistas no reciben gestión de empresas y las cuentas no administrativas no reciben el panel de administración. La API vuelve a comprobar todos los permisos.

- PYME: gestiona sus empresas y facturas, publica ofertas y consulta/paga sus créditos.
- Inversionista: consulta ofertas, aporta y confirma aportes simulados y sigue sus inversiones/créditos.
- Administrador: revisa empresas y DTE, emite créditos, gestiona usuarios y consulta reportes/auditoría.

Los formularios conservan los datos cuando hay errores. Los cambios de revisión requieren consultar los datos actuales antes de volver a guardar. Editar el nombre mantiene el token y la navegación; si el servidor comunica un cambio de rol, se invalidan los datos y rutas cargados con los permisos anteriores.

## Sesión y datos locales

El JWT vive exclusivamente en memoria y se envía como Bearer a la API. No se guarda en las preferencias ni en la cola local. Una nueva ejecución requiere iniciar sesión en línea.

La lectura de instantáneas y las solicitudes locales permitidas utilizan almacenamiento cifrado con DPAPI en Windows. Hay una acción explícita para sincronizar, tratamiento visible de conflictos y eliminación de datos/pendientes al cerrar sesión, recibir 401 o cambiar de rol. Consultar el [contrato offline](../../docs/integracion/offline_windows.md) para el alcance exacto. Enviar aportes, pagos, ofertas, verificación de DTE o cambios administrativos requiere conexión y no se encola.

## Pruebas

```powershell
flutter analyze
flutter test
```

Las pruebas usan respuestas HTTP ficticias para verificar contratos reales, permisos de navegación, errores, estados vacíos, revisión de empresas, pagos, gestión de usuarios y comportamiento adaptable. El recorrido contra una instalación real de CouchDB se ejecuta desde el backend siguiendo [estas instrucciones](../../docs/integracion/couchdb_real.md).

El cliente no conecta directamente con CouchDB. Los pagos son simulados y el DTE se marca mediante una decisión administrativa, sin validación externa automática.
