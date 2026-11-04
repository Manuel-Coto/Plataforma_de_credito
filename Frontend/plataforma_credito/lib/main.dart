import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/roles.dart';
import 'modules/administracion/providers/reportes_provider.dart';
import 'modules/administracion/screens/dashboard_screen.dart';
import 'modules/creditos/providers/operaciones_provider.dart';
import 'modules/creditos/screens/operaciones_screen.dart';
import 'modules/empresas/screens/empresa_form_screen.dart';
import 'modules/empresas/screens/empresas_pendientes_screen.dart';
import 'modules/facturas/providers/facturas_provider.dart';
import 'modules/facturas/screens/facturas_lista_screen.dart';
import 'modules/usuarios/providers/sesion_provider.dart';
import 'modules/usuarios/screens/cuenta_screen.dart';
import 'modules/usuarios/screens/login_screen.dart';
import 'services/api_client.dart';
import 'services/empresa_service.dart';
import 'services/factura_service.dart';

void main() => runApp(const PlataformaCreditoApp());

class PlataformaCreditoApp extends StatelessWidget {
  const PlataformaCreditoApp({super.key, this.apiClient});
  final ApiClient? apiClient;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => SesionProvider(apiClient ?? ApiClient()),
      child: Consumer<SesionProvider>(
        builder: (context, sesion, _) => MultiProvider(
          key: ValueKey(sesion.version),
          providers: [
            // Facturas (de tus compañeros)
            ChangeNotifierProvider<FacturasProvider>(
              create: (_) => _FacturasDeSesion(FacturaService(sesion.api)),
            ),
            // Tus módulos, con el mismo cliente (y token) de la sesión
            ChangeNotifierProvider<OperacionesProvider>(
              create: (_) => OperacionesProvider(sesion.api),
            ),
            ChangeNotifierProvider<ReportesProvider>(
              create: (_) => ReportesProvider(sesion.api),
            ),
          ],
          child: MaterialApp(
            title: 'Plataforma de Crédito Colaborativo',
            debugShowCheckedModeBanner: false,
            theme: ThemeData(
              useMaterial3: true,
              colorScheme:
              ColorScheme.fromSeed(seedColor: const Color(0xFF176B68)),
              scaffoldBackgroundColor: const Color(0xFFF5F7FA),
              appBarTheme: const AppBarTheme(
                backgroundColor: Colors.white,
                foregroundColor: Color(0xFF172B4D),
                surfaceTintColor: Colors.transparent,
              ),
            ),
            home: !sesion.autenticado
                ? const LoginScreen()
                : _Principal(sesion: sesion),
          ),
        ),
      ),
    );
  }
}

/// Pantalla principal: las pestañas dependen del rol del usuario.
class _Principal extends StatelessWidget {
  const _Principal({required this.sesion});
  final SesionProvider sesion;

  @override
  Widget build(BuildContext context) {
    final secciones = _seccionesPara(sesion.rol, sesion);

    return DefaultTabController(
      // Si cambia el rol (o la sesión), se reconstruye el controlador.
      key: ValueKey('${sesion.version}-${sesion.rol.name}'),
      length: secciones.length,
      child: Scaffold(
        appBar: AppBar(
          actions: [
            IconButton(
              tooltip: 'Cerrar sesión',
              onPressed: sesion.cerrar,
              icon: const Icon(Icons.logout),
            ),
          ],
          title: const Row(
            children: [
              Icon(Icons.account_balance_rounded, color: Color(0xFF176B68)),
              SizedBox(width: 12),
              Text('Plataforma de Crédito'),
            ],
          ),
          bottom: TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [for (final s in secciones) s.tab],
          ),
        ),
        body: TabBarView(
          children: [for (final s in secciones) s.pantalla],
        ),
      ),
    );
  }
}

class _Seccion {
  const _Seccion(this.tab, this.pantalla);
  final Tab tab;
  final Widget pantalla;
}

List<_Seccion> _seccionesPara(Rol rol, SesionProvider sesion) {
  const usuarios = Tab(icon: Icon(Icons.person_outline), text: 'Usuarios');
  const empresas = Tab(icon: Icon(Icons.business_outlined), text: 'Empresas');
  const facturas =
  Tab(icon: Icon(Icons.receipt_long_outlined), text: 'Facturas');
  const creditos =
  Tab(icon: Icon(Icons.payments_outlined), text: 'Créditos y pagos');
  const admin = Tab(
      icon: Icon(Icons.admin_panel_settings_outlined), text: 'Administración');

  return switch (rol) {
    Rol.pyme => [
      const _Seccion(usuarios, CuentaScreen()),
      _Seccion(
        empresas,
        EmpresaFormScreen(
          onGuardar: (datos) => EmpresaService(sesion.api).crear(datos),
        ),
      ),
      const _Seccion(facturas, FacturasListaScreen()),
      const _Seccion(creditos, OperacionesScreen()),
    ],
    Rol.inversionista => [
      const _Seccion(usuarios, CuentaScreen()),
      const _Seccion(facturas, FacturasListaScreen()),
      const _Seccion(creditos, OperacionesScreen()),
    ],
    Rol.administrador => [
      const _Seccion(usuarios, CuentaScreen()),
      const _Seccion(empresas, EmpresasPendientesScreen()),
      const _Seccion(facturas, FacturasListaScreen()),
      const _Seccion(creditos, OperacionesScreen()),
      const _Seccion(admin, DashboardScreen()),
      // Más adelante: Auditoría
    ],
  };
}

// Mantiene intacto el provider del módulo y descarta notificaciones de
// solicitudes pendientes cuando se destruye la sesión y su navegación.
class _FacturasDeSesion extends FacturasProvider {
  _FacturasDeSesion(super.servicio);
  bool _cerrado = false;

  @override
  void notifyListeners() {
    if (!_cerrado) super.notifyListeners();
  }

  @override
  void dispose() {
    _cerrado = true;
    super.dispose();
  }
}