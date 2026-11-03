import 'package:flutter/foundation.dart';
import 'package:plataforma_credito/services/api_client.dart';
import 'package:plataforma_credito/models/operacion.dart';

class OperacionesProvider extends ChangeNotifier {
  OperacionesProvider(this._api);
  final ApiClient _api;

  List<Operacion> _todas = [];
  bool cargando = false;
  String? error;
  String? filtro; // null = todas

  List<Operacion> get operaciones =>
      filtro == null ? _todas : _todas.where((o) => o.estado == filtro).toList();
  List<String> get estados => _todas.map((o) => o.estado).toSet().toList()..sort();

  void setFiltro(String? f) {
    filtro = f;
    notifyListeners();
  }

  Future<void> cargar() async {
    cargando = true;
    error = null;
    notifyListeners();
    try {
      final resp = await _api.get('/api/creditos');
      // El backend puede devolver una lista directa o un objeto paginado
      // (por ejemplo {"items": [...], "bookmark": "..."}).
      final List data;
      if (resp is List) {
        data = resp;
      } else if (resp is Map<String, dynamic>) {
        data = (resp['items'] ??
            resp['data'] ??
            resp['creditos'] ??
            resp['resultados'] ??
            const []) as List;
      } else {
        data = const [];
      }
      _todas = data
          .map((e) => Operacion.fromJson(e as Map<String, dynamic>))
          .toList();
    } on ApiException catch (e) {
      error = e.message;
    } catch (e) {
      error = 'Respuesta inesperada del servidor: $e';
    }
    cargando = false;
    notifyListeners();
  }
}