import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'modules/empresas/screens/empresa_form_screen.dart';
import 'modules/facturas/providers/facturas_provider.dart';
import 'modules/facturas/screens/facturas_lista_screen.dart';
import 'modules/usuarios/screens/registro_usuario_screen.dart';
import 'services/api_client.dart';
import 'services/factura_service.dart';

// Se lee al ejecutar con --dart-define; no queda escrito en el código ni en Git.
const String _token = String.fromEnvironment('API_TOKEN');

void main() => runApp(const PlataformaCreditoApp());

class PlataformaCreditoApp extends StatelessWidget {
  const PlataformaCreditoApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Crea el provider de facturas una sola vez para toda la app.
    return ChangeNotifierProvider(
      create: (_) => FacturasProvider(
        FacturaService(
          ApiClient(token: _token.isEmpty ? null : _token),
        ),
      ),
      child: MaterialApp(
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
        home: DefaultTabController(
          length: 3,
          child: Builder(
            builder: (context) => Scaffold(
              appBar: AppBar(
                title: const Row(
                  children: [
                    Icon(Icons.account_balance_rounded,
                        color: Color(0xFF176B68)),
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
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}