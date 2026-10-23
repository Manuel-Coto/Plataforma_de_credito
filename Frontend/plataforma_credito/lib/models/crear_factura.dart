/// Datos del formulario de registro. El backend rechaza campos extra,
/// así que aquí van exactamente estos siete.
class CrearFactura {
  const CrearFactura({
    required this.empresaId,
    required this.numero,
    required this.codigoGeneracion,
    required this.moneda,
    required this.montoTotalCentavos,
    required this.fechaEmision,
    required this.fechaVencimiento,
  });

  final String empresaId;
  final String numero;
  final String codigoGeneracion;
  final String moneda;
  final int montoTotalCentavos;
  final DateTime fechaEmision;
  final DateTime fechaVencimiento;

  // Rust espera "2026-10-14", sin hora.
  static String _fecha(DateTime f) => f.toIso8601String().split('T').first;

  Map<String, dynamic> toJson() => {
    'empresa_id': empresaId,
    'numero': numero,
    'codigo_generacion': codigoGeneracion,
    'moneda': moneda,
    'monto_total_centavos': montoTotalCentavos,
    'fecha_emision': _fecha(fechaEmision),
    'fecha_vencimiento': _fecha(fechaVencimiento),
  };
}