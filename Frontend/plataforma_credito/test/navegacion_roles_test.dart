import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:plataforma_credito/main.dart';
import 'package:plataforma_credito/services/api_client.dart';

void main() {
  for (final rol in ['administrador', 'pyme', 'inversionista']) {
    testWidgets('Navegación muestra los destinos permitidos a $rol',
        (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1440, 1000);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final api = ApiClient(httpClient: MockClient((request) async {
        if (request.url.path == '/api/auth/login') {
          return http.Response(
              jsonEncode({
                'access_token': 'token-rol',
                'token_type': 'Bearer',
                'expires_in': 3600,
                'usuario': {
                  'id': 'cuenta-test',
                  'nombre': 'Cuenta de prueba',
                  'correo': 'cuenta@example.test',
                  'rol': rol,
                  'estado': 'activo'
                }
              }),
              200);
        }
        return http.Response('{"error":"Ruta no prevista en este test"}', 404);
      }));
      await tester.pumpWidget(PlataformaCreditoApp(apiClient: api));
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Correo electrónico'),
          'cuenta@example.test');
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Contraseña'), 'password');
      await tester.tap(find.widgetWithText(FilledButton, 'Iniciar sesión'));
      await tester.pumpAndSettle();
      expect(find.text('Ofertas e inversiones'), findsWidgets);
      if (rol == 'administrador') {
        expect(find.text('Administración'), findsWidgets);
        expect(find.text('Revisar empresas'), findsOneWidget);
      } else {
        expect(find.text('Administración'), findsNothing);
      }
      if (rol == 'inversionista') {
        expect(find.text('Empresas'), findsNothing);
        expect(find.text('Registrar mi empresa'), findsNothing);
      } else {
        expect(find.text('Empresas'), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
}
