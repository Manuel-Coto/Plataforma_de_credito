import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:plataforma_credito/core/theme/credito_theme.dart';
import 'package:plataforma_credito/modules/usuarios/providers/sesion_provider.dart';
import 'package:plataforma_credito/modules/usuarios/screens/usuarios_gestion_screen.dart';
import 'package:plataforma_credito/services/api_client.dart';

Map<String, dynamic> perfil(String id, {String rol = 'pyme'}) => {
      'id': id,
      'nombre': id == 'admin' ? 'Cuenta administradora' : 'Cuenta de empresa',
      'correo': '$id@example.test',
      'rol': rol,
      'estado': 'activo',
      'fecha_creacion': '2026-11-08T10:00:00Z',
      'fecha_actualizacion': '2026-11-08T10:00:00Z',
    };

Future<SesionProvider> sesionCon(MockClient client) async {
  final sesion = SesionProvider(ApiClient(httpClient: client));
  await sesion.ingresar('admin@example.test', 'Prueba-123456!');
  return sesion;
}

http.Response loginRespuesta({String rol = 'administrador'}) => http.Response(
    jsonEncode({
      'access_token': 'token-prueba',
      'token_type': 'Bearer',
      'expires_in': 3600,
      'usuario': perfil('admin', rol: rol),
    }),
    200);

Widget gestion(SesionProvider sesion) => ChangeNotifierProvider(
    create: (_) => sesion,
    child: MaterialApp(
        theme: CreditoTheme.light,
        home: const Scaffold(body: UsuariosGestionScreen())));

Future<void> cambiarRol(WidgetTester tester) async {
  await tester.tap(find.byType(DropdownButtonFormField<String>).first);
  await tester.pumpAndSettle();
  await tester.tap(find.text('Inversionista').last);
  await tester.pumpAndSettle();
  await tester.tap(find.text('Guardar permisos'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Confirmar cambios'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('Consulta revisión, confirma y envía permisos con If-Match',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var rol = 'pyme';
    var patches = 0;
    final sesion = await sesionCon(MockClient((request) async {
      if (request.url.path == '/api/auth/login') return loginRespuesta();
      expect(request.headers['Authorization'], 'Bearer token-prueba');
      if (request.url.path == '/api/usuarios') {
        return http.Response(
            jsonEncode({
              'usuarios': [perfil('empresa', rol: rol)],
              'bookmark': 'pagina-1',
              'limit': 25
            }),
            200);
      }
      if (request.method == 'GET') {
        return http.Response(jsonEncode(perfil('empresa', rol: rol)), 200,
            headers: {'etag': '"1-test"'});
      }
      expect(request.method, 'PATCH');
      expect(request.headers['If-Match'], '"1-test"');
      expect(jsonDecode(request.body),
          {'rol': 'inversionista', 'estado': 'activo'});
      patches++;
      rol = 'inversionista';
      return http.Response(jsonEncode(perfil('empresa', rol: rol)), 200);
    }));
    await tester.pumpWidget(gestion(sesion));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cuenta de empresa'));
    await tester.pumpAndSettle();
    await cambiarRol(tester);
    expect(patches, 1);
    expect(find.text('Permisos actualizados.'), findsOneWidget);
    expect(find.text('Inversionista'), findsOneWidget);
  });

  testWidgets('412 bloquea guardar hasta consultar una revisión nueva',
      (tester) async {
    var reads = 0;
    final sesion = await sesionCon(MockClient((request) async {
      if (request.url.path == '/api/auth/login') return loginRespuesta();
      if (request.url.path == '/api/usuarios') {
        return http.Response(
            jsonEncode({
              'usuarios': [perfil('empresa')],
              'bookmark': 'pagina-1',
              'limit': 25
            }),
            200);
      }
      if (request.method == 'GET') {
        reads++;
        return http.Response(jsonEncode(perfil('empresa')), 200,
            headers: {'etag': '"$reads-test"'});
      }
      return http.Response('{"error":"Revision obsoleta"}', 412);
    }));
    await tester.pumpWidget(gestion(sesion));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cuenta de empresa'));
    await tester.pumpAndSettle();
    await cambiarRol(tester);
    expect(find.textContaining('Este usuario cambió'), findsOneWidget);
    expect(
        tester
            .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'Guardar permisos'))
            .onPressed,
        isNull);
    await tester.tap(find.text('Actualizar datos'));
    await tester.pumpAndSettle();
    expect(reads, 2);
    expect(find.textContaining('Este usuario cambió'), findsNothing);
  });

  testWidgets('Una PYME no solicita el listado reservado al administrador',
      (tester) async {
    var listados = 0;
    final sesion = await sesionCon(MockClient((request) async {
      if (request.url.path == '/api/auth/login') {
        return loginRespuesta(rol: 'pyme');
      }
      listados++;
      return http.Response('{"error":"No permitido"}', 403);
    }));
    await tester.pumpWidget(gestion(sesion));
    await tester.pumpAndSettle();
    expect(find.text('Acceso reservado'), findsOneWidget);
    expect(listados, 0);
  });
}
