import '../models/financiamiento.dart';
import '../models/operacion.dart';
import 'api_client.dart';

class CreditoService {
  const CreditoService(this.api);
  final ApiClient api;
  Future<Operacion> obtener(String id) async =>
      Operacion.fromJson(objetoFinanciero(
          await api.get('/api/creditos/${Uri.encodeComponent(id)}')));
  Future<ResultadoCredito> crear(String ofertaId) async =>
      ResultadoCredito.fromJson(
          await api.post('/api/creditos', {'oferta_id': ofertaId}));
  Future<ResultadoCredito> pagar(String creditoId,
          {required int montoCentavos, required String referencia}) async =>
      ResultadoCredito.fromJson(await api.post(
          '/api/creditos/${Uri.encodeComponent(creditoId)}/pagos',
          {'referencia': referencia, 'monto_centavos': montoCentavos}));
  Future<ResultadoCredito> sincronizar(String id) async =>
      ResultadoCredito.fromJson(await api
          .post('/api/creditos/${Uri.encodeComponent(id)}/sincronizar', {}));
  Future<ResultadoAporte> confirmarAporte(String id) async =>
      ResultadoAporte.fromJson(await api.post(
          '/api/creditos/aportes/${Uri.encodeComponent(id)}/confirmar', {}));
}
