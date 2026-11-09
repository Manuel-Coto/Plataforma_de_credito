import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:plataforma_credito/core/theme/credito_theme.dart';
import 'package:plataforma_credito/modules/usuarios/providers/sesion_provider.dart';
import 'package:plataforma_credito/modules/empresas/screens/empresa_revision_screen.dart';
import 'package:plataforma_credito/modules/administracion/screens/reportes_auditoria_screen.dart';
import 'package:plataforma_credito/services/api_client.dart';
import 'support/api_fixtures.dart';

http.Response respuesta(Object data, {Map<String, String>? headers}) =>
    http.Response(jsonEncode(data), 200, headers: {
      'content-type': 'application/json; charset=utf-8',
      ...?headers
    });

Future<SesionProvider> iniciar(WidgetTester tester, String rol, Widget screen,
    Future<http.Response> Function(http.Request) handler) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(1200, 1600);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  final api = ApiClient(httpClient: MockClient((request) async {
    if (request.url.path == '/api/auth/login') {
      return respuesta({
        'access_token': 'token-prueba',
        'token_type': 'Bearer',
        'expires_in': 3600,
        'usuario': {
          'id': 'usuario-prueba',
          'nombre': 'Prueba',
          'correo': 'prueba@example.test',
          'rol': rol,
          'estado': 'activo'
        }
      });
    }
    expect(request.headers['Authorization'], 'Bearer token-prueba');
    return handler(request);
  }));
  final sesion = SesionProvider(api);
  await sesion.ingresar('prueba@example.test', 'password');
  await tester.pumpWidget(ChangeNotifierProvider.value(
      value: sesion,
      child: MaterialApp(
          theme: CreditoTheme.light, home: Scaffold(body: screen))));
  await tester.pumpAndSettle();
  return sesion;
}

void main() {
  testWidgets(
      'PYME edita su empresa y la desactiva sin controles de aprobación',
      (tester) async {
    var actual = {
      'id': 'empresa-1',
      'nombre': 'Empresa inicial',
      'nit': '123456789',
      'correo': 'empresa@example.test',
      'telefono': '22223344',
      'direccion': 'Dirección ficticia',
      'estado': 'activa',
      'usuario_responsable_id': 'usuario-prueba'
    };
    var edits = 0;
    var deactivations = 0;
    final session = await iniciar(
        tester, 'pyme', const EmpresaDecisionScreen(id: 'empresa-1'),
        (request) async {
      if (request.method == 'PUT') {
        expect(request.headers['If-Match'], '"2-test"');
        edits++;
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body.keys.toSet(),
            {'nombre', 'nit', 'correo', 'telefono', 'direccion'});
        expect(body['nombre'], 'Empresa actualizada');
        actual = {
          ...actual,
          ...body.cast<String, String>(),
          'estado': 'pendiente'
        };
      }
      if (request.method == 'PATCH') {
        expect(request.url.path, '/api/empresas/empresa-1/desactivar');
        deactivations++;
        actual = {...actual, 'estado': 'inactiva'};
      }
      return respuesta(actual, headers: {'etag': '"2-test"'});
    });
    expect(find.text('Aprobar empresa'), findsNothing);
    await tester.tap(find.text('Editar empresa'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byType(TextFormField).first, 'Empresa actualizada');
    final save = find.text('Guardar cambios');
    await tester.ensureVisible(save);
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(edits, 1);
    expect(find.text('Empresa actualizada'), findsOneWidget);
    expect(find.text('Estado: pendiente'), findsOneWidget);
    await tester.tap(find.text('Desactivar empresa'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Desactivar'));
    await tester.pumpAndSettle();
    expect(deactivations, 1);
    expect(find.text('Estado: inactiva'), findsOneWidget);
    expect(find.text('Desactivar empresa'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    session.dispose();
  });

  testWidgets('Reportes conserva monedas y auditoría aplica filtros y cursores',
      (tester) async {
    final queries = <Map<String, String>>[];
    final report = (apiFixture('administracion_resumen')['reportes'] as List)
        .firstWhere((r) => r['modulo'] == 'creditos');
    final session =
        await iniciar(tester, 'administrador', const ReportesAuditoriaScreen(),
            (request) async {
      if (request.url.path.endsWith('/reportes')) {
        expect(request.url.queryParameters['modulo'], 'creditos');
        return respuesta(report);
      }
      expect(request.url.path, '/api/administracion/auditoria');
      queries.add(request.url.queryParameters);
      return respuesta({
        'eventos': request.url.queryParameters.containsKey('bookmark')
            ? []
            : [
                {
                  'id': 'evento-1',
                  'actor_id': 'actor/1',
                  'accion': 'pago_registrado',
                  'recurso_tipo': 'credito',
                  'recurso_id': 'credito-1',
                  'fecha': '2026-11-08T12:00:00Z',
                  'detalles': {'moneda': 'USD', 'monto_centavos': 1000}
                }
              ],
        'bookmark': 'cursor+dos',
        'limit': 25
      });
    });
    expect(find.text('Importes en EUR'), findsOneWidget);
    expect(find.text('Importes en USD'), findsOneWidget);
    await tester.tap(find.text('Auditoría'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'actor/1');
    await tester.enterText(find.byType(TextField).last, 'credito-1');
    await tester.tap(find.text('Aplicar filtros'));
    await tester.pumpAndSettle();
    expect(queries.last['actor_id'], 'actor/1');
    expect(queries.last['recurso_id'], 'credito-1');
    final more = find.text('Cargar más eventos');
    await tester.ensureVisible(more);
    await tester.tap(more);
    await tester.pumpAndSettle();
    expect(queries.last['bookmark'], 'cursor+dos');
    expect(queries.last['actor_id'], 'actor/1');
    expect(find.text('Cargar más eventos'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    session.dispose();
  });
}
