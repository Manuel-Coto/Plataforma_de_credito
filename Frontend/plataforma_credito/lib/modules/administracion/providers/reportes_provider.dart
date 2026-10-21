import 'package:flutter/foundation.dart';
import 'package:plataforma_credito/services/api_client.dart';
import 'package:plataforma_credito/models/resumen.dart';

class ReportesProvider extends ChangeNotifier {
  ReportesProvider(this._api);
  final ApiClient _api;

  Resumen? resumen;
  bool cargando = false;
  String? error;

  Future<void> cargar() async {
    cargando = true;
    error = null;
    notifyListeners();
    try {
      final data = await _api.get('/api/reportes/resumen');
      resumen = Resumen.fromJson(data as Map<String, dynamic>);
    } on ApiException catch (e) {
      error = e.message;
    }
    cargando = false;
    notifyListeners();
  }
}
