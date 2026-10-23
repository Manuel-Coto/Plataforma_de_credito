import 'package:flutter/material.dart';

class FilaDato extends StatelessWidget {
  const FilaDato({super.key, required this.etiqueta, required this.valor});

  final String etiqueta;
  final String valor;

  @override
  Widget build(BuildContext context) {
    final texto = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(etiqueta, style: texto.bodyMedium),
          Flexible(
            child: Text(
              valor,
              textAlign: TextAlign.right,
              style: texto.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}