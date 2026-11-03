import 'api_client.dart';

class EmpresaService {
  EmpresaService(this._api);
  final ApiClient _api;

  Future<void> crear(Map<String, String> datos) async {
    await _api.post('/api/empresas', {
      'nombre': datos['nombre'] ?? '',
      'nit': datos['nit'] ?? '',
      'correo': datos['correo'] ?? '',
      'telefono': datos['telefono'] ?? '',
      'direccion': datos['direccion'] ?? '',
    });
  }
}