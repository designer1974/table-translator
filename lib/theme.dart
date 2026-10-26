import 'package:flutter/material.dart';

/// Palette "bianco latte lucido": alto contrasto, leggibile anche alla luce.
class C {
  static const bgTop = Color(0xFFFFFDF8);
  static const bgBottom = Color(0xFFF3EEE3);
  static const card = Colors.white;
  static const border = Color(0xFFEAE3D4);
  static const ink = Color(0xFF1C1A16);
  static const muted = Color(0xFF7C7468);
  static const waiter = Color(0xFF1F3A5F); // blu notte
  static const tourist = Color(0xFFB4532F); // terracotta
  static const listening = Color(0xFFD7263D);
}

ThemeData buildTheme() {
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: C.waiter,
      brightness: Brightness.light,
    ).copyWith(surface: C.bgTop, onSurface: C.ink, primary: C.waiter),
    scaffoldBackgroundColor: C.bgTop,
  );
  return base.copyWith(
    appBarTheme: const AppBarTheme(
      backgroundColor: C.bgTop,
      foregroundColor: C.ink,
      elevation: 0,
      scrolledUnderElevation: 0,
    ),
    textTheme: base.textTheme.apply(bodyColor: C.ink, displayColor: C.ink),
  );
}

/// Sfondo latte con leggero gradiente.
class MilkBackground extends StatelessWidget {
  final Widget child;
  const MilkBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [C.bgTop, C.bgBottom],
          ),
        ),
        child: child,
      );
}

/// Carta bianca lucida: ombra morbida + riflesso in alto.
class GlossCard extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  final double radius;
  const GlossCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.radius = 28,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: C.card,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: C.border),
        boxShadow: const [
          BoxShadow(
              color: Color(0x1F6B5A3A), blurRadius: 24, offset: Offset(0, 8)),
          BoxShadow(
              color: Color(0x0F6B5A3A), blurRadius: 4, offset: Offset(0, 1)),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: Stack(
          children: [
            // riflesso lucido
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              height: 60,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        const Color(0xFFF7F2E8).withValues(alpha: 0.9),
                        Colors.white.withValues(alpha: 0),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Padding(padding: padding, child: child),
          ],
        ),
      ),
    );
  }
}
