class DatosDte {
  const DatosDte({
    required this.codigoGeneracion,
    this.selloRecepcion,
    required this.verificado,
    this.fechaVerificacion,
  });

  final String codigoGeneracion;
  final String? selloRecepcion;
  final bool verificado;
  final DateTime? fechaVerificacion;

  factory DatosDte.fromJson(Map<String, dynamic> json) => DatosDte(
    codigoGeneracion: json['codigo_generacion'] as String,
    selloRecepcion: json['sello_recepcion'] as String?,
    verificado: json['verificado'] as bool? ?? false,
    fechaVerificacion: json['fecha_verificacion'] == null
        ? null
        : DateTime.parse(json['fecha_verificacion'] as String),
  );
}