import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:plataforma_credito/core/theme/credito_theme.dart';
import 'package:plataforma_credito/modules/administracion/screens/reportes_auditoria_screen.dart';
import 'package:plataforma_credito/modules/empresas/screens/empresa_revision_screen.dart';
import 'package:plataforma_credito/modules/inversiones/providers/inversiones_provider.dart';
import 'package:plataforma_credito/modules/usuarios/providers/sesion_provider.dart';
import 'package:plataforma_credito/modules/usuarios/screens/usuarios_gestion_screen.dart';
import 'package:plataforma_credito/services/api_client.dart';
import 'package:plataforma_credito/services/credito_service.dart';
import 'package:plataforma_credito/services/inversion_service.dart';
import 'package:provider/provider.dart';

import 'support/api_fixtures.dart';

http.Response _json(Object data, [int status = 200]) =>
    http.Response(jsonEncode(data), status,
        headers: {'content-type': 'application/json; charset=utf-8'});
Object _pagina(String key, List<Object> items, String cursor) =>
    {key: items, 'bookmark': cursor, 'limit': 25};
Map<String, dynamic> _oferta(int id) => {
      '_id': 'oferta-$id',
      'factura_id': 'factura-$id',
      'empresa_id': 'empresa-$id',
      'creado_por': 'pyme',
      'monto_objetivo': 100.0,
      'monto_recaudado': 25.0,
      'moneda': 'USD',
      'tasa_rendimiento_anual': 8.0,
      'estado': 'abierta',
      'fecha_cierre': '2099-12-31T23:59:00Z'
    };
Map<String, dynamic> _inversion(int id) => {
      '_id': 'inversion-$id',
      'oferta_id': 'oferta-$id',
      'factura_id': 'factura-$id',
      'inversionista_id': 'inversionista',
      'monto': 25.0,
      'moneda': 'USD',
      'estado': 'pago_pendiente',
      'fecha_creacion': '2026-11-08T12:00:00Z',
      'fecha_liquidacion': null,
      'rendimiento_real': null
    };
Map<String, dynamic> _usuario(int id) => {
      'id': 'usuario-$id',
      'nombre': 'Usuario $id',
      'correo': 'usuario$id@example.test',
      'rol': 'pyme',
      'estado': 'activo'
    };
Map<String, dynamic> _empresa(int id) => {
      'id': 'empresa-$id',
      'nombre': 'Empresa $id',
      'nit': '12345678$id',
      'estado': 'pendiente',
      'usuario_responsable_id': 'pyme'
    };
Map<String, dynamic> _evento(int id) => {
      'id': 'evento-$id',
      'actor_id': 'actor-filtro',
      'accion': 'pago_registrado',
      'recurso_tipo': 'credito',
      'recurso_id': 'recurso-filtro',
      'fecha': '2026-11-08T12:00:00Z',
      'detalles': {'moneda': 'USD', 'monto_centavos': 2500}
    };
http.Response _login() => _json({
      'access_token': 'token-prueba',
      'token_type': 'Bearer',
      'expires_in': 3600,
      'usuario': {
        'id': 'admin',
        'nombre': 'Administrador',
        'correo': 'admin@example.test',
        'rol': 'administrador',
        'estado': 'activo'
      }
    });

Future<SesionProvider> _montar(
    WidgetTester tester, ApiClient api, Widget screen) async {
  final sesion = SesionProvider(api);
  await sesion.ingresar('admin@example.test', 'Prueba-123456!');
  await tester.pumpWidget(ChangeNotifierProvider<SesionProvider>(
      create: (_) => sesion,
      child: MaterialApp(
          theme: CreditoTheme.light, home: Scaffold(body: screen))));
  await tester.pumpAndSettle();
  return sesion;
}

Future<void> _tap(WidgetTester tester, String label) async {
  await tester.scrollUntilVisible(find.text(label), 200,
      scrollable: find.byType(Scrollable).last);
  await tester.tap(find.text(label));
  await tester.pumpAndSettle();
}

