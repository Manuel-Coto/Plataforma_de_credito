import 'dart:math';

import 'operacion.dart';

/// La API de ofertas/inversiones usa unidades monetarias; la interfaz conserva
/// centavos para validar y mostrar importes sin redondear entradas del usuario.
class Oferta {
  const Oferta(
      {required this.id,
      required this.facturaId,
      required this.empresaId,
      required this.creadoPor,
      required this.objetivoCentavos,
      required this.recaudadoCentavos,
      required this.moneda,
      required this.tasaAnual,
      required this.estado,
      required this.fechaCierre});
  final String id, facturaId, empresaId, creadoPor, moneda, estado;
  final int objetivoCentavos, recaudadoCentavos;
  final double tasaAnual;
  final DateTime fechaCierre;
  int get disponibleCentavos => objetivoCentavos - recaudadoCentavos;
  double get progreso =>
      (recaudadoCentavos / objetivoCentavos).clamp(0, 1).toDouble();
  bool get aceptaAportes =>
      estado == 'abierta' &&
      disponibleCentavos > 0 &&
      fechaCierre.isAfter(DateTime.now());

  factory Oferta.fromJson(Map<String, dynamic> json) {
    final objetivo = _dinero(json['monto_objetivo']);
    final recaudado = _dinero(json['monto_recaudado']);
    final tasa = json['tasa_rendimiento_anual'];
    final estado = textoFinanciero(json, 'estado');
    if (objetivo <= 0 ||
        recaudado > objetivo ||
        tasa is! num ||
        !tasa.isFinite ||
        tasa < 0 ||
        tasa > 100 ||
        !const [
          'abierta',
          'objetivo_alcanzado',
          'cerrada',
          'cancelada',
          'financiada'
        ].contains(estado)) {
      throw const FormatException('Oferta incompatible');
    }
    return Oferta(
        id: textoFinanciero(json, '_id'),
        facturaId: textoFinanciero(json, 'factura_id'),
        empresaId: textoFinanciero(json, 'empresa_id'),
        creadoPor: textoFinanciero(json, 'creado_por'),
        objetivoCentavos: objetivo,
        recaudadoCentavos: recaudado,
        moneda: textoFinanciero(json, 'moneda'),
        tasaAnual: tasa.toDouble(),
        estado: estado,
        fechaCierre: fechaFinanciera(json, 'fecha_cierre'));
  }
}

class Inversion {
  const Inversion(
      {required this.id,
      required this.ofertaId,
      required this.facturaId,
      required this.inversionistaId,
      required this.montoCentavos,
      required this.moneda,
      required this.estado,
      required this.fechaCreacion,
      this.fechaLiquidacion,
      this.rendimientoCentavos});
  final String id, ofertaId, facturaId, inversionistaId, moneda, estado;
  final int montoCentavos;
  final int? rendimientoCentavos;
  final DateTime fechaCreacion;
  final DateTime? fechaLiquidacion;
  bool get puedeConfirmarse =>
      const ['registrada', 'pago_pendiente'].contains(estado);

  factory Inversion.fromJson(Map<String, dynamic> json) {
    final monto = _dinero(json['monto']);
    final estado = textoFinanciero(json, 'estado');
    if (monto <= 0 ||
        !const [
          'registrada',
          'pago_pendiente',
          'confirmada',
          'liquidada',
          'reembolsada',
          'fallida'
        ].contains(estado)) {
      throw const FormatException('Inversión incompatible');
    }
    return Inversion(
        id: textoFinanciero(json, '_id'),
        ofertaId: textoFinanciero(json, 'oferta_id'),
        facturaId: textoFinanciero(json, 'factura_id'),
        inversionistaId: textoFinanciero(json, 'inversionista_id'),
        montoCentavos: monto,
        moneda: textoFinanciero(json, 'moneda'),
        estado: estado,
        fechaCreacion: fechaFinanciera(json, 'fecha_creacion'),
        fechaLiquidacion: json['fecha_liquidacion'] == null
            ? null
            : fechaFinanciera(json, 'fecha_liquidacion'),
        rendimientoCentavos: json['rendimiento_real'] == null
            ? null
            : _dinero(json['rendimiento_real']));
  }
}

