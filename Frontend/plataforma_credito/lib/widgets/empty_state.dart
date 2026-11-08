import 'package:flutter/material.dart';
import '../core/theme/credito_theme.dart';

class EmptyState extends StatelessWidget {
  const EmptyState(
      {super.key,
      required this.icon,
      required this.title,
      required this.message,
      this.action});
  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(
                padding: const EdgeInsets.all(22),
                decoration: BoxDecoration(
                    color: AppColors.softPrimary,
                    borderRadius: BorderRadius.circular(26)),
                child: Icon(icon, size: 36, color: AppColors.primary),
              ),
              const SizedBox(height: 22),
              Text(title,
                  style: Theme.of(context).textTheme.titleLarge,
                  textAlign: TextAlign.center),
              const SizedBox(height: 8),
              Text(message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.muted, height: 1.6)),
              if (action != null) ...[const SizedBox(height: 24), action!],
            ]),
          ),
        ),
      );
}
