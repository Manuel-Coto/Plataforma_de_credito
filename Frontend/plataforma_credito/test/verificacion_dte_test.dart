import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:plataforma_credito/models/factura.dart';
import 'package:plataforma_credito/modules/facturas/providers/facturas_provider.dart';
import 'package:plataforma_credito/modules/facturas/screens/factura_detalles_screen.dart';
import 'package:plataforma_credito/modules/usuarios/providers/sesion_provider.dart';
import 'package:plataforma_credito/services/api_client.dart';
import 'package:plataforma_credito/services/factura_service.dart';

Map<String, dynamic> documento(bool verificado) => {
      'id': 'factura-1',
      'empresa_id': 'empresa-1',
      'numero': 'F-001',
      'moneda': 'USD',
      'monto_total_centavos': 100000,
      'monto_financiado_centavos': 0,
      'fecha_emision': '2026-11-01',
      'fecha_vencimiento': '2026-12-01',
      'estado': verificado ? 'disponible' : 'pendiente_verificacion',
      'dte': {
        'codigo_generacion': 'CODIGO-FICTICIO',
        'verificado': verificado,
        'sello_recepcion': verificado ? 'SELLO-TEST' : null,
        'fecha_verificacion': verificado ? '2026-11-07T12:00:00Z' : null
      },
    };

void main() {
  for (final caso in ['correcto', 'conflicto', 'pyme']) {
    testWidgets('Revisión DTE: $caso', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(800, 1800);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      var verificado = false;
      var writes = 0;
      var reads = 0;
      final api = ApiClient(httpClient: MockClient((request) async {
        if (request.url.path == '/api/auth/login') {
          return http.Response(
              jsonEncode({
                'access_token': 'token-test',
                'token_type': 'Bearer',
                'expires_in': 3600,
                'usuario': {
                  'id': 'usuario-test',
                  'nombre': 'Prueba',
                  'correo': 'prueba@example.test',
                  'rol': caso == 'pyme' ? 'pyme' : 'administrador',
                  'estado': 'activo'
                }
              }),
              200);
        }
        expect(request.headers['Authorization'], 'Bearer token-test');
        if (request.method == 'PATCH') {
          writes++;
          expect(request.url.path, '/api/facturas/factura-1/verificar-dte');
          expect(jsonDecode(request.body), {'sello_recepcion': 'SELLO-TEST'});
          verificado = true;
          if (caso == 'conflicto') {
            return http.Response('{"error":"La factura cambio"}', 409);
          }
        }
        if (request.url.path == '/api/facturas') {
          return http.Response(
              jsonEncode({
                'facturas': [documento(verificado)],
                'bookmark': '',
                'limit': 50
              }),
              200);
        }
        if (request.method == 'GET') reads++;
        return http.Response(jsonEncode(documento(verificado)), 200);
      }));
      final session = SesionProvider(api);
      await session.ingresar('prueba@example.test', 'password-test');
      final provider = FacturasProvider(FacturaService(api));
      await tester.pumpWidget(MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: session),
            ChangeNotifierProvider.value(value: provider)
          ],
          child: MaterialApp(
              home: FacturaDetalleScreen(
                  factura: Factura.fromJson(documento(false))))));
      await tester.pumpAndSettle();
      if (caso == 'pyme') {
        expect(find.text('Verificar DTE'), findsNothing);
        expect(writes, 0);
      } else {
        final button = find.text('Verificar DTE');
        await tester.ensureVisible(button);
        await tester.tap(button);
        await tester.pumpAndSettle();
        expect(find.text('Escribe el sello de recepción del DTE.'),
            findsOneWidget);
        expect(writes, 0);
        await tester.enterText(find.byType(TextField), '  SELLO-TEST  ');
        await tester.ensureVisible(button);
        await tester.tap(button);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Confirmar verificación'));
        await tester.pumpAndSettle();
        expect(writes, 1);
        expect(find.text('Verificar DTE'), findsNothing);
        if (caso == 'conflicto') {
          expect(reads, 2);
          expect(find.textContaining('La factura cambió'), findsOneWidget);
        } else {
          expect(provider.facturas.single.dte.verificado, isTrue);
        }
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      provider.dispose();
      session.dispose();
      api.close();
    });
  }
}
