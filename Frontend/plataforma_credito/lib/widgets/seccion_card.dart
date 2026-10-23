import 'package:flutter/material.dart';

class SeccionCard extends StatelessWidget {
  const SeccionCard({super.key, required this.titulo, required this.children});

  final String titulo;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(titulo, style: Theme.of(context).textTheme.titleMedium),
            const Divider(height: 24),
            ...children,
          ],
        ),
      ),
    );
  }
}