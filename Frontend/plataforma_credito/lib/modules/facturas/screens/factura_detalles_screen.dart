import 'package:flutter/material.dart';
import '../../../models/factura.dart';
import '../../../widgets/fila_dato.dart';
import '../../../core/utils/formato.dart';
import '../../../widgets/seccion_card.dart';

class FacturaDetalleScreen extends StatelessWidget{
  const FacturaDetalleScreen({super.key, required this.factura});

  final Factura factura;

  @override
  Widget build(BuildContext context){
    return Scaffold(
      appBar: AppBar(title: Text('Factura ${factura.numero}')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SeccionCard(
            titulo: 'General',
            children: [
              FilaDato(etiqueta: 'Número', valor: factura.numero),
              FilaDato(etiqueta: 'Moneda', valor: factura.moneda),
              FilaDato(etiqueta: 'Estado', valor: factura.estado.etiqueta),
            ],
          ),
          SeccionCard(
            titulo: 'Fechas',
            children: [
              FilaDato(
                etiqueta: 'Emisión',
                valor: Formato.fecha(factura.fechaEmision),
              ),
              FilaDato(
                etiqueta: 'Vencimiento',
                valor: Formato.fecha(factura.fechaVencimiento),
              ),
            ],
          ),
          SeccionCard(
            titulo: 'Montos',
            children: [
              FilaDato(
                etiqueta: 'Total',
                valor: Formato.dinero(
                  factura.montoTotalCentavos,
                  factura.moneda,
                ),
              ),
              FilaDato(
                etiqueta: 'Financiado',
                valor: Formato.dinero(
                  factura.montoFinanciadoCentavos,
                  factura.moneda,
                ),
              ),
              FilaDato(
                etiqueta: 'Pendiente',
                valor: Formato.dinero(
                  factura.montoPendienteCentavos,
                  factura.moneda,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}