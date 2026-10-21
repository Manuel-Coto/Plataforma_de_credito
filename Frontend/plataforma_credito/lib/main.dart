import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'modules/facturas/providers/facturas_provider.dart';
import 'modules/facturas/screens/factura_lista_screen.dart';
import 'services/api_client.dart';
import 'services/factura_service.dart';

// Se lee al ejecutar con --dart-define; no queda escrito en el código ni en Git.
const String _token = String.fromEnvironment('API_TOKEN');

void main() => runApp(const PlataformaCreditoApp());

class PlataformaCreditoApp extends StatelessWidget {
  const PlataformaCreditoApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Crea el provider una sola vez y lo deja disponible para toda la app.
    return ChangeNotifierProvider(
      create: (_) => FacturasProvider(
        FacturaService(
          ApiClient(token: _token.isEmpty ? null : _token),
        ),
      ),
      child: MaterialApp(
        title: 'Plataforma de Crédito Colaborativo',
        theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.blue),
        home: const FacturasListaScreen(),
      ),
    );
  }
}