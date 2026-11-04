import 'package:flutter/foundation.dart';
import 'package:plataforma_credito/services/api_client.dart';

class EmpresasAdminProvider extends ChangeNotifier {
  EmpresasAdminProvider(this._api);
  final ApiClient _api;

  static const _limite = 50;
  static const _maxPaginas = 20;

  List<Map<String, dynamic>> pendientes = [];
  bool cargando = false;
  String? error;
  bool _cerrado = false;

  @override
  void notifyListeners() {
    if (!_cerrado) super.notifyListeners();
  }

  @override
  void dispose() {
    _cerrado = true;
    super.dispose();
  }

  /// El backend no filtra por estado: se piden las páginas y se filtra aquí.
  Future<void> cargar() async {
    cargando = true;
    error = null;
    notifyListeners();
    try {
      final todas = <Map<String, dynamic>>[];
      String? bookmark;
      for (var i = 0; i < _maxPaginas; i++) {
        final ruta = (bookmark == null || bookmark.isEmpty)
            ? '/api/empresas?limit=$_limite'
            : '/api/empresas?limit=$_limite'
            '&bookmark=${Uri.encodeQueryComponent(bookmark)}';
        final data = await _api.get(ruta) as Map<String, dynamic>;
        final pagina =
        (data['empresas'] as List).cast<Map<String, dynamic>>();
        todas.addAll(pagina);
        final siguiente = data['bookmark'] as String? ?? '';
        if (pagina.isEmpty || siguiente.isEmpty || siguiente == bookmark) {
          break;
        }
        bookmark = siguiente;
      }
      pendientes = todas.where((e) => e['estado'] == 'pendiente').toList();
    } on ApiException catch (e) {
      error = e.message;
    } catch (e) {
      error = 'Respuesta inesperada del servidor: $e';
    }
    cargando = false;
    notifyListeners();
  }

  Future<void> aprobar(String id) => _revisar(id, 'aprobar');

  Future<void> rechazar(String id, String motivo) =>
      _revisar(id, 'rechazar', cuerpo: {'motivo': motivo});

  /// Flujo con concurrencia optimista: GET para leer el ETag y PATCH con If-Match.
  Future<void> _revisar(
      String id,
      String accion, {
        Map<String, dynamic>? cuerpo,
      }) async {
    final actual = await _api.getConEtag('/api/empresas/$id');
    final etag = actual.etag;
    if (etag == null || etag.isEmpty) {
      throw ApiException('El servidor no devolvió el ETag de la empresa.');
    }
    await _api.patch('/api/empresas/$id/$accion', cuerpo: cuerpo, ifMatch: etag);
    await cargar();
  }
}