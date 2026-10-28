import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:plataforma_credito/modules/usuarios/screens/registro_usuario_screen.dart';
import 'package:plataforma_credito/services/api_client.dart';

void main() {
  testWidgets('Envía el registro, bloquea duplicados y confirma al recibir 201', (tester) async {
    final response = Completer<http.Response>();
    var requests = 0;
    final api = ApiClient(httpClient: MockClient((request) {
      requests++;
      expect(request.method, 'POST');
      expect(request.url.path, '/api/auth/register');
      expect(jsonDecode(request.body), {
        'nombre': 'Prueba', 'correo': 'prueba@example.test',
        'password': 'Prueba-123456!', 'rol': 'pyme',
      });
      return response.future;
    }));
    addTearDown(api.close);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: RegistroUsuarioScreen(
      onGuardar: (datos) async { await api.post('/api/auth/register', datos); },
    ))));
    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), 'Prueba');
    await tester.enterText(fields.at(1), 'prueba@example.test');
    await tester.enterText(fields.at(2), 'Prueba-123456!');
    final button = find.widgetWithText(FilledButton, 'Crear cuenta');
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pump();
    expect(find.text('Cuenta creada correctamente.'), findsNothing);
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed, isNull);
    response.complete(http.Response('{"id":"usuario:prueba"}', 201));
    await tester.pumpAndSettle();
    expect(requests, 1);
    expect(find.text('Cuenta creada correctamente.'), findsOneWidget);
    expect(tester.widget<TextFormField>(fields.at(2)).controller!.text, isEmpty);
  });

  testWidgets('Muestra el conflicto y conserva los datos para corregirlos', (tester) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: RegistroUsuarioScreen(
      onGuardar: (_) async { throw ApiException('Correo ya registrado', 409); },
    ))));
    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), 'Prueba');
    await tester.enterText(fields.at(1), 'prueba@example.test');
    await tester.enterText(fields.at(2), 'Prueba-123456!');
    final button = find.widgetWithText(FilledButton, 'Crear cuenta');
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(find.text('Correo ya registrado'), findsOneWidget);
    expect(find.text('Cuenta creada correctamente.'), findsNothing);
    expect(tester.widget<FilledButton>(button).onPressed, isNotNull);
    expect(tester.widget<TextFormField>(fields.at(1)).controller!.text, 'prueba@example.test');
  });
}
