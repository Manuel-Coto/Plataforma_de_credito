import 'package:flutter/material.dart';

import '../../../core/utils/formato.dart';
import '../../../models/factura.dart';
import 'estado_factura_chip.dart';
import '../screens/factura_detalles_screen.dart';

class FacturaCard extends StatelessWidget {
  const FacturaCard({super.key, required this.factura});

  final Factura factura;

  @override
  Widget build(BuildContext context) {
    final texto = Theme.of(context).textTheme;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
        child: InkWell(
        onTap: () {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => FacturaDetalleScreen(factura: factura),
        ),
      );
    },
    child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Fila: número a la izquierda, estado a la derecha.
            // Expanded hace que el texto ocupe todo el espacio sobrante.
            Row(
              children: [
                Expanded(
                  child: Text('Factura ${factura.numero}',
                      style: texto.titleMedium),
                ),
                EstadoFacturaChip(estado: factura.estado),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              Formato.dinero(factura.montoTotalCentavos, factura.moneda),
              style: texto.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(
              'Emitida: ${Formato.fecha(factura.fechaEmision)}'
                  '  ·  Vence: ${Formato.fecha(factura.fechaVencimiento)}',
              style: texto.bodySmall,
            ),
            if (factura.montoFinanciadoCentavos > 0) ...[
              const SizedBox(height: 4),
              Text(
                'Financiado: ${Formato.dinero(factura.montoFinanciadoCentavos, factura.moneda)}',
                style: texto.bodySmall,
              ),
            ],
          ],
        ),
      ),
        ),
    );
  }
}