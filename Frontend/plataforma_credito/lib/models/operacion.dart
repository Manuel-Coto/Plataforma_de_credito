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
        estado: (j['estado'] ?? 'pendiente').toString(),
      );
}

/// Campos supuestos; ajústalos al JSON real que devuelva GET /api/operaciones.
class Operacion {
  Operacion({
    required this.id,
    required this.facturaId,
    required this.montoCentavos,
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

  int get pagadoCentavos =>
      pagos.where((p) => p.estado == 'pagado').fold(0, (s, p) => s + p.montoCentavos);
  double get progreso => montoCentavos == 0 ? 0 : (pagadoCentavos / montoCentavos).clamp(0, 1).toDouble();

  factory Operacion.fromJson(Map<String, dynamic> j) => Operacion(
        id: (j['_id'] ?? j['id'] ?? '').toString(),
        facturaId: (j['factura_id'] ?? '').toString(),
        montoCentavos: (j['monto_centavos'] ?? 0) as int,
        moneda: (j['moneda'] ?? 'USD').toString(),
        estado: (j['estado'] ?? 'pendiente').toString(),
        vencimiento: DateTime.tryParse((j['fecha_vencimiento'] ?? '').toString()),
        pagos: ((j['pagos'] ?? []) as List)
            .map((e) => Pago.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}
