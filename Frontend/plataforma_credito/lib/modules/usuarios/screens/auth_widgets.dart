import 'package:flutter/material.dart';

import '../../../core/theme/credito_theme.dart';

class AuthBrand extends StatelessWidget {
  const AuthBrand({super.key, this.light = false});

  final bool light;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: light ? AppColors.accent : AppColors.primary,
              borderRadius: BorderRadius.circular(13),
            ),
            child: Icon(
              Icons.spa_outlined,
              color: light ? AppColors.primary : AppColors.onPrimary,
              size: 24,
            ),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Crédito',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: light ? AppColors.onPrimary : AppColors.ink,
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -.8,
                    height: 1.1,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  'COLABORATIVO',
                  style: TextStyle(
                    color: light ? AppColors.accent : AppColors.muted,
                    fontSize: 9,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      );
}

class AuthEditorialPanel extends StatelessWidget {
  const AuthEditorialPanel({super.key, required this.registro});

  final bool registro;

  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: Container(
          color: AppColors.primary,
          child: LayoutBuilder(
            builder: (context, constraints) => SingleChildScrollView(
              padding: const EdgeInsets.all(40),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: (constraints.maxHeight - 80)
                      .clamp(0.0, 1200.0)
                      .toDouble(),
                ),
                child: IntrinsicHeight(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const AuthBrand(light: true),
                      const SizedBox(height: 56),
                      const Text(
                        'CONEXIONES QUE IMPULSAN',
                        style: TextStyle(
                          color: AppColors.accent,
                          fontSize: 10,
                          letterSpacing: 2,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 18),
                      Text(
                        registro
                            ? 'Grandes ideas.\nNuevas\nposibilidades.'
                            : 'Crecer es\nmejor cuando\nlo hacemos juntos.',
                        style: const TextStyle(
                          color: AppColors.onPrimary,
                          fontSize: 43,
                          height: 1.12,
                          fontWeight: FontWeight.w500,
                          letterSpacing: -1.6,
                        ),
                      ),
                      const SizedBox(height: 20),
                      const Text(
                        'Conectamos empresas y personas para\nconstruir el siguiente capítulo de su historia.',
                        style: TextStyle(
                          color: AppColors.onPrimaryMuted,
                          fontSize: 14,
                          height: 1.7,
                        ),
                      ),
                      const SizedBox(height: 26),
                      Expanded(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(minHeight: 160),
                          child: const _GrowthIllustration(),
                        ),
                      ),
                      const SizedBox(height: 24),
                      const Divider(color: AppColors.primaryOutline),
                      const SizedBox(height: 16),
                      const Row(
                        children: [
                          Icon(
                            Icons.hub_outlined,
                            size: 20,
                            color: AppColors.accent,
                          ),
                          SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Más cerca de lo que quieres lograr.',
                              style: TextStyle(
                                color: AppColors.onPrimaryMuted,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
}

class _GrowthIllustration extends StatelessWidget {
  const _GrowthIllustration();

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
        child: SizedBox(
          width: double.infinity,
          height: 190,
          child: CustomPaint(painter: _GrowthPainter()),
        ),
      );
}

class _GrowthPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final width = size.width;
    final height = size.height;
    final unit = width / 4.6;
    final baseline = height * .89;
    final paint = Paint()..color = AppColors.primaryRaised;
    for (var i = 0; i < 4; i++) {
      final columnHeight = height * (.25 + i * .17);
      paint.color = [
        AppColors.artLow,
        AppColors.artMedium,
        AppColors.artHigh,
        AppColors.accent,
      ][i];
      final rect = RRect.fromRectAndCorners(
        Rect.fromLTWH(
            unit * i * 1.15, baseline - columnHeight, unit, columnHeight),
        topLeft: Radius.circular(unit / 2),
        topRight: Radius.circular(unit / 2),
      );
      canvas.drawRRect(rect, paint);
    }
    final line = Paint()
      ..color = AppColors.primaryOutline
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    canvas.drawLine(Offset(0, baseline), Offset(width, baseline), line);
    final center = Offset(width * .72, height * .2);
    canvas.drawCircle(
      center,
      18,
      Paint()..color = AppColors.softPrimary,
    );
    final arrow = Paint()
      ..color = AppColors.primary
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 1.8;
    canvas.drawLine(
        center + const Offset(-5, 5), center + const Offset(5, -5), arrow);
    canvas.drawLine(
        center + const Offset(-3, -5), center + const Offset(5, -5), arrow);
    canvas.drawLine(
        center + const Offset(5, -5), center + const Offset(5, 3), arrow);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

InputDecoration authInputDecoration(
  String label,
  IconData icon, {
  String? hint,
  Widget? suffixIcon,
}) =>
    InputDecoration(
      labelText: label,
      hintText: hint,
      prefixIcon: Icon(icon, size: 19, color: AppColors.muted),
      suffixIcon: suffixIcon,
      filled: true,
      fillColor: AppColors.surface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
      labelStyle: const TextStyle(color: AppColors.muted, fontSize: 14),
      hintStyle: const TextStyle(color: AppColors.muted, fontSize: 14),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
      ),
      errorMaxLines: 3,
    );
