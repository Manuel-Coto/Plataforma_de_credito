import 'package:flutter/material.dart';
import '../core/theme/credito_theme.dart';

class PageHeader extends StatelessWidget {
  const PageHeader({
    super.key,
    required this.title,
    required this.subtitle,
    this.eyebrow,
    this.action,
  });

  final String title;
  final String subtitle;
  final String? eyebrow;
  final Widget? action;

  @override
  Widget build(BuildContext context) =>
      LayoutBuilder(builder: (context, constraints) {
        final compact = constraints.maxWidth < 660;
        final heading = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (eyebrow != null) ...[
              Text(eyebrow!.toUpperCase(),
                  style: const TextStyle(
                    color: AppColors.primary,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.5,
                  )),
              const SizedBox(height: 10),
            ],
            Text(title,
                style: Theme.of(context)
                    .textTheme
                    .headlineMedium
                    ?.copyWith(fontSize: compact ? 26 : 30)),
            const SizedBox(height: 8),
            Text(subtitle,
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: AppColors.muted)),
          ],
        );
        if (compact) {
          return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                heading,
                if (action != null) ...[const SizedBox(height: 18), action!],
              ]);
        }
        return Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
          Expanded(child: heading),
          if (action != null) ...[const SizedBox(width: 24), action!],
        ]);
      });
}
