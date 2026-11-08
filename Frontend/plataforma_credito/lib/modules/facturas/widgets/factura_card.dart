import 'package:flutter/material.dart';
import '../../../core/theme/credito_theme.dart';
import '../../../core/utils/formato.dart';
import '../../../models/factura.dart';
import '../screens/factura_detalles_screen.dart';
import 'estado_factura_chip.dart';

class FacturaCard extends StatelessWidget {
  const FacturaCard({super.key, required this.factura});
  final Factura factura;

  @override
  Widget build(BuildContext context) {
    final texto = Theme.of(context).textTheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
                builder: (_) => FacturaDetalleScreen(factura: factura))),
        child: Padding(
          padding: const EdgeInsets.all(22),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                  padding: const EdgeInsets.all(11),
                  decoration: BoxDecoration(
                      color: AppColors.softPrimary,
                      borderRadius: BorderRadius.circular(13)),
                  child: const Icon(Icons.receipt_long_outlined,
                      size: 22, color: AppColors.primary)),
              const SizedBox(width: 14),
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text('Factura ${factura.numero}', style: texto.titleMedium),
                    const SizedBox(height: 6),
                    Text(
                        Formato.dinero(
                            factura.montoTotalCentavos, factura.moneda),
                        style: texto.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.w700)),
                  ])),
              const Icon(Icons.arrow_outward_rounded,
                  color: AppColors.muted, size: 20),
            ]),
            const SizedBox(height: 18),
            const Divider(height: 1),
            const SizedBox(height: 15),
            Wrap(
                spacing: 20,
                runSpacing: 12,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  _dato(Icons.calendar_today_outlined,
                      'Emitida ${Formato.fecha(factura.fechaEmision)}'),
                  _dato(Icons.event_outlined,
                      'Vence ${Formato.fecha(factura.fechaVencimiento)}'),
                  EstadoFacturaChip(estado: factura.estado),
                ]),
            if (factura.montoFinanciadoCentavos > 0) ...[
              const SizedBox(height: 13),
              Text(
                  'Financiado: ${Formato.dinero(factura.montoFinanciadoCentavos, factura.moneda)}',
                  style: texto.bodySmall?.copyWith(color: AppColors.primary)),
            ],
          ]),
        ),
      ),
    );
  }

  Widget _dato(IconData icon, String label) =>
      Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 15, color: AppColors.muted),
        const SizedBox(width: 7),
        Flexible(
            child: Text(label,
                style: const TextStyle(fontSize: 12, color: AppColors.muted))),
      ]);
}
