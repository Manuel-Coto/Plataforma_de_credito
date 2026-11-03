class Resumen {
  Resumen({
    required this.totalCreditos,
    required this.totalesPorMoneda,
    required this.empresasActivas,
    required this.facturasPendientes,
    required this.porEstado,
  });

  final int totalCreditos;
  final Map<String, int> totalesPorMoneda;
  final int empresasActivas;
  final int facturasPendientes;
  final Map<String, int> porEstado;

  factory Resumen.fromJson(Map<String, dynamic> json) {
    final reportes = {
      for (final reporte in (json['reportes'] as List).cast<Map<String, dynamic>>())
        reporte['modulo'] as String: reporte,
    };
    final creditos = reportes['creditos']!;
    final montos = creditos['montos_por_moneda'] as Map<String, dynamic>;
    return Resumen(
      totalCreditos: creditos['total'] as int,
      totalesPorMoneda: montos.map(
        (moneda, valores) => MapEntry(moneda, valores['total_centavos'] as int),
      ),
      empresasActivas: reportes['empresas']!['por_estado']['activa'] ?? 0,
      facturasPendientes: reportes['facturas']!['por_estado']['pendiente_verificacion'] ?? 0,
      porEstado: Map<String, int>.from(creditos['por_estado']),
    );
  }
}
