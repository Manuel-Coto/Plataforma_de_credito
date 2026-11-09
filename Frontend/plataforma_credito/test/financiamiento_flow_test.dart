import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:plataforma_credito/core/theme/credito_theme.dart';
import 'package:plataforma_credito/models/financiamiento.dart';
import 'package:plataforma_credito/modules/creditos/providers/operaciones_provider.dart';
import 'package:plataforma_credito/modules/creditos/widgets/pago_dialog.dart';
import 'package:plataforma_credito/modules/inversiones/providers/inversiones_provider.dart';
import 'package:plataforma_credito/services/api_client.dart';
import 'package:plataforma_credito/services/credito_service.dart';
import 'package:plataforma_credito/services/inversion_service.dart';

import 'support/api_fixtures.dart';

http.Response _json(Object value, [int status = 200]) =>
    http.Response(jsonEncode(value), status,
        headers: {'content-type': 'application/json; charset=utf-8'});
Map<String, dynamic> _oferta() => {
      '_id': 'oferta:prueba',
      'tipo': 'oferta',
      'factura_id': 'factura:prueba',
      'empresa_id': 'empresa:prueba',
      'creado_por': 'usuario:pyme',
      'monto_objetivo': 1000.0,
      'monto_recaudado': 250.0,
      'moneda': 'USD',
      'tasa_rendimiento_anual': 8.5,
      'estado': 'abierta',
      'fecha_apertura': '2026-11-08T00:00:00Z',
      'fecha_cierre': '2099-11-30T23:59:00Z',
    };
Map<String, dynamic> _inversion() => {
      '_id': 'inversion:prueba',
      'oferta_id': 'oferta:prueba',
      'factura_id': 'factura:prueba',
      'inversionista_id': 'usuario:inversionista',
      'monto': 123.45,
      'moneda': 'USD',
      'estado': 'pago_pendiente',
      'fecha_creacion': '2026-11-08T12:00:00Z',
      'fecha_liquidacion': null,
      'rendimiento_real': null,
    };
Map<String, dynamic> _credito() =>
    (apiFixture('creditos_pagina')['creditos'] as List).first
        as Map<String, dynamic>;
Map<String, dynamic> _pagadoParcial() {
  final credito = _credito();
  credito['pagado_centavos'] = 41000;
  credito['saldo_centavos'] = 60000;
  (credito['pagos'] as List).add({
    'id': 'pago:nuevo',
    'referencia': 'estable',
    'monto_centavos': 1000,
    'registrado_por': 'usuario:pyme',
    'fecha': '2026-11-08T12:00:00Z'
  });
  return credito;
}

Object _pagina(String campo, List<Object> items, {String bookmark = ''}) =>
    {campo: items, 'bookmark': bookmark, 'limit': 20};

