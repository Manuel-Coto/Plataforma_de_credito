/// Pago registrado por el backend. Su existencia confirma el registro;
/// el contrato no incluye estados de pago pendientes o simulados adicionales.
class Pago {
  const Pago({
    required this.id,
    required this.referencia,
    required this.montoCentavos,
    required this.registradoPor,
    required this.fecha,
  });

  final String id;
  final String referencia;
  final int montoCentavos;
  final String registradoPor;
  final DateTime fecha;

  factory Pago.fromJson(Map<String, dynamic> json) {
    final monto = _entero(json, 'monto_centavos');
    if (monto <= 0) throw const FormatException('Monto de pago inválido');
    return Pago(
      id: _texto(json, 'id'),
      referencia: _texto(json, 'referencia'),
      montoCentavos: monto,
      registradoPor: _texto(json, 'registrado_por'),
      fecha: _instante(json, 'fecha'),
    );
  }
}

/// Vista pública de GET /api/creditos y GET /api/creditos/{id}.
/// Los totales vienen del servidor, incluso cuando no se comparte el historial.
class Operacion {
  const Operacion({
    required this.id,
    required this.facturaId,
    required this.moneda,
    required this.capitalCentavos,
    required this.interesCentavos,
    required this.totalCentavos,
    required this.pagadoCentavos,
    required this.saldoCentavos,
    required this.estado,
    required this.vencido,
    required this.diasMora,
    required this.vencimiento,
    this.pagos,
  });

  final String id;
  final String facturaId;
  final String moneda;
  final int capitalCentavos;
  final int interesCentavos;
  final int totalCentavos;
  final int pagadoCentavos;
  final int saldoCentavos;
  final String estado;
  final bool vencido;
  final int diasMora;
  final DateTime vencimiento;

  /// null: el backend no comparte el historial con este perfil.
  /// Lista vacía: el historial sí se comparte y aún no contiene pagos.
  final List<Pago>? pagos;

  int get montoCentavos => totalCentavos;
  bool get historialCompartido => pagos != null;
  String get estadoVisible => vencido ? 'vencido' : estado;
  double get progreso =>
      (pagadoCentavos / totalCentavos).clamp(0, 1).toDouble();

  factory Operacion.fromJson(Map<String, dynamic> json) {
    final capital = _entero(json, 'capital_centavos');
    final interes = _entero(json, 'interes_centavos');
    final total = _entero(json, 'total_centavos');
    final pagado = _entero(json, 'pagado_centavos');
    final saldo = _entero(json, 'saldo_centavos');
    final estado = _texto(json, 'estado');
    final diasMora = _entero(json, 'dias_mora');
    final vencido = json['vencido'];
    if (capital <= 0 ||
        interes < 0 ||
        total <= 0 ||
        pagado < 0 ||
        saldo < 0 ||
        capital + interes != total ||
        pagado + saldo != total ||
        !const ['activo', 'pagado'].contains(estado) ||
        vencido is! bool ||
        diasMora < 0 ||
        vencido != (diasMora > 0) ||
        (estado == 'pagado' && (saldo != 0 || vencido)) ||
        (estado == 'activo' && saldo == 0)) {
      throw const FormatException('Importes o estado del crédito inválidos');
    }

    List<Pago>? pagos;
    if (json.containsKey('pagos')) {
      final historial = json['pagos'];
      if (historial is! List) {
        throw const FormatException('Historial de pagos inválido');
      }
      pagos = List<Pago>.unmodifiable(historial.map((item) {
        if (item is! Map<String, dynamic>) {
          throw const FormatException('Pago inválido');
        }
        return Pago.fromJson(item);
      }));
    }

    return Operacion(
      id: _texto(json, 'id'),
      facturaId: _texto(json, 'factura_id'),
      moneda: _texto(json, 'moneda'),
      capitalCentavos: capital,
      interesCentavos: interes,
      totalCentavos: total,
      pagadoCentavos: pagado,
      saldoCentavos: saldo,
      estado: estado,
      vencido: vencido,
      diasMora: diasMora,
      vencimiento: _calendario(_texto(json, 'fecha_vencimiento')),
      pagos: pagos,
    );
  }
}

String _texto(Map<String, dynamic> json, String campo) {
  final value = json[campo];
  if (value is! String || value.trim().isEmpty) {
    throw FormatException('Campo $campo inválido');
  }
  return value;
}

int _entero(Map<String, dynamic> json, String campo) {
  final value = json[campo];
  if (value is! int) throw FormatException('Campo $campo inválido');
  return value;
}

DateTime _calendario(String value) {
  final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(value);
  if (match == null) {
    throw const FormatException('Fecha de vencimiento inválida');
  }
  final year = int.parse(match[1]!);
  final month = int.parse(match[2]!);
  final day = int.parse(match[3]!);
  final date = DateTime.utc(year, month, day);
  if (date.year != year || date.month != month || date.day != day) {
    throw const FormatException('Fecha de vencimiento inválida');
  }
  return date;
}

DateTime _instante(Map<String, dynamic> json, String campo) {
  final value = _texto(json, campo);
  final format = RegExp(
      r'^\d{4}-\d{2}-\d{2}T(?:[01]\d|2[0-3]):[0-5]\d:[0-5]\d(?:\.\d+)?(?:Z|[+-](?:[01]\d|2[0-3]):[0-5]\d)$');
  if (!format.hasMatch(value)) throw FormatException('Campo $campo inválido');
  _calendario(value.substring(0, 10));
  final date = DateTime.tryParse(value);
  if (date == null) throw FormatException('Campo $campo inválido');
  return date;
}
