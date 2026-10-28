import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:plataforma_credito/main.dart';
import 'package:plataforma_credito/modules/usuarios/providers/sesion_provider.dart';
import 'package:plataforma_credito/services/api_client.dart';

http.Response login({String nombre = 'Usuario de prueba', int ttl = 3600}) => http.Response(jsonEncode({
  'access_token': 'token-de-prueba', 'token_type': 'Bearer', 'expires_in': ttl,
  'usuario': {'id': 'usuario:prueba', 'nombre': nombre, 'correo': 'prueba@example.test',
    'rol': 'pyme', 'estado': 'activo'},
}), 200);

Future<void> ingresar(WidgetTester tester) async {
  await tester.enterText(find.widgetWithText(TextFormField, 'Correo electrónico'), 'prueba@example.test');
  await tester.enterText(find.widgetWithText(TextFormField, 'Contraseña'), 'Prueba-123456!');
  await tester.tap(find.widgetWithText(FilledButton, 'Iniciar sesión'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('Login, token en facturas, navegación y cierre sin datos anteriores', (tester) async {
    String? authorization;
    final api = ApiClient(httpClient: MockClient((request) async {
      if (request.url.path == '/api/auth/login') {
        expect(jsonDecode(request.body), {'correo': 'prueba@example.test', 'password': 'Prueba-123456!'});
        return login();
      }
      authorization = request.headers['Authorization'];
      return http.Response('{"error":"Sin permisos de prueba"}', 403);
    }));
    await tester.pumpWidget(PlataformaCreditoApp(apiClient: api));
    expect(find.text('Facturas'), findsNothing);
    await ingresar(tester);
    expect(find.text('Usuario de prueba'), findsOneWidget);
    await tester.tap(find.text('Facturas'));
    await tester.pumpAndSettle();
    expect(authorization, 'Bearer token-de-prueba');
    expect(find.text('Sin permisos de prueba'), findsOneWidget);
    expect(api.token, isNotNull); // 403 no cierra la sesión.
    await tester.tap(find.text('Nueva factura'));
    await tester.pumpAndSettle();
    // Un 401 también debe descartar rutas abiertas sobre la pantalla principal.
    api.onUnauthorized!();
    await tester.pumpAndSettle();
    expect(find.widgetWithText(FilledButton, 'Iniciar sesión'), findsOneWidget);
    expect(find.text('Nueva factura'), findsNothing);
    expect(api.token, isNull);
    await ingresar(tester);
    await tester.tap(find.byTooltip('Cerrar sesión'));
    await tester.pumpAndSettle();
    expect(find.text('Usuario de prueba'), findsNothing);
    expect(api.token, isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Credenciales incorrectas y bloqueo del envío repetido', (tester) async {
    final response = Completer<http.Response>();
    var count = 0;
    final api = ApiClient(httpClient: MockClient((_) { count++; return response.future; }));
    await tester.pumpWidget(PlataformaCreditoApp(apiClient: api));
    await ingresar(tester);
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed, isNull);
    response.complete(http.Response('{"error":"Credenciales incorrectas"}', 401));
    await tester.pumpAndSettle();
    expect(find.text('Credenciales incorrectas'), findsOneWidget);
    expect(find.text('Mi cuenta'), findsNothing);
    expect(count, 1);
    expect(api.token, isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Vencimiento regresa al login y elimina el token', (tester) async {
    final api = ApiClient(httpClient: MockClient((_) async => login(ttl: 5)));
    await tester.pumpWidget(PlataformaCreditoApp(apiClient: api));
    await ingresar(tester);
    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle();
    expect(find.text('Tu sesión terminó. Inicia sesión nuevamente.'), findsOneWidget);
    expect(api.token, isNull);
    await tester.pumpWidget(const SizedBox());
  });

  test('401 protegido limpia sesión; respuesta pendiente no revive sesión cerrada', () async {
    final pending = Completer<http.Response>();
    var calls = 0;
    final api = ApiClient(httpClient: MockClient((request) async {
      if (request.url.path == '/api/auth/login') {
        calls++;
        if (calls == 1) return login();
        return pending.future;
      }
      return http.Response('{"error":"No autorizado"}', 401);
    }));
    final sesion = SesionProvider(api);
    addTearDown(sesion.dispose);
    await sesion.ingresar('prueba@example.test', 'Prueba-123456!');
    await expectLater(api.get('/api/usuarios/me'), throwsA(isA<ApiException>()));
    expect(sesion.autenticado, isFalse);
    expect(api.token, isNull);
    final loginPendiente = sesion.ingresar('prueba@example.test', 'Prueba-123456!');
    sesion.cerrar();
    pending.complete(login());
    await loginPendiente;
    expect(sesion.autenticado, isFalse);
    expect(api.token, isNull);
  });

  testWidgets('Registro vuelve al login con el correo sin iniciar sesión automáticamente', (tester) async {
    final api = ApiClient(httpClient: MockClient((request) async {
      expect(request.url.path, '/api/auth/register');
      return http.Response('{"id":"usuario:nuevo"}', 201);
    }));
    await tester.pumpWidget(PlataformaCreditoApp(apiClient: api));
    await tester.tap(find.text('¿No tienes cuenta? Crear una cuenta'));
    await tester.pumpAndSettle();
    final campos = find.byType(TextFormField);
    await tester.enterText(campos.at(0), 'Cuenta nueva');
    await tester.enterText(campos.at(1), 'nueva@example.test');
    await tester.enterText(campos.at(2), 'Nueva-Prueba-123!');
    final boton = find.widgetWithText(FilledButton, 'Crear cuenta');
    await tester.ensureVisible(boton);
    await tester.tap(boton);
    await tester.pumpAndSettle();
    expect(find.widgetWithText(FilledButton, 'Iniciar sesión'), findsOneWidget);
    expect(find.text('nueva@example.test'), findsOneWidget);
    expect(api.token, isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
