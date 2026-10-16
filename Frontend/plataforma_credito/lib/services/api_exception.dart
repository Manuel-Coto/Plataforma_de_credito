class ApiException implements Exception{
  const ApiException (this.statusCode, this.mensaje);
  final int statusCode;
  final String mensaje;

  @override
  String toString() => 'ApiException($statusCode): $mensaje';
}