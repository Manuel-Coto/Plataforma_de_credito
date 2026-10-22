/// Error devuelto por el backend o por la conexión.
/// [status] es null cuando no hubo respuesta del servidor.
class ApiException implements Exception {
  ApiException(this.message, [this.status]);

  final String message;
  final int? status;

  @override
  String toString() => message;
}