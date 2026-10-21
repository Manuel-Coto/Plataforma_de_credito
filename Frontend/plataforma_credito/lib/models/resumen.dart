/// Campos supuestos para GET /api/reportes/resumen.
class Resumen {
  Resumen({
    required this.totalOperaciones,
    required this.montoTotalCentavos,
    required this.empresasVerificadas,
    required this.facturasPendientes,
    required this.porEstado,
  });
  final int totalOperaciones;
  final int montoTotalCentavos;
  final int empresasVerificadas;
  final int facturasPendientes;
  final Map<String, int> porEstado;

  factory Resumen.fromJson(Map<String, dynamic> j) => Resumen(
        totalOperaciones: (j['total_operaciones'] ?? 0) as int,
        montoTotalCentavos: (j['monto_total_centavos'] ?? 0) as int,
        empresasVerificadas: (j['empresas_verificadas'] ?? 0) as int,
        facturasPendientes: (j['facturas_pendientes'] ?? 0) as int,
        porEstado: ((j['operaciones_por_estado'] ?? {}) as Map)
            .map((k, v) => MapEntry(k.toString(), (v as num).toInt())),
      );
}
