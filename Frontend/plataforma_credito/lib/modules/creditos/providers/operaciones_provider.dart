import 'package:flutter/foundation.dart';
import 'package:plataforma_credito/services/api_client.dart';
import 'package:plataforma_credito/models/operacion.dart';
import '../../../models/financiamiento.dart';
import '../../../services/credito_service.dart';

class IntentoPago {
  IntentoPago(this.montoCentavos) : referencia = nuevaReferenciaFinanciera();
  final int montoCentavos;
  final String referencia;
}

class OperacionesProvider extends ChangeNotifier {
  OperacionesProvider(this._api) : servicio = CreditoService(_api);
  final ApiClient _api;
  final CreditoService servicio;
  final _intentosPago = <String, IntentoPago>{};
  final _acciones = <String>{};
  final sincronizacionPendiente = <String>{};
  IntentoPago? intentoPago(String id) => _intentosPago[id];
  bool ocupado(String id) => _acciones.contains(id);

  Future<ResultadoCredito> pagar(Operacion credito, int montoCentavos) async {
    if (_disposed) throw ApiException('La sesión ya no está disponible.');
    final intento =
        _intentosPago.putIfAbsent(credito.id, () => IntentoPago(montoCentavos));
    if (intento.montoCentavos != montoCentavos) {
      throw ApiException(
          'Primero reintenta el pago pendiente con el mismo monto.');
    }
    if (!_acciones.add(credito.id)) {
      throw ApiException('El pago ya está en curso.');
    }
    notifyListeners();
    try {
      final resultado = await servicio.pagar(credito.id,
          montoCentavos: intento.montoCentavos, referencia: intento.referencia);
      if (!_disposed) {
        _intentosPago.remove(credito.id);
        _actualizar(resultado);
      }
      return resultado;
    } catch (exception) {
      if (!_disposed &&
          exception is ApiException &&
          exception.status != null &&
          exception.status! >= 400 &&
          exception.status! < 500 &&
          exception.status != 408 &&
          exception.status != 429) {
        _intentosPago.remove(credito.id);
      }
      rethrow;
    } finally {
      _acciones.remove(credito.id);
      if (!_disposed) notifyListeners();
    }
  }

  Future<ResultadoCredito> sincronizar(String id) async {
    if (_disposed) throw ApiException('La sesión ya no está disponible.');
    if (!_acciones.add(id)) {
      throw ApiException('La operación ya está en curso.');
    }
    notifyListeners();
    try {
      final resultado = await servicio.sincronizar(id);
      if (!_disposed) _actualizar(resultado);
      return resultado;
    } finally {
      _acciones.remove(id);
      if (!_disposed) notifyListeners();
    }
  }

  void incorporar(ResultadoCredito resultado) {
    if (_disposed) return;
    _actualizar(resultado);
    notifyListeners();
  }

  void _actualizar(ResultadoCredito resultado) {
    _solicitud++; // Una lectura anterior no debe restaurar el saldo previo.
    cargando = false;
    cargandoMas = false;
    error = null;
    errorMas = null;
    _todas = List.unmodifiable({
      for (final item in [..._todas, resultado.credito]) item.id: item
    }.values);
    if (resultado.sincronizacionPendiente) {
      sincronizacionPendiente.add(resultado.credito.id);
    } else {
      sincronizacionPendiente.remove(resultado.credito.id);
    }
  }

  List<Operacion> _todas = const [];
  bool _disposed = false;
  int _solicitud = 0;
  bool cargando = false;
  bool cargandoMas = false;
  bool hayMas = false;
  String? error;
  String? errorMas;
  String? filtro;
  String? bookmark;
  int? limite;
  final _cursores = <String>{};

  List<Operacion> get operaciones => List.unmodifiable(filtro == null
      ? _todas
      : _todas.where((operacion) => operacion.estadoVisible == filtro));

  // Vencido es una vista derivada del backend, no un estado almacenado.
  List<String> get estados => const ['activo', 'vencido', 'pagado'];

