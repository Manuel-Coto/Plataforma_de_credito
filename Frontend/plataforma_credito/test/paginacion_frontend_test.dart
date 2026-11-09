import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:plataforma_credito/core/estado_carga.dart';
import 'package:plataforma_credito/core/theme/credito_theme.dart';
import 'package:plataforma_credito/models/estado_factura.dart';
import 'package:plataforma_credito/models/financiamiento.dart';
import 'package:plataforma_credito/modules/creditos/providers/operaciones_provider.dart';
import 'package:plataforma_credito/modules/creditos/screens/operaciones_screen.dart';
import 'package:plataforma_credito/modules/facturas/providers/facturas_provider.dart';
import 'package:plataforma_credito/services/api_client.dart';
import 'package:plataforma_credito/services/factura_service.dart';
import 'package:provider/provider.dart';

http.Response _json(Object value, [int status = 200]) =>
    http.Response(jsonEncode(value), status,
        headers: {'content-type': 'application/json; charset=utf-8'});
Map<String, dynamic> _pagina(String campo, List<Object> filas, String cursor,
        {int limit = 50}) =>
    {campo: filas, 'bookmark': cursor, 'limit': limit};
Map<String, dynamic> _factura(int id,
        {String estado = 'disponible', String? numero}) =>
    {
      'id': 'factura-$id',
      'empresa_id': 'empresa-1',
      'numero': numero ?? 'F-$id',
      'dte': {
        'codigo_generacion': 'dte-$id',
        'verificado': true,
        'sello_recepcion': 'sello',
        'fecha_verificacion': '2026-11-08T12:00:00Z'
      },
      'moneda': 'USD',
      'monto_total_centavos': 10000,
      'monto_financiado_centavos': 0,
      'fecha_emision': '2026-11-08',
      'fecha_vencimiento': '2099-12-31',
      'estado': estado,
    };
Map<String, dynamic> _credito(int id,
        {bool vencido = false, bool pagado = false, int abonado = 0}) =>
    {
      'id': 'credito-$id',
      'factura_id': 'factura-$id',
      'moneda': 'USD',
      'capital_centavos': 10000,
      'interes_centavos': 0,
      'total_centavos': 10000,
      'pagado_centavos': pagado ? 10000 : abonado,
      'saldo_centavos': pagado ? 0 : 10000 - abonado,
      'estado': pagado ? 'pagado' : 'activo',
      'vencido': vencido,
      'dias_mora': vencido ? 5 : 0,
      'fecha_vencimiento': vencido ? '2026-01-01' : '2099-12-31',
      'pagos': [],
    };
Map<String, dynamic> _empresa(int id, {String? nombre}) => {
      'id': 'empresa-$id',
      'nombre': nombre ?? 'Empresa $id',
      'estado': 'activa'
    };

