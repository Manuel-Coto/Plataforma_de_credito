import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:plataforma_credito/core/theme/credito_theme.dart';
import 'package:plataforma_credito/modules/empresas/screens/empresa_revision_screen.dart';
import 'package:plataforma_credito/modules/usuarios/providers/sesion_provider.dart';
import 'package:plataforma_credito/services/api_client.dart';

void main() {
  for (final scenario in [(false, true), (true, true), (false, false)]) {
    final conflict = scenario.$1;
    final aprobar = scenario.$2;
    testWidgets(
        conflict
            ? 'Conflicto recarga sin repetir la decisión'
            : '${aprobar ? 'Aprueba' : 'Rechaza'} con el ETag y token consultados',
        (tester) async {
      var state = 'pendiente';
      var reads = 0;
      var writes = 0;
      final api = ApiClient(httpClient: MockClient((request) async {
        if (request.url.path == '/api/auth/login') {
          return http.Response(
              jsonEncode({
                'access_token': 'test-token',
                'token_type': 'Bearer',
                'expires_in': 3600,
                'usuario': {
                  'id': 'admin',
                  'nombre': 'Admin',
                  'correo': 'admin@example.test',
                  'rol': 'administrador',
                  'estado': 'activo'
                }
              }),
              200);
        }
        expect(request.headers['Authorization'], 'Bearer test-token');
        if (request.method == 'PATCH') {
          writes++;
          expect(request.url.path,
              '/api/empresas/empresa-1/${aprobar ? 'aprobar' : 'rechazar'}');
          expect(request.headers['If-Match'], '"1-original"');
          expect(request.body, isEmpty);
          if (conflict) {
            state = 'rechazada';
            return http.Response('{"error":"Revision obsoleta"}', 412);
          }
          state = aprobar ? 'activa' : 'rechazada';
        } else {
          reads++;
        }
        return http.Response(
            jsonEncode({
              'id': 'empresa-1',
              'nombre': 'Empresa ficticia',
              'nit': '123456789',
              'estado': state,
              'correo': 'contacto@example.test',
              'telefono': '22223344',
              'direccion': 'San Salvador',
              'usuario_responsable_id': 'pyme-1'
            }),
            200,
            headers: {
              'etag': reads == 1 && writes == 0 ? '"1-original"' : '"2-nueva"'
            });
      }));
      final session = SesionProvider(api);
      await session.ingresar('admin@example.test', 'test-password');
      await tester.pumpWidget(ChangeNotifierProvider.value(
          value: session,
          child: MaterialApp(
              theme: CreditoTheme.light,
              home: const EmpresaDecisionScreen(id: 'empresa-1'))));
      await tester.pumpAndSettle();
      final approve =
          find.text(aprobar ? 'Aprobar empresa' : 'Rechazar empresa');
      await tester.ensureVisible(approve);
      await tester.tap(approve);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Confirmar'));
      await tester.pumpAndSettle();
      expect(writes, 1);
      expect(reads, 2);
      expect(
          find.text('Estado: ${conflict || !aprobar ? 'rechazada' : 'activa'}'),
          findsOneWidget);
      expect(find.text('Aprobar empresa'), findsNothing);
      if (conflict) {
        expect(find.textContaining('Revisa los datos actualizados'),
            findsOneWidget);
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      session.dispose();
      api.close();
    });
  }
}
