import 'package:flutter/foundation.dart';

import '../../../core/estado_carga.dart';
import '../../../models/crear_factura.dart';
import '../../../models/empresa_opcion.dart';
import '../../../models/estado_factura.dart';
import '../../../models/factura.dart';
import '../../../services/api_exception.dart';
import '../../../services/factura_service.dart';

class FacturasProvider extends ChangeNotifier {
  FacturasProvider(this._servicio);
  final FacturaService _servicio;
  EstadoCarga _estadoCarga = EstadoCarga.inicial;
  List<Factura> _facturas = const [];
  String? _mensajeError, _errorMas, _bookmark;
  EstadoFactura? _filtro;
  int? _limite;
  final _cursores = <String>{};
  int _solicitud = 0;
  bool _cerrado = false, _cargandoMas = false, _hayMas = false;

  EstadoCarga get estadoCarga => _estadoCarga;
  List<Factura> get facturas => _facturas;
  String? get mensajeError => _mensajeError;
  String? get errorMas => _errorMas;
  EstadoFactura? get filtro => _filtro;
  String? get bookmark => _bookmark;
  int? get limite => _limite;
  bool get cargandoMas => _cargandoMas;
  bool get hayMas => _hayMas;

  Future<void> cargar() => _leer(mas: false);
  Future<void> cargarMas() => _leer(mas: true);

  Future<void> _leer({required bool mas}) async {
    if (_cerrado ||
        (mas &&
            (!_hayMas || _cargandoMas || _estadoCarga == EstadoCarga.cargando))) {
      return;
    }
    final solicitud = ++_solicitud;
    final filtro = _filtro;
    var cursor = mas ? _bookmark : null;
    if (mas) {
      _cargandoMas = true;
      _errorMas = null;
    } else {
      _estadoCarga = EstadoCarga.cargando;
      _cargandoMas = false;
      _mensajeError = null;
      _errorMas = null;
      _bookmark = null;
      _limite = null;
      _hayMas = false;
      _cursores.clear();
    }
    _notificar();
    try {
      final cursores = <String>{..._cursores};
      while (true) {
        final pagina =
            await _servicio.listar(estado: filtro, limit: 50, bookmark: cursor);
        if (!_vigente(solicitud)) return;
        if (pagina.limit < 1 ||
            pagina.limit > 100 ||
            pagina.facturas.length > pagina.limit) {
          throw const FormatException('Página de facturas incompatible');
        }
        final avanza =
            pagina.bookmark.isNotEmpty && cursores.add(pagina.bookmark);
        if (pagina.facturas.isEmpty && avanza) {
          cursor = pagina.bookmark;
          continue;
        }
        _facturas = List.unmodifiable({
          for (final factura in [
            ...(mas ? _facturas : <Factura>[]),
            ...pagina.facturas
          ])
            factura.id: factura,
        }.values);
        _bookmark = pagina.bookmark;
        _limite = pagina.limit;
        _hayMas = avanza;
        _cursores
          ..clear()
          ..addAll(cursores);
        _estadoCarga = EstadoCarga.listo;
        break;
      }
    } catch (error) {
      if (!_vigente(solicitud)) return;
      final mensaje = error is ApiException
          ? error.message
          : 'No se pudo leer el listado de facturas. Intenta nuevamente.';
      if (mas) {
        _errorMas = mensaje;
      } else {
        _facturas = const [];
        _estadoCarga = EstadoCarga.error;
        _mensajeError = mensaje;
      }
    } finally {
      if (_vigente(solicitud)) {
        _cargandoMas = false;
        _notificar();
      }
    }
  }

  Future<void> filtrarPor(EstadoFactura? estado) async {
    if (_cerrado) return;
    _filtro = estado;
    await cargar();
  }

  Future<List<EmpresaOpcion>> cargarEmpresas() => _servicio.listarEmpresas();
  Future<void> crear(CrearFactura datos) async {
    await _servicio.crear(datos);
    if (!_cerrado) await cargar();
  }

  bool _vigente(int solicitud) => !_cerrado && solicitud == _solicitud;
  void _notificar() {
    if (!_cerrado) notifyListeners();
  }

  @override
  void dispose() {
    _cerrado = true;
    _solicitud++;
    super.dispose();
  }
}
