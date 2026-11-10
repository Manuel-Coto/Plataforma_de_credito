/// Error devuelto por el backend o por la conexión.
/// [status] es null cuando no hubo respuesta del servidor.
class ApiException implements Exception {
  ApiException(this.message, [this.status, this.retryAfter]);

  final String message;
  final int? status;
  final Duration? retryAfter;

  @override
  String toString() => message;
}
