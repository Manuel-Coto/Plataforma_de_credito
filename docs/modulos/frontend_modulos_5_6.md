# Frontend de los módulos 5 y 6

Plataforma de Crédito Colaborativo, Proyecto 2.
Módulo 5: Créditos, operaciones y pagos. Módulo 6: Administración y reportes.
Tecnología: Flutter / Dart. Rama de trabajo: `feature/frontend-creditos-admin`.

## 1. Propósito

Mostrar al usuario el seguimiento de las operaciones de crédito con sus pagos simulados (módulo 5) y ofrecer al administrador un panel con indicadores generales (módulo 6).

El frontend no se conecta a CouchDB. Todos los datos se solicitan al backend en Rust por HTTP/JSON, que aplica las reglas de negocio y los permisos.

## 2. Pantallas

| Módulo | Pantalla | Archivo | Qué muestra |
|---|---|---|---|
| 5 | Créditos y pagos | `lib/modules/creditos/screens/operaciones_screen.dart` | Listado de operaciones con filtro por estado y barra de progreso de pago |
| 5 | Detalle de operación | `lib/modules/creditos/screens/operacion_detalle_screen.dart` | Monto, estado, vencimiento, total pagado e historial de pagos simulados |
| 6 | Panel de administración | `lib/modules/administracion/screens/dashboard_screen.dart` | Indicadores (operaciones, monto total, empresas verificadas, facturas pendientes) y operaciones por estado |

## 3. Estructura de archivos

```
lib/
  core/format.dart                      Formato de dinero, fechas y estados
  models/operacion.dart                 Modelos Operacion y Pago
  models/resumen.dart                   Modelo Resumen del panel
  services/api_client.dart              Cliente HTTP hacia el backend
  modules/creditos/providers/           OperacionesProvider
  modules/creditos/screens/             Listado y detalle
  modules/administracion/providers/     ReportesProvider
  modules/administracion/screens/       Panel
  main_prueba.dart                      Punto de entrada solo para pruebas
```

Gestión de estado: `provider`. Navegación: `go_router`. Formato: `intl`. Peticiones: `http`.

## 4. Endpoints que consume

| Método | Ruta | Pantalla |
|---|---|---|
| GET | `/api/operaciones` | Listado y detalle de operaciones |
| GET | `/api/reportes/resumen` | Panel de administración |

La dirección del backend se define en `ApiClient` (por defecto `http://127.0.0.1:8080`). El token de autenticación, cuando exista el módulo 1, se asigna en `ApiClient.token` y se envía como `Authorization: Bearer`.

## 5. Formato JSON esperado (supuesto, por confirmar con el backend)

`GET /api/operaciones` devuelve una lista:

```json
[{
  "_id": "operacion_001",
  "factura_id": "factura_001",
  "monto_centavos": 200000,
  "moneda": "USD",
  "estado": "activa",
  "fecha_vencimiento": "2026-12-15",
  "pagos": [{ "_id": "pago_001", "monto_centavos": 50000, "fecha": "2026-11-01", "estado": "pagado" }]
}]
```

`GET /api/reportes/resumen` devuelve un objeto:

```json
{
  "total_operaciones": 12,
  "monto_total_centavos": 2400000,
  "empresas_verificadas": 5,
  "facturas_pendientes": 3,
  "operaciones_por_estado": { "activa": 7, "pagada": 4, "vencida": 1 }
}
```

Los montos se manejan en centavos (enteros) para evitar errores de redondeo, igual que el ejemplo de factura de la guía.

## 6. Cómo probarlo

```
cd Frontend/plataforma_credito
flutter pub get
flutter run -d windows -t lib/main_prueba.dart
```

(En Linux, usar `-d linux`.) Sin el backend activo, las pantallas muestran el mensaje "No se pudo conectar con el servidor" con un botón para reintentar.

## 7. Estado actual y pendientes

- Las pantallas compilan y se ejecutan; el manejo de error de conexión está verificado.
- No se han probado con el backend real: los nombres de campo del JSON son supuestos.
- Pendiente: conectar con los endpoints reales y ajustar los modelos al formato definido por el equipo.
- Pendiente: auditoría y exportación de reportes (módulo 6), que aún no tienen endpoint definido.
- Pendiente: integrar las rutas en el `main.dart` del equipo, usando `context.push` para que cada pantalla tenga botón de regreso.
- Los pagos y operaciones son simulados; no se manejan fondos reales.
