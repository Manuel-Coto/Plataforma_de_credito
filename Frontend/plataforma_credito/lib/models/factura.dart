import 'datos_dte.dart';
import 'estado_factura.dart';

class Factura {
  const Factura({
    required this.id,
    required this.empresaId,
    required this.numero,
    required this.dte,
    required this.moneda,
    required this.montoTotalCentavos,
    required this.montoFinanciadoCentavos,
    required this.fechaEmision,
    required this.fechaVencimiento,
    required this.estado,
  });

  final String id;
  final String empresaId;
  final String numero;
  final DatosDte dte;
  final String moneda;
  final int montoTotalCentavos; // siempre en centavos
  final int montoFinanciadoCentavos;
  final DateTime fechaEmision;
  final DateTime fechaVencimiento;
  final EstadoFactura estado;

  int get montoPendienteCentavos =>
      montoTotalCentavos - montoFinanciadoCentavos;

  factory Factura.fromJson(Map<String, dynamic> json) => Factura(
    id: json['id'] as String,
    empresaId: json['empresa_id'] as String,
    numero: json['numero'] as String,
    dte: DatosDte.fromJson(json['dte'] as Map<String, dynamic>),
    moneda: json['moneda'] as String,
    montoTotalCentavos: (json['monto_total_centavos'] as num).toInt(),
    montoFinanciadoCentavos:
    (json['monto_financiado_centavos'] as num?)?.toInt() ?? 0,
    fechaEmision: DateTime.parse(json['fecha_emision'] as String),
    fechaVencimiento: DateTime.parse(json['fecha_vencimiento'] as String),
    estado: EstadoFactura.desdeApi(json['estado'] as String),
  );
}