void main() {
  test(
      'facturas: páginas cortas siguen, IDs se actualizan y cursor repetido finaliza',
      () async {
    var calls = 0;
    final api = ApiClient(httpClient: MockClient((request) async {
      expect(request.url.queryParameters['limit'], '50');
      final cursor = request.url.queryParameters['bookmark'];
      switch (calls++) {
        case 0:
          expect(cursor, isNull);
          return _json(
              _pagina('facturas', [_factura(1), _factura(2)], 'A +/1'));
        case 1:
          expect(cursor, 'A +/1');
          return _json(_pagina('facturas',
              [_factura(2, numero: 'Actualizada'), _factura(3)], 'B'));
        default:
          expect(cursor, 'B');
          return _json(_pagina('facturas', [], 'B'));
      }
    }));
    addTearDown(api.close);
    final provider = FacturasProvider(FacturaService(api));
    addTearDown(provider.dispose);
    await provider.cargar();
    expect(provider.hayMas, isTrue);
    await provider.cargarMas();
    expect(provider.facturas.map((f) => f.id),
        ['factura-1', 'factura-2', 'factura-3']);
    expect(provider.facturas[1].numero, 'Actualizada');
    await provider.cargarMas();
    expect(provider.hayMas, isFalse);
    await provider.cargarMas();
    expect(calls, 3);
  });

  test(
      'facturas: atraviesa vacío intermedio con cursor nuevo, termina sin avance',
      () async {
    final cursores = <String?>[];
    final api = ApiClient(httpClient: MockClient((request) async {
      final cursor = request.url.queryParameters['bookmark'];
      cursores.add(cursor);
      if (cursor == null) return _json(_pagina('facturas', [], 'vacío'));
      if (cursor == 'vacío') {
        return _json(_pagina('facturas', [_factura(1)], 'con-datos'));
      }
      return _json(_pagina('facturas', [], cursor));
    }));
    addTearDown(api.close);
    final provider = FacturasProvider(FacturaService(api));
    addTearDown(provider.dispose);
    await provider.cargar();
    expect(provider.facturas, hasLength(1));
    expect(cursores, [null, 'vacío']);
    await provider.cargarMas();
    expect(provider.hayMas, isFalse);
    expect(cursores, [null, 'vacío', 'con-datos']);
  });

  test(
      'facturas: filtro reinicia cursor y descarta respuesta previa fuera de orden',
      () async {
    final anterior = Completer<http.Response>();
    final consultas = <Map<String, String>>[];
    final api = ApiClient(httpClient: MockClient((request) async {
      final query = request.url.queryParameters;
      consultas.add(query);
      if (!query.containsKey('estado')) return anterior.future;
      expect(query['estado'], 'disponible');
      return _json(_pagina('facturas', [_factura(2)],
          query.containsKey('bookmark') ? 'actual' : 'actual'));
    }));
    addTearDown(api.close);
    final provider = FacturasProvider(FacturaService(api));
    addTearDown(provider.dispose);
    final vieja = provider.cargar();
    await provider.filtrarPor(EstadoFactura.disponible);
    anterior.complete(_json(_pagina('facturas', [_factura(1)], 'viejo')));
    await vieja;
    expect(provider.facturas.single.id, 'factura-2');
    expect(provider.bookmark, 'actual');
    await provider.cargarMas();
    expect(consultas.last['bookmark'], 'actual');
    expect(provider.hayMas, isFalse);
  });

  test(
      'facturas: error de página conserva filas y reintenta el cursor; refresh fallido limpia',
      () async {
    var fase = 0;
    final api = ApiClient(httpClient: MockClient((request) async {
      final cursor = request.url.queryParameters['bookmark'];
      if (fase == 3 || (fase == 1 && cursor != null)) {
        return _json({'error': 'Sin conexión'}, 503);
      }
      return _json(_pagina('facturas', [_factura(cursor == null ? 1 : 2)],
          cursor == null ? 'A' : 'B'));
    }));
    addTearDown(api.close);
    final provider = FacturasProvider(FacturaService(api));
    addTearDown(provider.dispose);
    await provider.cargar();
    fase = 1;
    await provider.cargarMas();
    expect(provider.facturas, hasLength(1));
    expect(provider.errorMas, 'Sin conexión');
    expect(provider.bookmark, 'A');
    expect(provider.estadoCarga, EstadoCarga.listo);
    fase = 2;
    await provider.cargarMas();
    expect(provider.facturas, hasLength(2));
    fase = 3;
    await provider.cargar();
    expect(provider.facturas, isEmpty);
    expect(provider.hayMas, isFalse);
    expect(provider.bookmark, isNull);
    expect(provider.estadoCarga, EstadoCarga.error);
  });

  test('facturas: no notifica respuesta pendiente después de dispose',
      () async {
    final response = Completer<http.Response>();
    final api = ApiClient(httpClient: MockClient((_) => response.future));
    addTearDown(api.close);
    final provider = FacturasProvider(FacturaService(api));
    final pending = provider.cargar();
    provider.dispose();
    response.complete(_json(_pagina('facturas', [_factura(1)], 'A')));
    await expectLater(pending, completes);
  });

  test(
      'selector empresas: más de100, vacío intermedio y duplicados sin truncamiento',
      () async {
    final cursores = <String?>[];
    final api = ApiClient(httpClient: MockClient((request) async {
      expect(request.url.queryParameters['limit'], '100');
      final cursor = request.url.queryParameters['bookmark'];
      cursores.add(cursor);
      if (cursor == null) {
        return _json(_pagina(
            'empresas', List.generate(100, (i) => _empresa(i)), 'A',
            limit: 100));
      }
      if (cursor == 'A') return _json(_pagina('empresas', [], 'B', limit: 100));
      if (cursor == 'B') {
        return _json(_pagina(
            'empresas',
            [
              _empresa(1, nombre: 'Actualizada'),
              ...List.generate(5, (i) => _empresa(i + 100))
            ],
            'C',
            limit: 100));
      }
      return _json(_pagina('empresas', [], 'C', limit: 100));
    }));
    addTearDown(api.close);
    final empresas = await FacturaService(api).listarEmpresas();
    expect(empresas, hasLength(105));
    expect(
        empresas.firstWhere((e) => e.id == 'empresa-1').nombre, 'Actualizada');
    expect(cursores, [null, 'A', 'B', 'C']);
  });

  test(
      'selector empresas: cursor A-B-A detiene el ciclo conservando registros únicos',
      () async {
    var calls = 0;
    final api = ApiClient(httpClient: MockClient((request) async {
      final n = ++calls;
      return _json(
          _pagina('empresas', [_empresa(n)], n == 2 ? 'B' : 'A', limit: 100));
    }));
    addTearDown(api.close);
    expect(await FacturaService(api).listarEmpresas(), hasLength(3));
    expect(calls, 3);
  });

  test(
      'créditos vencidos: consulta activos y atraviesa páginas sin coincidencias',
      () async {
    final cursores = <String?>[];
    final api = ApiClient(httpClient: MockClient((request) async {
      expect(request.url.queryParameters['estado'], 'activo');
      final cursor = request.url.queryParameters['bookmark'];
      cursores.add(cursor);
      if (cursor == null) return _json(_pagina('creditos', [_credito(1)], 'A'));
      if (cursor == 'A') return _json(_pagina('creditos', [], 'B'));
      if (cursor == 'B') {
        return _json(_pagina('creditos', [_credito(2, vencido: true)], 'C'));
      }
      return _json(_pagina('creditos', [_credito(3, vencido: true)], 'C'));
    }));
    addTearDown(api.close);
    final provider = OperacionesProvider(api);
    addTearDown(provider.dispose);
    await provider.setFiltro('vencido');
    expect(provider.operaciones.single.id, 'credito-2');
    expect(cursores, [null, 'A', 'B']);
    await provider.cargarMas();
    expect(provider.operaciones.map((c) => c.id), ['credito-2', 'credito-3']);
    expect(provider.hayMas, isFalse);
  });

  test(
      'créditos pagados: filtro backend, páginas cortas y cursores conservados',
      () async {
    final api = ApiClient(httpClient: MockClient((request) async {
      expect(request.url.queryParameters['estado'], 'pagado');
      final cursor = request.url.queryParameters['bookmark'];
      return _json(_pagina(
          'creditos',
          cursor == 'B' ? [] : [_credito(cursor == null ? 1 : 2, pagado: true)],
          cursor == null ? 'A' : 'B'));
    }));
    addTearDown(api.close);
    final provider = OperacionesProvider(api);
    addTearDown(provider.dispose);
    await provider.setFiltro('pagado');
    expect(provider.hayMas, isTrue);
    await provider.cargarMas();
    expect(provider.operaciones, hasLength(2));
    await provider.cargarMas();
    expect(provider.hayMas, isFalse);
  });

  test(
      'créditos: pago invalida lectura atrasada pero conserva cursor de la página anterior',
      () async {
    final pendiente = Completer<http.Response>();
    var calls = 0;
    final api = ApiClient(httpClient: MockClient((request) async {
      calls++;
      if (calls == 1) return _json(_pagina('creditos', [_credito(1)], 'A'));
      expect(request.url.queryParameters['bookmark'], 'A');
      if (calls == 2) return pendiente.future;
      return _json(_pagina('creditos', [_credito(2)], 'B'));
    }));
    addTearDown(api.close);
    final provider = OperacionesProvider(api);
    addTearDown(provider.dispose);
    await provider.cargar();
    final paginaTardia = provider.cargarMas();
    provider.incorporar(ResultadoCredito.fromJson({
      'credito': _credito(1, abonado: 1000),
      'sincronizacion_pendiente': false
    }));
    pendiente.complete(
        _json(_pagina('creditos', [_credito(1), _credito(9)], 'obsoleto')));
    await paginaTardia;
    expect(provider.bookmark, 'A');
    expect(provider.hayMas, isTrue);
    expect(provider.operaciones.single.pagadoCentavos, 1000);
    await provider.cargarMas();
    expect(provider.operaciones, hasLength(2));
    expect(provider.operaciones.first.pagadoCentavos, 1000);
  });

  test(
      'créditos: error en más páginas conserva datos y reintento; refresh restablece cursor',
      () async {
    var fallar = false;
    final cursores = <String?>[];
    final api = ApiClient(httpClient: MockClient((request) async {
      final cursor = request.url.queryParameters['bookmark'];
      cursores.add(cursor);
      if (fallar) return _json({'error': 'No disponible'}, 503);
      return _json(_pagina('creditos', [_credito(cursor == null ? 1 : 2)],
          cursor == null ? 'A' : 'B'));
    }));
    addTearDown(api.close);
    final provider = OperacionesProvider(api);
    addTearDown(provider.dispose);
    await provider.cargar();
    fallar = true;
    await provider.cargarMas();
    expect(provider.error, isNull);
    expect(provider.errorMas, 'No disponible');
    expect(provider.operaciones, hasLength(1));
    expect(provider.bookmark, 'A');
    fallar = false;
    await provider.cargarMas();
    expect(provider.operaciones, hasLength(2));
    await provider.cargar();
    expect(cursores.last, isNull);
    expect(provider.operaciones, hasLength(1));
  });

  test(
      'créditos: cambio de filtro descarta respuesta pendiente y reinicia consulta',
      () async {
    final anterior = Completer<http.Response>();
    final api = ApiClient(httpClient: MockClient((request) async {
      if (request.url.queryParameters['estado'] == 'pagado') {
        expect(request.url.queryParameters['bookmark'], isNull);
        return _json(_pagina('creditos', [_credito(2, pagado: true)], 'P'));
      }
      return anterior.future;
    }));
    addTearDown(api.close);
    final provider = OperacionesProvider(api);
    addTearDown(provider.dispose);
    final antigua = provider.cargar();
    await provider.setFiltro('pagado');
    anterior.complete(_json(_pagina('creditos', [_credito(1)], 'antiguo')));
    await antigua;
    expect(provider.operaciones.single.id, 'credito-2');
    expect(provider.bookmark, 'P');
  });

  testWidgets(
      'el botón de créditos carga otra página y no sustituye los registros anteriores',
      (tester) async {
    final api = ApiClient(httpClient: MockClient((request) async {
      final cursor = request.url.queryParameters['bookmark'];
      return _json(_pagina('creditos', [_credito(cursor == null ? 1 : 2)],
          cursor == null ? 'A' : 'B'));
    }));
    addTearDown(api.close);
    final provider = OperacionesProvider(api);
    addTearDown(provider.dispose);
    await tester.pumpWidget(ChangeNotifierProvider.value(
        value: provider,
        child: MaterialApp(
            theme: CreditoTheme.light,
            home: const Scaffold(body: OperacionesScreen()))));
    await tester.pumpAndSettle();
    final boton = find.text('Cargar más créditos');
    await tester.ensureVisible(boton);
    await tester.tap(boton);
    await tester.pumpAndSettle();
    expect(provider.operaciones, hasLength(2));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
