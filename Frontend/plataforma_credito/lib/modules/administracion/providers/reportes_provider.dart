import 'package:flutter/foundation.dart';
import 'package:plataforma_credito/models/resumen.dart';
import 'package:plataforma_credito/services/api_client.dart';

class ReportesProvider extends ChangeNotifier {
  ReportesProvider(this._api);
  final ApiClient _api;

  Resumen? resumen;
  bool cargando = false;
  String? error;
  int _solicitud = 0;
  bool _cerrado = false;

  bool _vigente(int solicitud) => !_cerrado && solicitud == _solicitud;

  Future<void> cargar() async {
    if (_cerrado) return;
    final solicitud = ++_solicitud;
    cargando = true;
    error = null;
    resumen = null;
    notifyListeners();
    try {
      final data = await _api.get('/api/administracion/resumen');
      if (!_vigente(solicitud)) return;
      if (data is! Map<String, dynamic>) {
        throw const FormatException('El resumen debe ser un objeto.');
      }
      final actualizado = Resumen.fromJson(data);
      if (_vigente(solicitud)) resumen = actualizado;
    } on ApiException catch (exception) {
      if (_vigente(solicitud)) error = exception.message;
    } on FormatException {
      if (_vigente(solicitud)) {
        error =
            'El servidor devolvió un resumen con un formato incompatible. Intenta actualizar nuevamente.';
      }
    } catch (_) {
      if (_vigente(solicitud)) {
        error = 'No se pudo cargar el resumen. Intenta nuevamente.';
      }
    } finally {
      if (_vigente(solicitud)) {
        cargando = false;
        notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    _cerrado = true;
    _solicitud++;
    super.dispose();
  }
}
