import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:plataforma_credito/modules/creditos/providers/operaciones_provider.dart';
import 'package:plataforma_credito/services/api_client.dart';

void main() {
  test('carga créditos paginados y conserva el total pagado sin historial', () async {
    final rutas = <Uri>[];
    final api = ApiClient(httpClient: MockClient((request) async {
      rutas.add(request.url);
      final primera = rutas.length == 1;
      return http.Response(jsonEncode({
        'creditos': [
          {
            'id': primera ? 'credito:1' : 'credito:2',
            'total_centavos': 10000,
            'pagado_centavos': 2500,
          },
        ],
        'bookmark': primera ? 'siguiente' : '',
      }), 200);
    }));
    addTearDown(api.close);
    final provider = OperacionesProvider(api);
    await provider.cargar();

    expect(rutas.map((uri) => uri.path), ['/api/creditos', '/api/creditos']);
    expect(rutas.last.queryParameters['bookmark'], 'siguiente');
    expect(provider.operaciones.map((o) => o.id), ['credito:1', 'credito:2']);
    expect(provider.operaciones.first.progreso, 0.25);
    expect(provider.operaciones.first.historialVisible, isFalse);
  });
}
