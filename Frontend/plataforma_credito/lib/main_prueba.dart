// Punto de entrada SOLO para probar los módulos Créditos y Administración
// sin tocar el main.dart del equipo:
//   flutter run -d linux -t lib/main_prueba.dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:plataforma_credito/services/api_client.dart';
import 'package:plataforma_credito/models/operacion.dart';
import 'package:plataforma_credito/modules/creditos/providers/operaciones_provider.dart';
import 'package:plataforma_credito/modules/creditos/screens/operaciones_screen.dart';
import 'package:plataforma_credito/modules/creditos/screens/operacion_detalle_screen.dart';
import 'package:plataforma_credito/modules/administracion/providers/reportes_provider.dart';
import 'package:plataforma_credito/modules/administracion/screens/dashboard_screen.dart';

final _api = ApiClient(baseUrl: 'http://127.0.0.1:8080');

final _router = GoRouter(routes: [
  GoRoute(path: '/', builder: (_, __) => const _Inicio()),
  GoRoute(path: '/operaciones', builder: (_, __) => const OperacionesScreen()),
  GoRoute(
    path: '/operaciones/:id',
    builder: (_, s) => OperacionDetalleScreen(operacion: s.extra as Operacion),
  ),
  GoRoute(path: '/admin', builder: (_, __) => const DashboardScreen()),
]);

void main() => runApp(MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => OperacionesProvider(_api)),
        ChangeNotifierProvider(create: (_) => ReportesProvider(_api)),
      ],
      child: MaterialApp.router(
        title: 'Plataforma de Crédito Colaborativo',
        theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.blue),
        routerConfig: _router,
      ),
    ));

class _Inicio extends StatelessWidget {
  const _Inicio();
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Prueba: módulos 5 y 6')),
        body: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            FilledButton(
                onPressed: () => context.push('/operaciones'),
                child: const Text('Créditos y pagos')),
            const SizedBox(height: 12),
            FilledButton(
                onPressed: () => context.push('/admin'),
                child: const Text('Panel de administración')),
          ]),
        ),
      );
}
