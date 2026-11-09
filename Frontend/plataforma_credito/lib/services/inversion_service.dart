import '../models/financiamiento.dart';
import 'api_client.dart';

class InversionService {
  const InversionService(this.api);
  final ApiClient api;

  Future<ResultadoRecuperacion> recuperar({String? bookmark}) async {
    final ruta = Uri(
            path: '/api/inversiones/recuperar',
            queryParameters: bookmark == null || bookmark.isEmpty
                ? null
                : {'bookmark': bookmark})
        .toString();
    return ResultadoRecuperacion.fromJson(await api.post(ruta, {}));
  }

  Future<Oferta> actualizarOferta(String id) async {
    String? cursor;
    final vistos = <String>{};
    while (true) {
      final pagina = await ofertas(bookmark: cursor, limit: 100);
      for (final oferta in pagina.items) {
        if (oferta.id == id) return oferta;
      }
      if (pagina.items.isEmpty ||
          pagina.bookmark.isEmpty ||
          !vistos.add(pagina.bookmark)) {
        break;
      }
      cursor = pagina.bookmark;
    }
    throw ApiException(
        'La oferta ya no está disponible. Actualiza el catálogo.', 404);
  }

  Future<PaginaFinanciera<Oferta>> ofertas(
          {String? estado, String? bookmark, int limit = 20}) async =>
      PaginaFinanciera.desdeJson(
          await api.get('/api/ofertas', query: {
            'limit': '$limit',
            if (estado != null) 'estado': estado,
            if (bookmark != null && bookmark.isNotEmpty) 'bookmark': bookmark,
          }),
          'ofertas',
          Oferta.fromJson);

  Future<PaginaFinanciera<Inversion>> inversiones(
          {String? bookmark, int limit = 20}) async =>
      PaginaFinanciera.desdeJson(
          await api.get('/api/inversiones', query: {
            'limit': '$limit',
            if (bookmark != null && bookmark.isNotEmpty) 'bookmark': bookmark,
          }),
          'inversiones',
          Inversion.fromJson);

  Future<Oferta> crearOferta(
          {required String facturaId,
          required int montoCentavos,
          required double tasaAnual,
          required DateTime fechaCierre}) async =>
      Oferta.fromJson(objetoFinanciero(await api.post('/api/ofertas', {
        'factura_id': facturaId,
        'monto_objetivo': montoCentavos / 100,
        'tasa_rendimiento_anual': tasaAnual,
        'fecha_cierre': fechaCierre.toUtc().toIso8601String(),
      })));

  Future<Inversion> invertir(
          {required String ofertaId,
          required int montoCentavos,
          required String claveIdempotencia}) async =>
      Inversion.fromJson(objetoFinanciero(await api.post('/api/inversiones',
          {'oferta_id': ofertaId, 'monto': montoCentavos / 100},
          idempotencyKey: claveIdempotencia)));
}
