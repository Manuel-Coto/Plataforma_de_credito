import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:plataforma_credito/core/theme/credito_theme.dart';
import 'package:plataforma_credito/modules/empresas/screens/empresa_form_screen.dart';
import 'package:plataforma_credito/modules/usuarios/providers/sesion_provider.dart';
import 'package:plataforma_credito/services/api_client.dart';
import 'package:plataforma_credito/widgets/offline_status.dart';
import 'package:plataforma_credito/widgets/session_actions.dart';

const company = {
  'nombre': 'Empresa local',
  'nit': '123456789',
  'correo': 'empresa@example.test',
  'telefono': '22223344',
  'direccion': 'Dirección local'
};
const profile = {
  'id': 'pyme-test',
  'nombre': 'PYME',
  'correo': 'pyme@example.test',
  'rol': 'pyme',
  'estado': 'activo'
};
http.Response response(Object body,
        {int status = 200, Map<String, String> headers = const {}}) =>
    http.Response(jsonEncode(body), status, headers: {
      'content-type': 'application/json; charset=utf-8',
      ...headers
    });
Future<void> activate(ApiClient api) => api.offline.activate(
    OfflineScope(baseUrl: api.baseUrl, userId: 'pyme-test', role: 'pyme'),
    DateTime.now().toUtc().add(const Duration(hours: 1)));
Widget app(Widget screen) =>
    MaterialApp(theme: CreditoTheme.light, home: screen);

void main() {
  testWidgets('pantalla sincroniza el cambio conservando su clave',
      (tester) async {
    String? key;
    final api = ApiClient(
        token: 'token',
        httpClient: MockClient((request) async {
          if (request.url.path == '/api/usuarios/me') return response(profile);
          expect(request.method, 'POST');
          key = request.headers['Idempotency-Key'];
          return response({'id': 'empresa-1', ...company}, status: 201);
        }));
    await activate(api);
    final operation = await api.offline
        .enqueue(method: 'POST', route: '/api/empresas', body: company);
    await tester.pumpWidget(app(SincronizacionScreen(api: api)));
    expect(find.text('Registrar empresa'), findsOneWidget);
    expect(find.text('Nombre: Empresa local'), findsOneWidget);
    await tester.tap(find.text('Sincronizar pendientes'));
    await tester.pumpAndSettle();
    expect(api.offline.operations, isEmpty);
    expect(key, operation.idempotencyKey);
    expect(find.text('No tienes cambios pendientes.'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    api.close();
  });

  testWidgets('conflicto muestra ambas versiones y confirma revisión nueva',
      (tester) async {
    final revisions = <String?>[];
    final api = ApiClient(
        token: 'token',
        httpClient: MockClient((request) async {
          if (request.url.path == '/api/usuarios/me') return response(profile);
          if (request.method == 'GET') {
            return response({
              'id': 'empresa-1',
              ...company,
              'nombre': 'Empresa en servidor',
              'estado': 'activa'
            }, headers: {
              'etag': '"2-server"'
            });
          }
          revisions.add(request.headers['If-Match']);
          if (revisions.length == 1) {
            return response({'error': 'La empresa cambió'}, status: 412);
          }
          return response(
              {'id': 'empresa-1', ...company, 'estado': 'pendiente'});
        }));
    await activate(api);
    await api.offline.enqueue(
        method: 'PUT',
        route: '/api/empresas/empresa-1',
        body: company,
        ifMatch: '"1-old"');
    await api.sincronizarPendientes();
    expect(api.offline.conflictCount, 1);
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(app(SincronizacionScreen(api: api)));
    final review = find.text('Revisar conflicto');
    await tester.ensureVisible(review);
    await tester.tap(review);
    // The request remains busy while the conflict confirmation is open.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Versión actual del servidor'), findsOneWidget);
    expect(find.text('Nombre: Empresa en servidor'), findsOneWidget);
    expect(find.text('Tus cambios pendientes'), findsOneWidget);
    expect(revisions, ['"1-old"']);
    await tester.tap(find.text('Aplicar mis cambios'));
    await tester.pumpAndSettle();
    expect(revisions, ['"1-old"', '"2-server"']);
    expect(api.offline.operations, isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
    api.close();
  });

  testWidgets('cierre advierte y permite conservar pendientes', (tester) async {
    final api = ApiClient(
        httpClient: MockClient((request) async => response({
              'access_token': 'token',
              'token_type': 'Bearer',
              'expires_in': 3600,
              'usuario': profile
            })));
    final session = SesionProvider(api);
    await session.ingresar('pyme@example.test', 'password');
    await api.offline
        .enqueue(method: 'POST', route: '/api/empresas', body: company);
    await tester.pumpWidget(app(Scaffold(
        body: Builder(
            builder: (context) => TextButton(
                onPressed: () => confirmarCierreSesion(context, session),
                child: const Text('Cerrar sesión'))))));
    await tester.tap(find.text('Cerrar sesión'));
    await tester.pumpAndSettle();
    expect(find.text('Hay cambios sin sincronizar'), findsOneWidget);
    await tester.tap(find.text('Volver'));
    await tester.pumpAndSettle();
    expect(session.autenticado, isTrue);
    expect(api.offline.pendingCount, 1);
    await tester.tap(find.text('Cerrar sesión'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Eliminar y cerrar sesión'));
    await tester.pumpAndSettle();
    expect(session.autenticado, isFalse);
    expect(api.offline.operations, isEmpty);
    await api.offline.flush();
    await tester.pumpWidget(const SizedBox.shrink());
    session.dispose();
  });

  testWidgets('formulario informa guardado local sin éxito remoto ficticio',
      (tester) async {
    var closed = false;
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(app(Scaffold(
        body: EmpresaFormScreen(
      initialData: company,
      onGuardar: (_) async => throw OfflineQueuedException('local-1'),
      onGuardado: () => closed = true,
    ))));
    final save = find.text('Guardar cambios');
    await tester.ensureVisible(save);
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(closed, isTrue);
    expect(
        find.textContaining('Cambio guardado en este equipo.'), findsOneWidget);
    expect(find.text('Empresa actualizada.'), findsNothing);
  });
}
