import 'package:flutter/material.dart';
import '../../../models/estado_factura.dart';

class EstadoFacturaChip extends StatelessWidget {
  const EstadoFacturaChip({super.key, required this.estado});
  final EstadoFactura estado;

  (Color foreground, Color background) get _palette => switch (estado) {
        EstadoFactura.pendienteVerificacion => (
            const Color(0xFF7D510C),
            const Color(0xFFFFF3D8)
          ),
        EstadoFactura.verificada => (
            const Color(0xFF315C86),
            const Color(0xFFEDF3FA)
          ),
        EstadoFactura.disponible => (
            const Color(0xFF2B6449),
            const Color(0xFFEAF3ED)
          ),
        EstadoFactura.parcialmenteFinanciada => (
            const Color(0xFF4B5486),
            const Color(0xFFEFF0FA)
          ),
        EstadoFactura.financiada => (
            const Color(0xFF2B6449),
            const Color(0xFFEAF3ED)
          ),
        EstadoFactura.pagada => (
            const Color(0xFF214E41),
            const Color(0xFFE1EEE5)
          ),
        EstadoFactura.vencida => (
            const Color(0xFF9C3D3B),
            const Color(0xFFFCECE9)
          ),
        EstadoFactura.rechazada => (
            const Color(0xFF73514F),
            const Color(0xFFF4ECEA)
          ),
      };

  @override
  Widget build(BuildContext context) {
    final (foreground, background) = _palette;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        estado.etiqueta,
        softWrap: true,
        style: TextStyle(
          color: foreground,
          fontSize: 12,
          height: 1.35,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
