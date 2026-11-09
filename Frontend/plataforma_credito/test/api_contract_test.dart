import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:plataforma_credito/core/theme/credito_theme.dart';
import 'package:plataforma_credito/models/operacion.dart';
import 'package:plataforma_credito/models/resumen.dart';
import 'package:plataforma_credito/modules/administracion/providers/reportes_provider.dart';
import 'package:plataforma_credito/modules/administracion/screens/dashboard_screen.dart';
import 'package:plataforma_credito/modules/creditos/providers/operaciones_provider.dart';
import 'package:plataforma_credito/modules/creditos/screens/operacion_detalle_screen.dart';
import 'package:plataforma_credito/services/api_client.dart';
import 'package:provider/provider.dart';

import 'support/api_fixtures.dart';

http.Response _json(Object value) => http.Response(
      jsonEncode(value),
      200,
      headers: const {'content-type': 'application/json; charset=utf-8'},
    );

Map<String, dynamic> _credito([int index = 0]) =>
    (apiFixture('creditos_pagina')['creditos'] as List)[index]
        as Map<String, dynamic>;

void main() {
  group('Contrato compartido con Rust: créditos', () {
    test('usa los totales del crédito y reconoce pagos sin campo estado', () {
      final credito = Operacion.fromJson(_credito());
      expect(credito.capitalCentavos, 100000);
      expect(credito.interesCentavos, 1000);
      expect(credito.totalCentavos, 101000);
      expect(credito.pagadoCentavos, 40000);
      expect(credito.saldoCentavos, 61000);
      expect(credito.progreso, closeTo(40000 / 101000, .000001));
      expect(credito.estadoVisible, 'vencido');
      expect(credito.diasMora, 5);
      expect(credito.historialCompartido, isTrue);
      expect(credito.pagos, isNotEmpty);
      expect(credito.pagos!.first.montoCentavos, greaterThan(0));
    });

    test('un inversionista conserva los totales aunque no reciba el historial',
        () {
      final data = _credito()..remove('pagos');
      final credito = Operacion.fromJson(data);
      expect(credito.historialCompartido, isFalse);
      expect(credito.pagos, isNull);
      expect(credito.pagadoCentavos, 40000);
      expect(credito.saldoCentavos, 61000);
      expect(credito.progreso, closeTo(40000 / 101000, .000001));
    });

    test('el crédito pagado muestra saldo cero y avance completo', () {
      final credito = Operacion.fromJson(_credito(1));
      expect(credito.totalCentavos, 52500);
      expect(credito.pagadoCentavos, 52500);
      expect(credito.saldoCentavos, 0);
      expect(credito.estadoVisible, 'pagado');
      expect(credito.progreso, 1);
    });

    test('rechaza el formato antiguo, campos ausentes y saldos contradictorios',
        () {
      expect(() => Operacion.fromJson({'monto_centavos': 101000}),
          throwsFormatException);
      for (final field in [
        'total_centavos',
        'pagado_centavos',
        'saldo_centavos'
      ]) {
        final invalid = _credito()..remove(field);
        expect(() => Operacion.fromJson(invalid), throwsFormatException,
            reason: field);
      }
      final invalid = _credito()..['saldo_centavos'] = 0;
      expect(() => Operacion.fromJson(invalid), throwsFormatException);
    });

    test('consume el listado paginado real y filtra por vencido', () async {
      final api = ApiClient(httpClient: MockClient((request) async {
        expect(request.url.path, '/api/creditos');
        return _json(apiFixture('creditos_pagina'));
      }));
      final provider = OperacionesProvider(api);
      addTearDown(provider.dispose);
      addTearDown(api.close);
      await provider.cargar();
      expect(provider.error, isNull);
      expect(provider.operaciones, hasLength(3));
      provider.setFiltro('vencido');
      expect(provider.operaciones, hasLength(1));
      expect(provider.operaciones.single.saldoCentavos, 61000);
      provider.setFiltro('pagado');
      expect(provider.operaciones.single.progreso, 1);
    });

    test(
        'un formato inválido al actualizar muestra error y retira datos previos',
        () async {
      var calls = 0;
      final api = ApiClient(
          httpClient: MockClient((_) async => _json(
              calls++ == 0 ? apiFixture('creditos_pagina') : {'items': []})));
      final provider = OperacionesProvider(api);
      addTearDown(provider.dispose);
      addTearDown(api.close);
      await provider.cargar();
      expect(provider.operaciones, isNotEmpty);
      await provider.cargar();
      expect(provider.error, isNotNull);
      expect(provider.operaciones, isEmpty);
      expect(provider.cargando, isFalse);
    });

    test(
        'ignora una solicitud anterior que termina después de la actualización',
        () async {
      final first = Completer<http.Response>();
      var calls = 0;
      final api = ApiClient(
          httpClient: MockClient((_) => calls++ == 0
              ? first.future
              : Future.value(_json(apiFixture('creditos_pagina')))));
      final provider = OperacionesProvider(api);
      addTearDown(provider.dispose);
      addTearDown(api.close);
      final pending = provider.cargar();
      await provider.cargar();
      first.complete(_json({'creditos': [], 'bookmark': '', 'limit': 20}));
      await pending;
      expect(provider.operaciones, hasLength(3));
      expect(provider.error, isNull);
    });

    test('una respuesta pendiente no notifica después de cerrar el provider',
        () async {
      final response = Completer<http.Response>();
      final api = ApiClient(httpClient: MockClient((_) => response.future));
      addTearDown(api.close);
      final provider = OperacionesProvider(api);
      final pending = provider.cargar();
      provider.dispose();
      response.complete(_json(apiFixture('creditos_pagina')));
      await expectLater(pending, completes);
    });
  });

  group('Contrato compartido con Rust: administración', () {
    test('lee los ocho reportes y mantiene los montos por moneda', () {
      final resumen = Resumen.fromJson(apiFixture('administracion_resumen'));
      expect(resumen.totalCreditos, 3);
      expect(resumen.montosCreditosPorMoneda, {'USD': 153500, 'EUR': 25200});
      expect(resumen.empresasVerificadas, 2);
      expect(resumen.facturasPendientes, 2);
      expect(resumen.porEstado.values.fold(0, (sum, value) => sum + value), 3);
      expect(resumen.generadoEn.isUtc, isTrue);
    });

    test('un resumen vacío válido contiene reportes y produce ceros reales',
        () {
      final data = apiFixture('administracion_resumen');
      for (final report in data['reportes'] as List) {
        report['total'] = 0;
        report['por_estado'] = <String, dynamic>{};
        report['por_rol'] = <String, dynamic>{};
        report['montos_por_moneda'] = <String, dynamic>{};
      }
      final resumen = Resumen.fromJson(data);
      expect(resumen.totalCreditos, 0);
      expect(resumen.empresasVerificadas, 0);
      expect(resumen.facturasPendientes, 0);
      expect(resumen.montosCreditosPorMoneda, isEmpty);
    });

    test('rechaza el resumen antiguo y los reportes incompletos o duplicados',
        () {
      expect(() => Resumen.fromJson({'total_operaciones': 3}),
          throwsFormatException);
      final missing = apiFixture('administracion_resumen');
      (missing['reportes'] as List)
          .removeWhere((report) => report['modulo'] == 'creditos');
      expect(() => Resumen.fromJson(missing), throwsFormatException);
      final duplicate = apiFixture('administracion_resumen');
      final reports = duplicate['reportes'] as List;
      reports.add(reports.first);
      expect(() => Resumen.fromJson(duplicate), throwsFormatException);
    });

    test('un error de formato retira el resumen anterior y permite reintentar',
        () async {
      var calls = 0;
      final api = ApiClient(httpClient: MockClient((request) async {
        expect(request.url.path, '/api/administracion/resumen');
        return _json(calls++ == 1
            ? {'total_operaciones': 3}
            : apiFixture('administracion_resumen'));
      }));
      final provider = ReportesProvider(api);
      addTearDown(provider.dispose);
      addTearDown(api.close);
      await provider.cargar();
      expect(provider.resumen!.totalCreditos, 3);
      await provider.cargar();
      expect(provider.error, isNotNull);
      expect(provider.resumen, isNull);
      expect(provider.cargando, isFalse);
      await provider.cargar();
      expect(provider.error, isNull);
      expect(provider.resumen!.totalCreditos, 3);
    });

    test('no revive el resumen después de cerrar la pantalla o la sesión',
        () async {
      final response = Completer<http.Response>();
      final api = ApiClient(httpClient: MockClient((_) => response.future));
      addTearDown(api.close);
      final provider = ReportesProvider(api);
      final pending = provider.cargar();
      provider.dispose();
      response.complete(_json(apiFixture('administracion_resumen')));
      await expectLater(pending, completes);
      expect(provider.resumen, isNull);
    });
  });

  testWidgets('el panel muestra USD y EUR en importes separados',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 900);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final api = ApiClient(
        httpClient: MockClient(
            (_) async => _json(apiFixture('administracion_resumen'))));
    addTearDown(api.close);
    await tester.pumpWidget(ChangeNotifierProvider(
      create: (_) => ReportesProvider(api),
      child: MaterialApp(
          theme: CreditoTheme.light,
          home: const Scaffold(body: DashboardScreen())),
    ));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.textContaining('1,535.00'), findsOneWidget);
    expect(find.textContaining('252.00'), findsOneWidget);
    expect(find.textContaining('1,787.00'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
      'detalle de crédito distingue historial privado de pagos inexistentes',
      (tester) async {
    final data = _credito()..remove('pagos');
    await tester.pumpWidget(MaterialApp(
      theme: CreditoTheme.light,
      home: OperacionDetalleScreen(operacion: Operacion.fromJson(data)),
    ));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.textContaining('610.00'), findsOneWidget);
    expect(find.text('Todavía no se registran pagos.'), findsNothing);
    expect(find.textContaining('compart'), findsWidgets);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
