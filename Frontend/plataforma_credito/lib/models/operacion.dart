class Pago {
  Pago({required this.id, required this.montoCentavos, required this.fecha, required this.estado});
  final String id;
  final int montoCentavos;
  final DateTime? fecha;
  final String estado;

  factory Pago.fromJson(Map<String, dynamic> j) => Pago(
        id: (j['_id'] ?? j['id'] ?? '').toString(),
        montoCentavos: (j['monto_centavos'] ?? 0) as int,
        fecha: DateTime.tryParse((j['fecha'] ?? '').toString()),
        estado: (j['estado'] ?? 'pagado').toString(),
      );
}

class Operacion {
  Operacion({
    required this.id,
    required this.facturaId,
    required this.montoCentavos,
    required this.pagadoCentavos,
    required this.historialVisible,
    required this.moneda,
    required this.estado,
    required this.vencimiento,
    required this.pagos,
  });
  final String id;
  final String facturaId;
  final int montoCentavos;
  final String moneda;
  final String estado;
  final DateTime? vencimiento;
  final List<Pago> pagos;

  final int pagadoCentavos;
  final bool historialVisible;
  double get progreso => montoCentavos == 0 ? 0 : (pagadoCentavos / montoCentavos).clamp(0, 1).toDouble();

  factory Operacion.fromJson(Map<String, dynamic> j) => Operacion(
        id: (j['_id'] ?? j['id'] ?? '').toString(),
        facturaId: (j['factura_id'] ?? '').toString(),
        montoCentavos: j['total_centavos'] as int,
        pagadoCentavos: j['pagado_centavos'] as int,
        historialVisible: j['pagos'] != null,
        moneda: (j['moneda'] ?? 'USD').toString(),
        estado: (j['estado'] ?? 'pendiente').toString(),
        vencimiento: DateTime.tryParse((j['fecha_vencimiento'] ?? '').toString()),
        pagos: ((j['pagos'] ?? []) as List)
            .map((e) => Pago.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}
