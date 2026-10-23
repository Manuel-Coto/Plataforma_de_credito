import 'package:flutter/foundation.dart';

import '../../../core/estado_carga.dart';
import '../../../models/estado_factura.dart';
import '../../../models/factura.dart';
import '../../../services/api_exception.dart';
import '../../../services/factura_service.dart';

// "extends ChangeNotifier": hereda la capacidad de avisar a quien escuche
// (las pantallas) con notifyListeners().
class FacturasProvider extends ChangeNotifier {
  // El servicio llega desde fuera: el provider no sabe de URLs ni tokens.
  FacturasProvider(this._servicio);

  final FacturaService _servicio;

  // Estado interno. Con "_" es privado: solo este archivo puede cambiarlo.
  EstadoCarga _estadoCarga = EstadoCarga.inicial;
  List<Factura> _facturas = const [];
  String? _mensajeError;
  EstadoFactura? _filtro;

  // La pantalla solo puede LEER el estado, nunca modificarlo directamente.
  EstadoCarga get estadoCarga => _estadoCarga;
  List<Factura> get facturas => _facturas;
  String? get mensajeError => _mensajeError;
  EstadoFactura? get filtro => _filtro;

  /// Pide las facturas al backend, respetando el filtro actual.
  Future<void> cargar() async {
    _estadoCarga = EstadoCarga.cargando;
    _mensajeError = null;
    notifyListeners(); // la pantalla muestra el indicador de carga

    try {
      final pagina = await _servicio.listar(estado: _filtro, limit: 50);
      _facturas = pagina.facturas;
      _estadoCarga = EstadoCarga.listo;
    } on ApiException catch (e) {
      // Error conocido: lo devolvió el backend o no hubo conexión.
      _mensajeError = e.message;
      _estadoCarga = EstadoCarga.error;
    } catch (_) {
      // Cualquier otra cosa (por ejemplo, una respuesta con formato
      // inesperado). Sin esto, la pantalla se quedaría cargando para siempre.
      _mensajeError = 'Respuesta inesperada del servidor';
      _estadoCarga = EstadoCarga.error;
    }

    notifyListeners(); // la pantalla muestra la lista o el error
  }

  /// Cambia el filtro por estado (null = todas) y recarga.
  Future<void> filtrarPor(EstadoFactura? estado) async {
    _filtro = estado;
    await cargar();
  }
}