import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:plataforma_credito/main.dart';
import 'package:plataforma_credito/services/api_client.dart';

import 'support/api_fixtures.dart';

Future<void> _capture(WidgetTester tester, GlobalKey key, String name) async {
  const output = String.fromEnvironment('DESIGN_PREVIEW_DIR');
  if (output.isEmpty) return;
  await tester.runAsync(() async {
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 1);
    try {
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final directory = await Directory(output).create(recursive: true);
      await File('${directory.path}/$name.png')
          .writeAsBytes(bytes!.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    const output = String.fromEnvironment('DESIGN_PREVIEW_DIR');
    if (output.isEmpty) return;
    final font = FontLoader('Segoe UI');
    for (final name in ['segoeui.ttf', 'seguisb.ttf', 'segoeuib.ttf']) {
      final source = File('C:/Windows/Fonts/$name');
      if (await source.exists()) {
        font.addFont(
            Future.value(ByteData.sublistView(await source.readAsBytes())));
      }
    }
    await font.load();
    final icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();
  });
  for (final size in [
    const Size(390, 844),
    const Size(800, 600),
    const Size(1280, 500),
    const Size(1440, 1000)
  ]) {
    testWidgets('Acceso y navegación se adaptan a ${size.width.toInt()} px',
        (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = size;
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final captureKey = GlobalKey();
      final api = ApiClient(httpClient: MockClient((request) async {
        if (request.url.path == '/api/auth/login') {
          return http.Response(
              jsonEncode({
                'access_token': 'token-layout',
                'token_type': 'Bearer',
                'expires_in': 3600,
                'usuario': {
                  'id': 'usuario:layout',
                  'nombre': 'María de los Ángeles',
                  'correo': 'maria@example.test',
                  'rol': 'administrador',
                  'estado': 'activo'
                },
              }),
              200,
              headers: const {
                'content-type': 'application/json; charset=utf-8'
              });
        }
        if (request.url.path == '/api/administracion/resumen') {
          return http.Response(
              jsonEncode(apiFixture('administracion_resumen')), 200);
        }
        if (request.url.path == '/api/creditos') {
          return http.Response(jsonEncode(apiFixture('creditos_pagina')), 200);
        }
        if (request.url.path == '/api/facturas') {
          return http.Response('{"facturas":[],"bookmark":"","limit":50}', 200);
        }
        if (request.url.path == '/api/empresas') {
          return http.Response(
              '{"empresas":[],"bookmark":"","limit":100}', 200);
        }
        return http.Response('{"error":"Ruta no prevista en la prueba"}', 404);
      }));
      await tester.pumpWidget(RepaintBoundary(
          key: captureKey, child: PlataformaCreditoApp(apiClient: api)));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      if (size.width == 1440) await _capture(tester, captureKey, 'acceso');
      if (size.width == 390) {
        final register = find.text('¿No tienes cuenta? Crear una cuenta');
        await tester.ensureVisible(register);
        await tester.tap(register);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(
            find.widgetWithText(FilledButton, 'Crear cuenta'), findsOneWidget);
        await tester.tap(find.text('Volver a iniciar sesión'));
        await tester.pumpAndSettle();
      }
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Correo electrónico'),
          'maria@example.test');
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Contraseña'), 'Prueba-123456!');
      final login = find.widgetWithText(FilledButton, 'Iniciar sesión');
      await tester.ensureVisible(login);
      await tester.tap(login);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('María de los Ángeles'), findsOneWidget);
      if (size.width >= 1000) {
        expect(find.byType(NavigationBar), findsNothing);
        await _capture(tester, captureKey, 'mi-espacio');
      } else {
        expect(find.byType(NavigationBar), findsOneWidget);
        if (size.width == 390) await _capture(tester, captureKey, 'movil');
      }
      await tester.tap(find.text('Facturas').first);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Filtrar por estado'), findsOneWidget);
      expect(find.text('Nueva factura'), findsNothing);
      final navigationLabels = size.width >= 1000
          ? ['Empresas', 'Créditos y pagos', 'Administración']
          : ['Empresas', 'Créditos', 'Panel'];
      for (final label in navigationLabels) {
        final destination = find.text(label).first;
        await tester.ensureVisible(destination);
        await tester.tap(destination);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: label);
      }
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
