import '../models/crear_factura.dart';
import '../models/estado_factura.dart';
import '../models/factura.dart';
import '../models/factura_pagina.dart';
import 'api_client.dart';
import '../models/empresa_opcion.dart';

class FacturaService {
  // Recibe el cliente HTTP ya creado (inyección de dependencias).
  // El servicio no sabe de URLs ni de tokens: eso es trabajo del cliente.
  const FacturaService(this._api);

  final ApiClient _api;

  Future<Factura> verificarDte(String id, String sello) async {
    final datos = await _api.patch(
        '/api/facturas/${Uri.encodeComponent(id)}/verificar-dte',
        {'sello_recepcion': sello.trim()});
    return Factura.fromJson(datos as Map<String, dynamic>);
  }

  /// GET /api/facturas, con filtros opcionales.
  Future<FacturaPagina> listar({
    EstadoFactura? estado,
    int? limit,
    String? bookmark,
  }) async {
    // Solo se incluyen los filtros que el usuario realmente indicó.
    final query = <String, String>{
      if (estado != null) 'estado': estado.valorApi,
      if (limit != null) 'limit': '$limit',
      if (bookmark != null && bookmark.isNotEmpty) 'bookmark': bookmark,
    };

    final datos = await _api.get('/api/facturas', query: query);
    return FacturaPagina.fromJson(datos as Map<String, dynamic>);
  }

  /// GET /api/facturas/{id}
  Future<Factura> obtener(String id) async {
    // encodeComponent protege la ruta si el id trae caracteres especiales.
    final datos = await _api.get('/api/facturas/${Uri.encodeComponent(id)}');
    return Factura.fromJson(datos as Map<String, dynamic>);
  }

  /// POST /api/facturas. Devuelve la factura ya creada, con su id.
  Future<Factura> crear(CrearFactura factura) async {
    final datos = await _api.post('/api/facturas', factura.toJson());
    return Factura.fromJson(datos as Map<String, dynamic>);
  }

  /// Empresas visibles para el usuario (una pyme ve solo las suyas).
  Future<List<EmpresaOpcion>> listarEmpresas() async {
    final empresas = <String, EmpresaOpcion>{};
    final cursores = <String>{};
    String? cursor;
    while (true) {
      final datos = await _api.get('/api/empresas', query: {
        'limit': '100',
        if (cursor != null) 'bookmark': cursor,
      });
      if (datos is! Map<String, dynamic> ||
          datos['empresas'] is! List ||
          datos['bookmark'] is! String ||
          datos['limit'] is! int ||
          (datos['limit'] as int) < 1 ||
          (datos['limit'] as int) > 100) {
        throw const FormatException('Página de empresas incompatible');
      }
      final lista = datos['empresas'] as List;
      for (final item in lista) {
        final empresa = EmpresaOpcion.fromJson(item as Map<String, dynamic>);
        empresas[empresa.id] = empresa;
      }
      final siguiente = datos['bookmark'] as String;
      if (siguiente.isEmpty || !cursores.add(siguiente)) break;
      cursor = siguiente;
    }
    return List.unmodifiable(empresas.values);
  }
}
