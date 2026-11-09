/// Respuesta real de GET /api/administracion/resumen.
class Resumen {
  Resumen._({required this.generadoEn, required this.reportes});

  static const modulos = {
    'usuarios',
    'empresas',
    'facturas',
    'ofertas',
    'inversiones',
    'creditos',
    'pagos',
    'auditoria',
  };

  final DateTime generadoEn;
  final Map<String, ReporteResumen> reportes;

  int get totalCreditos => reportes['creditos']!.total;

  /// Importes en centavos; cada entrada conserva su propia moneda.
  Map<String, int> get montosCreditosPorMoneda =>
      Map.unmodifiable(reportes['creditos']!.montosPorMoneda.map(
          (moneda, montos) => MapEntry(moneda, montos['total_centavos']!)));

  int get empresasVerificadas => reportes['empresas']!.porEstado['activa'] ?? 0;

  int get facturasPendientes =>
      reportes['facturas']!.porEstado['pendiente_verificacion'] ?? 0;

  Map<String, int> get porEstado => reportes['creditos']!.porEstado;

  factory Resumen.fromJson(Map<String, dynamic> json) {
    final generadoEn = _timestamp(json['generado_en']);
    final source = json['reportes'];
    if (source is! List || source.length != modulos.length) {
      throw const FormatException('El resumen debe incluir los ocho módulos.');
    }
    final reportes = <String, ReporteResumen>{};
    for (final entry in source) {
      final reporte = ReporteResumen.fromJson(_object(entry, 'reporte'));
      if (!modulos.contains(reporte.modulo) ||
          reportes.containsKey(reporte.modulo)) {
        throw const FormatException(
            'Módulo de reporte desconocido o repetido.');
      }
      reportes[reporte.modulo] = reporte;
    }
    final creditos = reportes['creditos']!;
    if (creditos.total > 0 && creditos.montosPorMoneda.isEmpty) {
      throw const FormatException('Faltan los importes de los créditos.');
    }
    for (final montos in creditos.montosPorMoneda.values) {
      if (!montos.containsKey('total_centavos')) {
        throw const FormatException(
            'Falta el total en centavos de una moneda.');
      }
    }
    return Resumen._(
        generadoEn: generadoEn, reportes: Map.unmodifiable(reportes));
  }
}

class ReporteResumen {
  ReporteResumen._({
    required this.modulo,
    required this.total,
    required this.porEstado,
    required this.porRol,
    required this.montosPorMoneda,
  });

  final String modulo;
  final int total;
  final Map<String, int> porEstado;
  final Map<String, int> porRol;
  final Map<String, Map<String, int>> montosPorMoneda;

  factory ReporteResumen.fromJson(Map<String, dynamic> json) {
    final modulo = json['modulo'];
    if (modulo is! String || !Resumen.modulos.contains(modulo)) {
      throw const FormatException('Módulo de reporte inválido.');
    }
    final source = _object(json['montos_por_moneda'], 'montos_por_moneda');
    final montos = <String, Map<String, int>>{};
    for (final entry in source.entries) {
      if (entry.key.trim().isEmpty) {
        throw const FormatException('Código de moneda vacío.');
      }
      montos[entry.key] = _counts(entry.value, 'importes por moneda');
    }
    return ReporteResumen._(
      modulo: modulo,
      total: _nonNegativeInteger(json['total'], 'total'),
      porEstado: _counts(json['por_estado'], 'por_estado'),
      porRol: _counts(json['por_rol'], 'por_rol'),
      montosPorMoneda: Map.unmodifiable(montos),
    );
  }
}

Map<String, dynamic> _object(Object? value, String field) {
  if (value is! Map || value.keys.any((key) => key is! String)) {
    throw FormatException('El campo $field debe ser un objeto.');
  }
  return Map<String, dynamic>.from(value);
}

int _nonNegativeInteger(Object? value, String field) {
  if (value is! int || value < 0) {
    throw FormatException('El campo $field debe ser un entero no negativo.');
  }
  return value;
}

Map<String, int> _counts(Object? value, String field) {
  final source = _object(value, field);
  final result = <String, int>{};
  for (final entry in source.entries) {
    if (entry.key.trim().isEmpty) {
      throw FormatException('El campo $field contiene una clave vacía.');
    }
    result[entry.key] = _nonNegativeInteger(entry.value, field);
  }
  return Map.unmodifiable(result);
}

DateTime _timestamp(Object? value) {
  if (value is! String) {
    throw const FormatException('Falta la fecha de generación del resumen.');
  }
  final parts = RegExp(
    r'^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})(?:\.\d{1,9})?(?:Z|[+-]\d{2}:\d{2})$',
  ).firstMatch(value);
  final parsed = DateTime.tryParse(value);
  if (parts == null || parsed == null) {
    throw const FormatException('Fecha de generación inválida.');
  }
  final year = int.parse(parts[1]!);
  final month = int.parse(parts[2]!);
  final day = int.parse(parts[3]!);
  if (month < 1 ||
      month > 12 ||
      day < 1 ||
      day > DateTime.utc(year, month + 1, 0).day ||
      int.parse(parts[4]!) > 23 ||
      int.parse(parts[5]!) > 59 ||
      int.parse(parts[6]!) > 59) {
    throw const FormatException('Fecha de generación inválida.');
  }
  return parsed;
}
