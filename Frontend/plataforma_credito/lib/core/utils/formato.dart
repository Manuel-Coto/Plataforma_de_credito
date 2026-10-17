import 'package:intl/intl.dart';

/// Funciones para mostrar datos al usuario. Solo contiene métodos estáticos.
abstract final class Formato {
  /// 200000 centavos, 'USD'  ->  $2,000.00
  static String dinero(int centavos, String moneda) {
    final simbolo = moneda == 'USD' ? r'$' : '$moneda ';
    return NumberFormat.currency(symbol: simbolo, decimalDigits: 2)
        .format(centavos / 100);
  }

  /// DateTime -> 14/10/2026
  static String fecha(DateTime fecha) => DateFormat('dd/MM/yyyy').format(fecha);
}