import 'package:intl/intl.dart';

String money(int centavos, [String moneda = 'USD']) =>
    NumberFormat.currency(symbol: moneda == 'USD' ? r'$' : '$moneda ', decimalDigits: 2)
        .format(centavos / 100);

String fecha(DateTime? d) => d == null ? '—' : DateFormat('dd/MM/yyyy').format(d);

String estadoLegible(String e) {
  const m = {
    'pendiente': 'Pendiente',
    'activa': 'Activa',
    'pagada': 'Pagada',
    'pagado': 'Pagado',
    'vencida': 'Vencida',
    'liquidada': 'Liquidada',
  };
  return m[e] ?? e.replaceAll('_', ' ');
}
