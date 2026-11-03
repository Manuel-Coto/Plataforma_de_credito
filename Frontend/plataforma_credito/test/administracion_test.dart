import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:plataforma_credito/modules/administracion/providers/reportes_provider.dart';
import 'package:plataforma_credito/services/api_client.dart';

void main() {
  test('carga el resumen administrativo y distingue estados y monedas', () async {
    final api = ApiClient(httpClient: MockClient((request) async {
      expect(request.url.path, '/api/administracion/resumen');
      return http.Response(jsonEncode({
        'reportes': [
          {'modulo': 'facturas', 'por_estado': {'pendiente_verificacion': 3}},
          {'modulo': 'empresas', 'por_estado': {'activa': 4}},
          {
            'modulo': 'creditos',
            'total': 2,
            'por_estado': {'activo': 1, 'pagado': 1},
            'montos_por_moneda': {
              'USD': {'total_centavos': 1200},
              'EUR': {'total_centavos': 900},
            },
          },
        ],
      }), 200);
    }));
    addTearDown(api.close);
    final provider = ReportesProvider(api);
    await provider.cargar();
    final resumen = provider.resumen!;
    expect(resumen.totalCreditos, 2);
    expect(resumen.totalesPorMoneda, {'USD': 1200, 'EUR': 900});
    expect(resumen.porEstado, {'activo': 1, 'pagado': 1});
    expect(resumen.empresasActivas, 4);
    expect(resumen.facturasPendientes, 3);
  });
}