void main() {
  test('ofertas e historial atraviesan vacío y detienen ciclo A-B-A', () async {
    final cursores = <String, List<String?>>{};
    final api = ApiClient(httpClient: MockClient((request) async {
      final path = request.url.path;
      final cursor = request.url.queryParameters['bookmark'];
      (cursores[path] ??= []).add(cursor);
      final campo = path == '/api/ofertas' ? 'ofertas' : 'inversiones';
      if (cursor == null) return _json(_pagina(campo, [], 'A'));
      final id = cursor == 'A'
          ? 1
          : cursor == 'B'
              ? 2
              : 3;
      return _json(_pagina(
          campo,
          [campo == 'ofertas' ? _oferta(id) : _inversion(id)],
          cursor == 'A'
              ? 'B'
              : cursor == 'B'
                  ? 'C'
                  : 'A'));
    }));
    addTearDown(api.close);
    final provider = InversionesProvider(
        InversionService(api), CreditoService(api),
        rol: 'inversionista', usuarioId: 'inversionista');
    addTearDown(provider.dispose);
    await provider.cargar();
    expect(provider.ofertas, hasLength(1));
    expect(provider.inversiones, hasLength(1));
    await provider.cargarOfertas(mas: true);
    await provider.cargarOfertas(mas: true);
    await provider.cargarInversiones(mas: true);
    await provider.cargarInversiones(mas: true);
    expect(provider.ofertas, hasLength(3));
    expect(provider.inversiones, hasLength(3));
    expect(provider.masOfertas, isFalse);
    expect(provider.masInversiones, isFalse);
    expect(cursores['/api/ofertas'], [null, 'A', 'B', 'C']);
    expect(cursores['/api/inversiones'], [null, 'A', 'B', 'C']);
  });

  test(
      'refresh fallido de inversiones borra filas y flags de páginas anteriores',
      () async {
    var fallar = false;
    var calls = 0;
    final api = ApiClient(httpClient: MockClient((request) async {
      calls++;
      expect(request.url.queryParameters['bookmark'], isNull);
      if (fallar) return _json({'error': 'No disponible'}, 503);
      return _json(request.url.path == '/api/ofertas'
          ? _pagina('ofertas', [_oferta(1)], 'A')
          : _pagina('inversiones', [_inversion(1)], 'A'));
    }));
    addTearDown(api.close);
    final provider = InversionesProvider(
        InversionService(api), CreditoService(api),
        rol: 'inversionista', usuarioId: 'inversionista');
    addTearDown(provider.dispose);
    await provider.cargar();
    expect(provider.masOfertas, isTrue);
    expect(provider.masInversiones, isTrue);
    fallar = true;
    await provider.cargar();
    expect(provider.ofertas, isEmpty);
    expect(provider.inversiones, isEmpty);
    expect(provider.masOfertas, isFalse);
    expect(provider.masInversiones, isFalse);
    final anteriores = calls;
    await provider.cargarOfertas(mas: true);
    await provider.cargarInversiones(mas: true);
    expect(calls, anteriores);
    expect(provider.errorOfertas, 'No disponible');
  });

  testWidgets(
      'usuarios atraviesa vacío con avance y finaliza ciclo entre páginas',
      (tester) async {
    final cursores = <String?>[];
    final api = ApiClient(httpClient: MockClient((request) async {
      if (request.url.path == '/api/auth/login') return _login();
      final cursor = request.url.queryParameters['bookmark'];
      cursores.add(cursor);
      if (cursor == null) return _json(_pagina('usuarios', [], 'A'));
      final id = cursor == 'A'
          ? 1
          : cursor == 'B'
              ? 2
              : 3;
      return _json(_pagina(
          'usuarios',
          [_usuario(id)],
          cursor == 'A'
              ? 'B'
              : cursor == 'B'
                  ? 'C'
                  : 'A'));
    }));
    await _montar(tester, api, const UsuariosGestionScreen());
    expect(find.text('Usuario 1'), findsOneWidget);
    await _tap(tester, 'Cargar más usuarios');
    await _tap(tester, 'Cargar más usuarios');
    expect(cursores, [null, 'A', 'B', 'C']);
    expect(find.text('Cargar más usuarios'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
      'usuarios refresh fallido elimina filas y volver a cargar reinicia bookmark',
      (tester) async {
    var fallar = false;
    final cursores = <String?>[];
    final api = ApiClient(httpClient: MockClient((request) async {
      if (request.url.path == '/api/auth/login') return _login();
      if (request.url.path == '/api/usuarios/me') {
        return _json((jsonDecode(_login().body) as Map<String, dynamic>)['usuario']);
      }
      cursores.add(request.url.queryParameters['bookmark']);
      return fallar
          ? _json({'error': 'Acceso temporalmente denegado'}, 403)
          : _json(_pagina('usuarios', [_usuario(1)], 'A'));
    }));
    await _montar(tester, api, const UsuariosGestionScreen());
    fallar = true;
    await tester.tap(find.text('Actualizar'));
    await tester.pumpAndSettle();
    expect(find.text('Usuario 1'), findsNothing);
    expect(find.text('Cargar más usuarios'), findsNothing);
    fallar = false;
    await tester.tap(find.text('Reintentar'));
    await tester.pumpAndSettle();
    expect(cursores, [null, null, null]);
    expect(find.text('Usuario 1'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
      'empresas atraviesa vacío nuevo y detiene ciclo sin perder registros',
      (tester) async {
    final cursores = <String?>[];
    final api = ApiClient(httpClient: MockClient((request) async {
      if (request.url.path == '/api/auth/login') return _login();
      final cursor = request.url.queryParameters['bookmark'];
      cursores.add(cursor);
      if (cursor == null) return _json(_pagina('empresas', [], 'A'));
      return _json(_pagina('empresas', [_empresa(cursor == 'A' ? 1 : 2)],
          cursor == 'A' ? 'B' : 'A'));
    }));
    await _montar(tester, api, const EmpresaRevisionScreen());
    expect(find.text('Empresa 1'), findsOneWidget);
    await _tap(tester, 'Cargar más empresas');
    expect(cursores, [null, 'A', 'B']);
    expect(find.text('Cargar más empresas'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
      'auditoría conserva filtros en vacío intermedio y corta ciclo A-B-A',
      (tester) async {
    final consultas = <Map<String, String>>[];
    final api = ApiClient(httpClient: MockClient((request) async {
      if (request.url.path == '/api/auth/login') return _login();
      if (request.url.path.endsWith('/reportes')) {
        return _json((apiFixture('administracion_resumen')['reportes'] as List)
            .firstWhere((r) => r['modulo'] == 'creditos'));
      }
      final query = request.url.queryParameters;
      consultas.add(query);
      final cursor = query['bookmark'];
      if (cursor == null) return _json(_pagina('eventos', [], 'A'));
      return _json(_pagina('eventos', [_evento(cursor == 'A' ? 1 : 2)],
          cursor == 'A' ? 'B' : 'A'));
    }));
    await _montar(tester, api, const ReportesAuditoriaScreen());
    await tester.tap(find.text('Auditoría'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'actor-filtro');
    await tester.enterText(find.byType(TextField).last, 'recurso-filtro');
    await _tap(tester, 'Aplicar filtros');
    await _tap(tester, 'Cargar más eventos');
    expect(consultas.last['actor_id'], 'actor-filtro');
    expect(consultas.last['recurso_id'], 'recurso-filtro');
    expect(consultas.last['bookmark'], 'B');
    expect(find.text('Cargar más eventos'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
