import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'models/operacion.dart';
import 'modules/administracion/providers/reportes_provider.dart';
import 'modules/administracion/screens/dashboard_screen.dart';
import 'modules/creditos/providers/operaciones_provider.dart';
import 'modules/creditos/screens/operacion_detalle_screen.dart';
import 'modules/creditos/screens/operaciones_screen.dart';
import 'modules/empresas/screens/empresa_form_screen.dart';
import 'modules/facturas/providers/facturas_provider.dart';
import 'modules/facturas/screens/factura_lista_screen.dart';
import 'modules/usuarios/screens/registro_usuario_screen.dart';
import 'services/api_client.dart';
import 'services/factura_service.dart';

// Se lee al ejecutar con --dart-define; no queda escrito en el código ni en Git.
const String _token = String.fromEnvironment('API_TOKEN');

// Cliente para créditos y administración (el mismo de main_prueba.dart).
final _apiCreditos = ApiClient(
  baseUrl: 'http://127.0.0.1:8080',
  token: _token.isEmpty ? null : _token,
);

final _router = GoRouter(routes: [
  GoRoute(path: '/', builder: (_, __) => const _InicioTabs()),
  GoRoute(
    path: '/operaciones/:id',
    builder: (_, s) => OperacionDetalleScreen(operacion: s.extra as Operacion),
  ),
]);

void main() => runApp(const PlataformaCreditoApp());

class PlataformaCreditoApp extends StatelessWidget {
  const PlataformaCreditoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        // Facturas (de tus compañeros)
        ChangeNotifierProvider(
          create: (_) => FacturasProvider(
            FacturaService(ApiClient(token: _token.isEmpty ? null : _token)),
          ),
        ),
        // Tus módulos
        ChangeNotifierProvider(create: (_) => OperacionesProvider(_apiCreditos)),
        ChangeNotifierProvider(create: (_) => ReportesProvider(_apiCreditos)),
      ],
      child: MaterialApp.router(
        title: 'Plataforma de Crédito Colaborativo',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF176B68)),
          scaffoldBackgroundColor: const Color(0xFFF5F7FA),
          appBarTheme: const AppBarTheme(
            backgroundColor: Colors.white,
            foregroundColor: Color(0xFF172B4D),
            surfaceTintColor: Colors.transparent,
          ),
        ),
        routerConfig: _router,
      ),
    );
  }
}

class _InicioTabs extends StatelessWidget {
  const _InicioTabs();

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 5,
      child: Builder(
        builder: (context) => Scaffold(
          appBar: AppBar(
            title: const Row(
              children: [
                Icon(Icons.account_balance_rounded, color: Color(0xFF176B68)),
                SizedBox(width: 12),
                Text('Plataforma de Crédito'),
              ],
            ),
            bottom: const TabBar(
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              tabs: [
                Tab(icon: Icon(Icons.person_outline), text: 'Usuarios'),
                Tab(icon: Icon(Icons.business_outlined), text: 'Empresas'),
                Tab(icon: Icon(Icons.receipt_long_outlined), text: 'Facturas'),
                Tab(icon: Icon(Icons.payments_outlined), text: 'Créditos y pagos'),
                Tab(
                    icon: Icon(Icons.admin_panel_settings_outlined),
                    text: 'Administración'),
              ],
            ),
          ),
          body: TabBarView(
            children: [
              RegistroUsuarioScreen(
                onGuardar: (_) => ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'Formulario validado. Falta conectar el envío al backend.',
                    ),
                  ),
                ),
              ),
              EmpresaFormScreen(
                onGuardar: (_) => ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'Formulario validado. Falta conectar el envío al backend.',
                    ),
                  ),
                ),
              ),
              const FacturasListaScreen(),
              const OperacionesScreen(),
              const DashboardScreen(),
            ],
          ),
        ),
      ),
    );
  }
}