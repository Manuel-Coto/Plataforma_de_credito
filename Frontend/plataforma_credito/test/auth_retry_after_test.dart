import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:plataforma_credito/main.dart';
import 'package:plataforma_credito/modules/usuarios/providers/sesion_provider.dart';
import 'package:plataforma_credito/services/api_client.dart';

void main() {
  test('429 conserva segundos, fecha HTTP y espera predeterminada', () async {
    for (final header in [
      '7',
      HttpDate.format(DateTime.now().toUtc().add(const Duration(seconds: 30))),
      'incorrecto'
    ]) {
      final api = ApiClient(
          httpClient: MockClient((_) async => http.Response(
              '{"error":"Demasiados intentos"}', 429,
              headers: {'retry-after': header})));
      try {
        await api.post('/api/auth/login', {});
        fail('Debe rechazar 429');
      } on ApiException catch (error) {
        expect(error.status, 429);
        if (header == '7') expect(error.retryAfter, const Duration(seconds: 7));
        if (header == 'incorrecto') {
          expect(error.retryAfter, const Duration(seconds: 60));
        }
        expect(error.retryAfter!.inSeconds, greaterThan(0));
      } finally {
        api.close();
      }
    }
  });

  for (final register in [false, true]) {
    testWidgets(
        '429 bloquea ${register ? 'registro' : 'login'} y libera al finalizar',
        (tester) async {
      var requests = 0;
      final api = ApiClient(httpClient: MockClient((_) async {
        requests++;
        return http.Response('{"error":"Espera para reintentar"}', 429,
            headers: {'retry-after': '3'});
      }));
      await tester.pumpWidget(PlataformaCreditoApp(apiClient: api));
      if (register) {
        await tester.tap(find.text('¿No tienes cuenta? Crear una cuenta'));
        await tester.pumpAndSettle();
        final fields = find.byType(TextFormField);
        await tester.enterText(fields.at(0), 'Cuenta ficticia');
        await tester.enterText(fields.at(1), 'retry@example.test');
        await tester.enterText(fields.at(2), 'Solo-Prueba-2026!');
      } else {
        await tester.enterText(
            find.widgetWithText(TextFormField, 'Correo electrónico'),
            'retry@example.test');
        await tester.enterText(find.widgetWithText(TextFormField, 'Contraseña'),
            'Solo-Prueba-2026!');
      }
      final label = register ? 'Crear cuenta' : 'Iniciar sesión';
      await tester.ensureVisible(find.widgetWithText(FilledButton, label));
      await tester.tap(find.widgetWithText(FilledButton, label));
      await tester.pumpAndSettle();
      expect(requests, 1);
      expect(find.text('Reintentar en 3 s'), findsOneWidget);
      expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
          isNull);
      final provider = Provider.of<SesionProvider>(
          tester.element(find.byType(FilledButton)),
          listen: false);
      await expectLater(provider.registrar({}), throwsA(isA<ApiException>()));
      expect(requests, 1);
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
      expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
          isNotNull);
      await tester.tap(find.widgetWithText(FilledButton, label));
      await tester.pumpAndSettle();
      expect(requests, 2);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
