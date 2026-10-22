enum EstadoFactura {
  pendienteVerificacion('pendiente_verificacion', 'Pendiente de verificación'),
  verificada('verificada', 'Verificada'),
  disponible('disponible', 'Disponible'),
  parcialmenteFinanciada('parcialmente_financiada', 'Parcialmente financiada'),
  financiada('financiada', 'Financiada'),
  pagada('pagada', 'Pagada'),
  vencida('vencida', 'Vencida'),
  rechazada('rechazada', 'Rechazada');

  const EstadoFactura(this.valorApi, this.etiqueta);

  final String valorApi;
  final String etiqueta;

  static EstadoFactura desdeApi(String valor) =>
      EstadoFactura.values.firstWhere(
            (e) => e.valorApi == valor,
        orElse: () =>
        throw FormatException('Estado de factura desconocido: $valor'),
      );
}