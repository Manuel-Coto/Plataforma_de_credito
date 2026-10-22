import 'factura.dart';

class FacturaPagina {
  const FacturaPagina({
    required this.facturas,
    required this.bookmark,
    required this.limit,
  });

  final List<Factura> facturas;
  final String bookmark;
  final int limit;

  factory FacturaPagina.fromJson(Map<String, dynamic> json) => FacturaPagina(
    // Convierte cada elemento de la lista JSON en un objeto Factura.
    facturas: (json['facturas'] as List<dynamic>)
        .map((f) => Factura.fromJson(f as Map<String, dynamic>))
        .toList(),
    bookmark: json['bookmark'] as String,
    limit: (json['limit'] as num).toInt(),
  );
}