void main() {
  test(
      'ofertas e inversiones interpretan unidades reales y entradas exactas de centavos',
      () {
    final oferta = Oferta.fromJson(_oferta());
    expect(oferta.objetivoCentavos, 100000);
    expect(oferta.recaudadoCentavos, 25000);
    expect(oferta.disponibleCentavos, 75000);
    expect(oferta.tasaAnual, 8.5);
    expect(Inversion.fromJson(_inversion()).montoCentavos, 12345);
    expect(textoACentavos('123,45'), 12345);
    expect(textoACentavos('0.01'), 1);
    expect(textoACentavos('10.001'), isNull);
    expect(textoACentavos('NaN'), isNull);
    expect(() => Oferta.fromJson(_oferta()..['monto_objetivo'] = .001),
        throwsFormatException);
  });

  test(
      'publicar oferta envía unidades monetarias, porcentaje anual y fecha UTC',
      () async {
    final api = ApiClient(httpClient: MockClient((request) async {
      expect(request.method, 'POST');
      expect(request.url.path, '/api/ofertas');
      expect(jsonDecode(request.body), {
        'factura_id': 'factura:prueba',
        'monto_objetivo': 123.45,
        'tasa_rendimiento_anual': 8.5,
        'fecha_cierre': '2099-11-30T23:59:00.000Z'
      });
      return _json(_oferta(), 201);
    }));
    addTearDown(api.close);
    await InversionService(api).crearOferta(
        facturaId: 'factura:prueba',
        montoCentavos: 12345,
        tasaAnual: 8.5,
        fechaCierre: DateTime.utc(2099, 11, 30, 23, 59));
  });

  test(
      'un aporte con respuesta perdida reutiliza la misma clave y monto sin duplicarlo',
      () async {
    final keys = <String?>[], bodies = <Object>[];
    var posts = 0;
    final api = ApiClient(httpClient: MockClient((request) async {
      if (request.method == 'POST') {
        expect(request.url.path, '/api/inversiones');
        keys.add(request.headers['Idempotency-Key']);
        bodies.add(jsonDecode(request.body));
        if (posts++ == 0) throw http.ClientException('respuesta perdida');
        return _json(_inversion(), 201);
      }
      return _json(request.url.path == '/api/ofertas'
          ? _pagina('ofertas', [_oferta()])
          : _pagina('inversiones', [_inversion()]));
    }));
    addTearDown(api.close);
    final provider = InversionesProvider(
        InversionService(api), CreditoService(api),
        rol: 'inversionista', usuarioId: 'usuario:inversionista');
    addTearDown(provider.dispose);
    final oferta = Oferta.fromJson(_oferta());
    await expectLater(
        provider.invertir(oferta, 12345), throwsA(isA<ApiException>()));
    expect(provider.intentoPendiente(oferta.id), isNotNull);
    await expectLater(
        provider.invertir(oferta, 20000), throwsA(isA<ApiException>()));
    await provider.invertir(oferta, 12345);
    expect(posts, 2);
    expect(keys.first, isNotEmpty);
    expect(keys[0], keys[1]);
    expect(bodies[0], bodies[1]);
    expect(provider.intentoPendiente(oferta.id), isNull);
    expect(provider.inversiones, hasLength(1));
  });

  test('bloquea doble envío del mismo aporte mientras espera respuesta',
      () async {
    final respuesta = Completer<http.Response>();
    var posts = 0;
    final api = ApiClient(httpClient: MockClient((request) async {
      if (request.method == 'POST') {
        posts++;
        return respuesta.future;
      }
      return _json(_pagina(
          request.url.path == '/api/ofertas' ? 'ofertas' : 'inversiones', []));
    }));
    addTearDown(api.close);
    final provider = InversionesProvider(
        InversionService(api), CreditoService(api),
        rol: 'inversionista', usuarioId: 'usuario:inversionista');
    addTearDown(provider.dispose);
    final oferta = Oferta.fromJson(_oferta());
    final primero = provider.invertir(oferta, 12345);
    await expectLater(
        provider.invertir(oferta, 12345), throwsA(isA<ApiException>()));
    respuesta.complete(_json(_inversion(), 201));
    await primero;
    expect(posts, 1);
  });

  test('recuperación recorre cursores y nunca confirma automáticamente aportes',
      () async {
    const cursor = 'cursor +/pendiente?=1';
    var paginas = 0;
    final api = ApiClient(httpClient: MockClient((request) async {
      if (request.method == 'POST') {
        expect(request.url.path, '/api/inversiones/recuperar');
        expect(jsonDecode(request.body), isEmpty);
        expect(request.url.queryParameters['bookmark'],
            paginas == 0 ? null : cursor);
        return _json({
          'recuperadas': ++paginas,
          'pendientes': 1,
          'bookmark': paginas == 1 ? cursor : ''
        });
      }
      return _json(_pagina(
          request.url.path == '/api/ofertas' ? 'ofertas' : 'inversiones', []));
    }));
    addTearDown(api.close);
    final provider = InversionesProvider(
        InversionService(api), CreditoService(api),
        rol: 'inversionista', usuarioId: 'usuario:inversionista');
    addTearDown(provider.dispose);
    await provider.recuperar();
    expect(provider.cursorRecuperacion, cursor);
    await provider.recuperar();
    expect(provider.cursorRecuperacion, isNull);
    expect(provider.recuperacion!.recuperadas, 2);
    expect(paginas, 2);
  });

  test(
      'confirmar aporte usa endpoint explícito y comunica sincronización pendiente',
      () async {
    final api = ApiClient(httpClient: MockClient((request) async {
      expect(request.method, 'POST');
      expect(request.url.pathSegments,
          ['api', 'creditos', 'aportes', 'inversion:prueba', 'confirmar']);
      return _json({
        'inversion_id': 'inversion:prueba',
        'estado': 'confirmada',
        'simulado': true,
        'sincronizacion_pendiente': true
      });
    }));
    addTearDown(api.close);
    final resultado =
        await CreditoService(api).confirmarAporte('inversion:prueba');
    expect(resultado.sincronizacionPendiente, isTrue);
    expect(resultado.estado, 'confirmada');
  });

  test(
      'pago perdido reutiliza referencia y aplica saldo recibido sin duplicar historial',
      () async {
    final referencias = <String>[], montos = <int>[];
    var posts = 0;
    final api = ApiClient(httpClient: MockClient((request) async {
      if (request.method == 'GET') return _json(apiFixture('creditos_pagina'));
      final cuerpo = jsonDecode(request.body) as Map<String, dynamic>;
      referencias.add(cuerpo['referencia'] as String);
      montos.add(cuerpo['monto_centavos'] as int);
      if (posts++ == 0) throw http.ClientException('respuesta perdida');
      return _json(
          {'credito': _pagadoParcial(), 'sincronizacion_pendiente': true});
    }));
    addTearDown(api.close);
    final provider = OperacionesProvider(api);
    addTearDown(provider.dispose);
    await provider.cargar();
    final credito = provider.operaciones.first;
    await expectLater(
        provider.pagar(credito, 1000), throwsA(isA<ApiException>()));
    await expectLater(
        provider.pagar(credito, 2000), throwsA(isA<ApiException>()));
    await provider.pagar(credito, 1000);
    expect(posts, 2);
    expect(referencias[0], referencias[1]);
    expect(montos, [1000, 1000]);
    final actual =
        provider.operaciones.firstWhere((item) => item.id == credito.id);
    expect(actual.pagadoCentavos, 41000);
    expect(actual.saldoCentavos, 60000);
    expect(
        actual.pagos!.where((pago) => pago.id == 'pago:nuevo'), hasLength(1));
    expect(provider.sincronizacionPendiente, contains(credito.id));
    expect(provider.intentoPago(credito.id), isNull);
  });

  test('listar ofertas preserva bookmark opaco y agrega páginas sin duplicados',
      () async {
    var calls = 0;
    final api = ApiClient(httpClient: MockClient((request) async {
      expect(request.url.queryParameters['estado'], 'abierta');
      if (calls++ == 0) {
        return _json(_pagina('ofertas', [_oferta()], bookmark: 'cursor +/2'));
      }
      expect(request.url.queryParameters['bookmark'], 'cursor +/2');
      return _json(_pagina('ofertas', [_oferta()], bookmark: 'cursor +/2'));
    }));
    addTearDown(api.close);
    final provider = InversionesProvider(
        InversionService(api), CreditoService(api),
        rol: 'inversionista', usuarioId: 'usuario:inversionista');
    addTearDown(provider.dispose);
    await provider.cargarOfertas();
    expect(provider.masOfertas, isTrue);
    await provider.cargarOfertas(mas: true);
    expect(provider.ofertas, hasLength(1));
    expect(provider.masOfertas, isFalse);
  });

  testWidgets(
      'el pago requiere confirmar y conserva el intento al fallar la conexión',
      (tester) async {
    var envios = 0;
    int? pendiente;
    await tester.pumpWidget(MaterialApp(
        theme: CreditoTheme.light,
        home: Scaffold(
            body: PagoDialog(
                saldoCentavos: 10000,
                moneda: 'USD',
                montoPendiente: () => pendiente,
                onGuardar: (monto) async {
                  envios++;
                  pendiente = monto;
                  throw ApiException('Conexión interrumpida');
                }))));
    await tester.enterText(find.byType(TextFormField), '25.00');
    await tester.tap(find.text('Revisar pago'));
    await tester.pumpAndSettle();
    expect(envios, 0);
    await tester.tap(find.widgetWithText(FilledButton, 'Confirmar pago'));
    await tester.pumpAndSettle();
    expect(envios, 1);
    expect(pendiente, 2500);
    expect(find.text('Reintentar pago'), findsOneWidget);
    expect(tester.widget<TextFormField>(find.byType(TextFormField)).enabled,
        isFalse);
    await tester.tap(find.text('Reintentar pago'));
    await tester.pumpAndSettle();
    expect(envios, 2);
    expect(pendiente, 2500);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