class PaginaFinanciera<T> {
  const PaginaFinanciera(
      {required this.items, required this.bookmark, required this.limit});
  final List<T> items;
  final String bookmark;
  final int limit;
  factory PaginaFinanciera.desdeJson(
      dynamic value, String campo, T Function(Map<String, dynamic>) parsear) {
    final json = objetoFinanciero(value);
    final items = json[campo];
    final bookmark = json['bookmark'];
    final limit = json['limit'];
    if (items is! List ||
        bookmark is! String ||
        limit is! int ||
        limit < 1 ||
        limit > 100) {
      throw const FormatException('Página incompatible');
    }
    return PaginaFinanciera(
        items: List.unmodifiable(
            items.map((item) => parsear(objetoFinanciero(item)))),
        bookmark: bookmark,
        limit: limit);
  }
}

class ResultadoCredito {
  const ResultadoCredito(
      {required this.credito, required this.sincronizacionPendiente});
  final Operacion credito;
  final bool sincronizacionPendiente;
  factory ResultadoCredito.fromJson(dynamic value) {
    final json = objetoFinanciero(value);
    if (json['sincronizacion_pendiente'] is! bool) {
      throw const FormatException('Resultado incompatible');
    }
    return ResultadoCredito(
        credito: Operacion.fromJson(objetoFinanciero(json['credito'])),
        sincronizacionPendiente: json['sincronizacion_pendiente'] as bool);
  }
}

class ResultadoAporte {
  const ResultadoAporte(
      {required this.inversionId,
      required this.estado,
      required this.sincronizacionPendiente});
  final String inversionId, estado;
  final bool sincronizacionPendiente;
  factory ResultadoAporte.fromJson(dynamic value) {
    final json = objetoFinanciero(value);
    final estado = textoFinanciero(json, 'estado');
    if (json['simulado'] != true ||
        json['sincronizacion_pendiente'] is! bool ||
        !const ['confirmada', 'liquidada'].contains(estado)) {
      throw const FormatException('Confirmación incompatible');
    }
    return ResultadoAporte(
        inversionId: textoFinanciero(json, 'inversion_id'),
        estado: estado,
        sincronizacionPendiente: json['sincronizacion_pendiente'] as bool);
  }
}

class ResultadoRecuperacion {
  const ResultadoRecuperacion(
      {required this.recuperadas,
      required this.pendientes,
      required this.bookmark});
  final int recuperadas, pendientes;
  final String bookmark;
  factory ResultadoRecuperacion.fromJson(dynamic value) {
    final json = objetoFinanciero(value);
    if (json['recuperadas'] is! int ||
        (json['recuperadas'] as int) < 0 ||
        json['pendientes'] is! int ||
        (json['pendientes'] as int) < 0 ||
        json['bookmark'] is! String) {
      throw const FormatException('Recuperación incompatible');
    }
    return ResultadoRecuperacion(
        recuperadas: json['recuperadas'] as int,
        pendientes: json['pendientes'] as int,
        bookmark: json['bookmark'] as String);
  }
}

int? textoACentavos(String value) {
  final match =
      RegExp(r'^(\d{1,12})(?:[.,](\d{1,2}))?$').firstMatch(value.trim());
  if (match == null) return null;
  final cents =
      int.parse(match[1]!) * 100 + int.parse((match[2] ?? '').padRight(2, '0'));
  return cents > 0 ? cents : null;
}

String nuevaReferenciaFinanciera() {
  final random = Random.secure();
  return 'sim-${List.generate(16, (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0')).join()}';
}

Map<String, dynamic> objetoFinanciero(dynamic value) {
  if (value is! Map<String, dynamic>) {
    throw const FormatException('Objeto incompatible');
  }
  return value;
}

String textoFinanciero(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! String || value.trim().isEmpty) {
    throw FormatException('Campo $key incompatible');
  }
  return value;
}

DateTime fechaFinanciera(Map<String, dynamic> json, String key) {
  final value = textoFinanciero(json, key);
  final date = DateTime.tryParse(value);
  if (date == null || !RegExp(r'(Z|[+-]\d{2}:\d{2})$').hasMatch(value)) {
    throw FormatException('Fecha $key incompatible');
  }
  return date;
}

int _dinero(dynamic value) {
  if (value is! num || !value.isFinite || value < 0 || value > 9000000000000) {
    throw const FormatException('Importe incompatible');
  }
  final scaled = value * 100;
  final cents = scaled.round();
  if ((scaled - cents).abs() > .0001) {
    throw const FormatException('Importe con fracción de centavo');
  }
  return cents;
}
