import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:plataforma_credito/modules/usuarios/providers/sesion_provider.dart';
import 'package:plataforma_credito/services/api_client.dart';
import 'package:plataforma_credito/modules/usuarios/screens/cuenta_screen.dart';
import 'package:provider/provider.dart';

Map<String, dynamic> perfil(String nombre) => {
      'id': 'usuario:prueba',
      'nombre': nombre,
      'correo': 'perfil@example.test',
      'rol': 'pyme',
      'estado': 'activo',
    };

http.Response login() => http.Response(
    jsonEncode({
      'access_token': 'token-perfil',
      'token_type': 'Bearer',
      'expires_in': 3600,
      'usuario': perfil('Nombre anterior'),
    }),
    200);

void main() {
  test('Un segundo guardado pendiente falla explícitamente y no informa éxito',
      () async {
    final pendiente = Completer<http.Response>();
    final iniciado = Completer<void>();
    var peticiones = 0;
    final api = ApiClient(httpClient: MockClient((request) async {
      if (request.url.path == '/api/auth/login') return login();
      peticiones++;
      if (!iniciado.isCompleted) {
        iniciado.complete();
      }
      return pendiente.future;
    }));
    final sesion = SesionProvider(api);
    addTearDown(sesion.dispose);
    await sesion.ingresar('perfil@example.test', 'Prueba-123456!');
    final primero = sesion.actualizarPerfil('Primer cambio');
    await iniciado.future;
    await expectLater(
        sesion.actualizarPerfil('Segundo cambio'),
        throwsA(isA<ApiException>().having(
            (e) => e.message, 'mensaje', contains('Ya se está guardando'))));
    expect(peticiones, 1);
    expect(sesion.guardandoPerfil, isTrue);
    expect(sesion.usuario!['nombre'], 'Nombre anterior');
    pendiente.complete(http.Response(jsonEncode(perfil('Primer cambio')), 200));
    await primero;
    expect(sesion.usuario!['nombre'], 'Primer cambio');
  });

  testWidgets(
      'El modal permanece abierto durante el PUT aunque se intente salir',
      (tester) async {
    final pendiente = Completer<http.Response>();
    var peticiones = 0;
    final sesion =
        SesionProvider(ApiClient(httpClient: MockClient((request) async {
      if (request.url.path == '/api/auth/login') return login();
      peticiones++;
      return pendiente.future;
    })));
    await sesion.ingresar('perfil@example.test', 'Prueba-123456!');
    await tester.pumpWidget(ChangeNotifierProvider(
        create: (_) => sesion,
        child: const MaterialApp(home: Scaffold(body: CuentaScreen()))));
    final editar = find.widgetWithText(OutlinedButton, 'Editar perfil');
    await tester.ensureVisible(editar);
    await tester.tap(editar);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), 'Nombre guardado');
    await tester.tap(find.text('Guardar nombre'));
    await tester.pump();
    expect(peticiones, 1);
    await tester.tapAt(const Offset(4, 4));
    await tester.pump();
    final dialogo = tester.element(find.byType(AlertDialog));
    await Navigator.of(dialogo).maybePop();
    await tester.pump();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, 'Cancelar'))
            .onPressed,
        isNull);
    expect(find.text('Perfil actualizado.'), findsNothing);
    pendiente
        .complete(http.Response(jsonEncode(perfil('Nombre guardado')), 200));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('Perfil actualizado.'), findsOneWidget);
    expect(peticiones, 1);
  });

  test('Un cambio de rol limpia la versión de proveedores y conserva token',
      () async {
    final api = ApiClient(httpClient: MockClient((request) async {
      if (request.url.path == '/api/auth/login') return login();
      return http.Response(
          jsonEncode({...perfil('Nombre actualizado'), 'rol': 'inversionista'}),
          200);
    }));
    final sesion = SesionProvider(api);
    addTearDown(sesion.dispose);
    await sesion.ingresar('perfil@example.test', 'Prueba-123456!');
    final version = sesion.version;
    await sesion.actualizarPerfil('Nombre actualizado');
    expect(sesion.usuario!['rol'], 'inversionista');
    expect(sesion.version, version + 1);
    expect(sesion.autenticado, isTrue);
    expect(api.token, 'token-perfil');
  });

  test('Editar nombre conserva token, versión de navegación y cuenta',
      () async {
    final api = ApiClient(httpClient: MockClient((request) async {
      if (request.url.path == '/api/auth/login') return login();
      expect(request.method, 'PUT');
      expect(request.url.path, '/api/usuarios/me');
      expect(request.headers['Authorization'], 'Bearer token-perfil');
      expect(jsonDecode(request.body), {'nombre': 'Nombre actualizado'});
      return http.Response(jsonEncode(perfil('Nombre actualizado')), 200);
    }));
    final sesion = SesionProvider(api);
    addTearDown(sesion.dispose);
    await sesion.ingresar('perfil@example.test', 'Prueba-123456!');
    final version = sesion.version;
    await sesion.actualizarPerfil('  Nombre actualizado  ');
    expect(sesion.usuario!['nombre'], 'Nombre actualizado');
    expect(sesion.version, version);
    expect(api.token, 'token-perfil');
    expect(sesion.guardandoPerfil, isFalse);
  });

  test('Una respuesta de perfil pendiente no revive una sesión cerrada',
      () async {
    final respuesta = Completer<http.Response>();
    final api = ApiClient(httpClient: MockClient((request) async {
      if (request.url.path == '/api/auth/login') return login();
      return respuesta.future;
    }));
    final sesion = SesionProvider(api);
    addTearDown(sesion.dispose);
    await sesion.ingresar('perfil@example.test', 'Prueba-123456!');
    final guardado = sesion.actualizarPerfil('Nombre que llega tarde');
    sesion.cerrar();
    respuesta.complete(
        http.Response(jsonEncode(perfil('Nombre que llega tarde')), 200));
    await guardado;
    expect(sesion.usuario, isNull);
    expect(api.token, isNull);
    expect(sesion.guardandoPerfil, isFalse);
  });
}
