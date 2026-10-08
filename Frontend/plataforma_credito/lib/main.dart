import 'package:flutter/material.dart';

void main() => runApp(const PlataformaCreditoApp());

class PlataformaCreditoApp extends StatelessWidget {
  const PlataformaCreditoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Plataforma de Crédito Colaborativo',
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.blue),
      home: Scaffold(
        appBar: AppBar(title: const Text('Plataforma de Crédito Colaborativo')),
        body: const Center(child: Text('Estructura inicial: 6 módulos')),
      ),
    );
  }
}
