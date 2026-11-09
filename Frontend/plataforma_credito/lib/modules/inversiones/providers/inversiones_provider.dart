import 'package:flutter/foundation.dart';

import '../../../models/financiamiento.dart';
import '../../../services/api_client.dart';
import '../../../services/credito_service.dart';
import '../../../services/inversion_service.dart';

class IntentoAporte {
  IntentoAporte(this.oferta, this.montoCentavos)
      : clave = nuevaReferenciaFinanciera();
  final Oferta oferta;
  final int montoCentavos;
  final String clave;
}

class InversionesProvider extends ChangeNotifier {
  InversionesProvider(this.servicio, this.creditos,
      {required this.rol, required this.usuarioId})
      : estadoOferta = rol == 'inversionista' ? 'abierta' : null;
  final InversionService servicio;
  final CreditoService creditos;
  final String rol, usuarioId;
  List<Oferta> ofertas = const [];
  List<Inversion> inversiones = const [];
  String? estadoOferta, errorOfertas, errorInversiones;
  bool cargandoOfertas = false, cargandoInversiones = false;
  bool masOfertas = false, masInversiones = false;
  String? _cursorOfertas, _cursorInversiones;
  final _cursoresOfertas = <String>{}, _cursoresInversiones = <String>{};
  final _cursoresRecuperacion = <String>{};
  int _lecturaOfertas = 0, _lecturaInversiones = 0;
  bool _cerrado = false;
  final _ocupadas = <String>{};
  final _intentos = <String, IntentoAporte>{};
  final sincronizacionesPendientes = <String>{};
  bool recuperando = false;
  String? cursorRecuperacion;
  ResultadoRecuperacion? recuperacion;
  bool get veHistorial => rol == 'administrador' || rol == 'inversionista';
  bool ocupado(String id) => _ocupadas.contains(id);
  IntentoAporte? intentoPendiente(String ofertaId) => _intentos[ofertaId];
  List<IntentoAporte> get aportesPendientes =>
      List.unmodifiable(_intentos.values);

  Future<void> cargar() async {
    await Future.wait([
      cargarOfertas(),
      if (veHistorial) cargarInversiones(),
    ]);
  }

  Future<void> filtrarOfertas(String? estado) async {
    estadoOferta = estado;
    await cargarOfertas();
  }

  Future<void> cargarOfertas({bool mas = false}) async {
    if (_cerrado || (mas && (cargandoOfertas || !masOfertas))) return;
    final lectura = ++_lecturaOfertas;
    var cursor = mas ? _cursorOfertas : null;
    cargandoOfertas = true;
    errorOfertas = null;
    if (!mas) {
      ofertas = const [];
      masOfertas = false;
      _cursorOfertas = null;
      _cursoresOfertas.clear();
    }
    _notificar();
    try {
      final cursores = <String>{..._cursoresOfertas};
      final estado = estadoOferta;
      while (true) {
        final pagina = await servicio.ofertas(estado: estado, bookmark: cursor);
        if (_cerrado || lectura != _lecturaOfertas) return;
        final avanza =
            pagina.bookmark.isNotEmpty && cursores.add(pagina.bookmark);
        if (pagina.items.isEmpty && avanza) {
          cursor = pagina.bookmark;
          continue;
        }
        ofertas = List.unmodifiable({
          for (final item in [...(mas ? ofertas : <Oferta>[]), ...pagina.items])
            item.id: item,
        }.values);
        masOfertas = avanza;
        _cursorOfertas = pagina.bookmark;
        _cursoresOfertas
          ..clear()
          ..addAll(cursores);
        break;
      }
    } catch (error) {
      if (_cerrado || lectura != _lecturaOfertas) return;
      if (!mas) ofertas = const [];
      errorOfertas = _mensaje(error);
    } finally {
      if (!_cerrado && lectura == _lecturaOfertas) {
        cargandoOfertas = false;
        _notificar();
      }
    }
  }

