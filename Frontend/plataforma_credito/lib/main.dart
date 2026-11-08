import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'modules/administracion/providers/reportes_provider.dart';
import 'modules/creditos/providers/operaciones_provider.dart';
import 'modules/facturas/providers/facturas_provider.dart';
import 'modules/usuarios/providers/sesion_provider.dart';
import 'modules/usuarios/screens/login_screen.dart';
import 'services/api_client.dart';
import 'services/factura_service.dart';
import 'core/theme/credito_theme.dart';
import 'widgets/app_shell.dart';

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
            ChangeNotifierProvider<FacturasProvider>(
              create: (_) => _FacturasDeSesion(FacturaService(sesion.api)),
            ),
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
            theme: CreditoTheme.light,
            home: !sesion.autenticado ? const LoginScreen() : const AppShell(),
          ),
        ),
      ),
    );
  }
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
