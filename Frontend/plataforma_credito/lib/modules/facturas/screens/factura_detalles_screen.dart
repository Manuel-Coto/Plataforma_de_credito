import 'package:flutter/material.dart';
import '../../../models/factura.dart';

class FacturaDetalleScreen extends StatelessWidget{
  const FacturaDetalleScreen({super.key, required this.factura});

  final Factura factura;

  @override
  Widget build(BuildContext context){
    return Scaffold(
      appBar: AppBar(title: Text('Factura ${factura.numero}')),
      body: Center(
        child: Text('Monto: ${factura.montoTotalCentavos} centavod'),
      ),
    );
  }
}