  Future<void> cargarInversiones({bool mas = false}) async {
    if (_cerrado ||
        !veHistorial ||
        (mas && (cargandoInversiones || !masInversiones))) {
      return;
    }
    final lectura = ++_lecturaInversiones;
    var cursor = mas ? _cursorInversiones : null;
    cargandoInversiones = true;
    errorInversiones = null;
    if (!mas) {
      inversiones = const [];
      masInversiones = false;
      _cursorInversiones = null;
      _cursoresInversiones.clear();
    }
    _notificar();
    try {
      final cursores = <String>{..._cursoresInversiones};
      while (true) {
        final pagina = await servicio.inversiones(bookmark: cursor);
        if (_cerrado || lectura != _lecturaInversiones) return;
        final avanza =
            pagina.bookmark.isNotEmpty && cursores.add(pagina.bookmark);
        if (pagina.items.isEmpty && avanza) {
          cursor = pagina.bookmark;
          continue;
        }
        inversiones = List.unmodifiable({
          for (final item in [
            ...(mas ? inversiones : <Inversion>[]),
            ...pagina.items
          ])
            item.id: item,
        }.values);
        masInversiones = avanza;
        _cursorInversiones = pagina.bookmark;
        _cursoresInversiones
          ..clear()
          ..addAll(cursores);
        break;
      }
    } catch (error) {
      if (_cerrado || lectura != _lecturaInversiones) return;
      if (!mas) inversiones = const [];
      errorInversiones = _mensaje(error);
    } finally {
      if (!_cerrado && lectura == _lecturaInversiones) {
        cargandoInversiones = false;
        _notificar();
      }
    }
  }

  Future<Inversion> invertir(Oferta oferta, int montoCentavos) async {
    if (rol != 'inversionista') {
      throw ApiException('Tu perfil no puede registrar aportes.');
    }
    final intento = _intentos.putIfAbsent(
        oferta.id, () => IntentoAporte(oferta, montoCentavos));
    if (intento.montoCentavos != montoCentavos) {
      throw ApiException(
          'Primero reintenta el aporte pendiente con el mismo monto.');
    }
    _iniciar(oferta.id);
    try {
      final inversion = await servicio.invertir(
          ofertaId: oferta.id,
          montoCentavos: intento.montoCentavos,
          claveIdempotencia: intento.clave);
      if (!_cerrado) {
        _intentos.remove(oferta.id);
        await cargar();
      }
      return inversion;
    } catch (error) {
      if (!_cerrado && errorDefinitivo(error)) _intentos.remove(oferta.id);
      rethrow;
    } finally {
      _ocupadas.remove(oferta.id);
      _notificar();
    }
  }

  Future<ResultadoAporte> confirmar(Inversion inversion) async {
    _iniciar(inversion.id);
    try {
      final resultado = await creditos.confirmarAporte(inversion.id);
      if (!_cerrado) {
        if (resultado.sincronizacionPendiente) {
          sincronizacionesPendientes.add(inversion.id);
        } else {
          sincronizacionesPendientes.remove(inversion.id);
        }
        await cargar();
      }
      return resultado;
    } finally {
      _ocupadas.remove(inversion.id);
      _notificar();
    }
  }

  Future<ResultadoCredito> crearCredito(Oferta oferta) async {
    if (rol != 'administrador') {
      throw ApiException('Esta acción requiere una cuenta administradora.');
    }
    _iniciar(oferta.id);
    try {
      final resultado = await creditos.crear(oferta.id);
      if (!_cerrado) await cargarOfertas();
      return resultado;
    } finally {
      _ocupadas.remove(oferta.id);
      _notificar();
    }
  }

  Future<ResultadoRecuperacion> recuperar() async {
    if (!veHistorial || _cerrado || recuperando) {
      throw ApiException('La recuperación no está disponible ahora.');
    }
    recuperando = true;
    _notificar();
    final anterior = cursorRecuperacion;
    if (anterior == null) _cursoresRecuperacion.clear();
    try {
      final result = await servicio.recuperar(bookmark: anterior);
      if (!_cerrado) {
        recuperacion = result;
        cursorRecuperacion = result.bookmark.isNotEmpty &&
                _cursoresRecuperacion.add(result.bookmark)
            ? result.bookmark
            : null;
        await cargar();
      }
      return result;
    } finally {
      recuperando = false;
      _notificar();
    }
  }

  void _iniciar(String id) {
    if (_cerrado) throw ApiException('La sesión ya no está disponible.');
    if (!_ocupadas.add(id)) {
      throw ApiException('La operación ya está en curso.');
    }
    _notificar();
  }

  void _notificar() {
    if (!_cerrado) notifyListeners();
  }

  @override
  void dispose() {
    _cerrado = true;
    _lecturaOfertas++;
    _lecturaInversiones++;
    _intentos.clear();
    super.dispose();
  }
}

bool errorDefinitivo(Object error) =>
    error is ApiException &&
    error.status != null &&
    error.status! >= 400 &&
    error.status! < 500 &&
    error.status != 408 &&
    error.status != 429;

String mensajeFinanciero(Object error) => _mensaje(error);
String _mensaje(Object error) => error is ApiException
    ? error.message
    : 'No pudimos completar la operación. Intenta nuevamente.';
