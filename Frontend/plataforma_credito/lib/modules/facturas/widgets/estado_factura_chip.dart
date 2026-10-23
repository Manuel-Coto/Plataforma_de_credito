import 'package:flutter/material.dart';

import '../../../models/estado_factura.dart';

class EstadoFacturaChip extends StatelessWidget {
  const EstadoFacturaChip({super.key, required this.estado});

  final EstadoFactura estado;

  // switch como expresión: devuelve un valor. Dart obliga a cubrir TODOS los
  // estados; si mañana se agrega uno nuevo al enum, esto no compila hasta
  // que decidas su color.
  Color get _color => switch (estado) {
    EstadoFactura.pendienteVerificacion => Colors.orange,
    EstadoFactura.verificada => Colors.blue,
    EstadoFactura.disponible => Colors.teal,
    EstadoFactura.parcialmenteFinanciada => Colors.indigo,
    EstadoFactura.financiada => Colors.green,
    EstadoFactura.pagada => Colors.green.shade800,
    EstadoFactura.vencida => Colors.red,
    EstadoFactura.rechazada => Colors.grey,
  };

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: _color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _color),
      ),
      child: Text(
        estado.etiqueta,
        style: TextStyle(
          color: _color,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}