  Future<void> setFiltro(String? value) async {
    if (_disposed || (value != null && !estados.contains(value))) return;
    filtro = value;
    await cargar();
  }

  Future<void> cargar() => _leer(mas: false);
  Future<void> cargarMas() => _leer(mas: true);

  Future<void> _leer({required bool mas}) async {
    if (_disposed || (mas && (!hayMas || cargando || cargandoMas))) return;
    final solicitud = ++_solicitud;
    final filtroActual = filtro;
    final filtroApi = filtroActual == 'vencido' ? 'activo' : filtroActual;
    var cursor = mas ? bookmark : null;
    if (mas) {
      cargandoMas = true;
      errorMas = null;
    } else {
      cargando = true;
      cargandoMas = false;
      error = null;
      errorMas = null;
      bookmark = null;
      limite = null;
      hayMas = false;
      _cursores.clear();
    }
    notifyListeners();
    try {
      final acumulados = <String, Operacion>{
        if (mas)
          for (final item in _todas) item.id: item,
      };
      final cursores = <String>{..._cursores};
      final visiblesAntes = mas ? operaciones.length : 0;
      while (true) {
        final response = await _api.get('/api/creditos', query: {
          'limit': '50',
          if (filtroApi != null) 'estado': filtroApi,
          if (cursor != null && cursor.isNotEmpty) 'bookmark': cursor,
        });
        if (_disposed || solicitud != _solicitud) return;
        if (response is! Map<String, dynamic> ||
            response['creditos'] is! List ||
            response['bookmark'] is! String ||
            response['limit'] is! int ||
            (response['limit'] as int) < 1 ||
            (response['limit'] as int) > 100 ||
            (response['creditos'] as List).length >
                (response['limit'] as int)) {
          throw const FormatException('Página de créditos inválida');
        }
        final pagina = (response['creditos'] as List).map((item) {
          if (item is! Map<String, dynamic>) {
            throw const FormatException('Crédito inválido');
          }
          return Operacion.fromJson(item);
        }).toList(growable: false);
        for (final item in pagina) {
          acumulados[item.id] = item;
        }
        final siguiente = response['bookmark'] as String;
        final avanza = siguiente.isNotEmpty && cursores.add(siguiente);
        final visibles = acumulados.values
            .where((item) =>
                filtroActual == null || item.estadoVisible == filtroActual)
            .length;
        // El filtro vencido es derivado. También se atraviesan páginas vacías
        // con un cursor nuevo para no declarar un vacío antes de terminar.
        if (avanza && (pagina.isEmpty || visibles <= visiblesAntes)) {
          cursor = siguiente;
          continue;
        }
        _todas = List.unmodifiable(acumulados.values);
        bookmark = siguiente;
        limite = response['limit'] as int;
        hayMas = avanza;
        _cursores
          ..clear()
          ..addAll(cursores);
        break;
      }
    } on ApiException catch (exception) {
      if (_disposed || solicitud != _solicitud) return;
      if (mas) {
        errorMas = exception.message;
      } else {
        _descartar(exception.message);
      }
    } on FormatException {
      if (_disposed || solicitud != _solicitud) return;
      const mensaje =
          'No pudimos leer la información de créditos. Intenta nuevamente.';
      if (mas) {
        errorMas = mensaje;
      } else {
        _descartar(mensaje);
      }
    } catch (_) {
      if (_disposed || solicitud != _solicitud) return;
      const mensaje = 'No se pudieron cargar los créditos. Intenta nuevamente.';
      if (mas) {
        errorMas = mensaje;
      } else {
        _descartar(mensaje);
      }
    } finally {
      if (!_disposed && solicitud == _solicitud) {
        cargando = false;
        cargandoMas = false;
        notifyListeners();
      }
    }
  }

  void _descartar(String mensaje) {
    _todas = const [];
    bookmark = null;
    limite = null;
    hayMas = false;
    _cursores.clear();
    error = mensaje;
  }

  @override
  void dispose() {
    _disposed = true;
    _solicitud++;
    _intentosPago.clear();
    super.dispose();
  }
}
