import 'dart:math';

import 'package:flutter/material.dart';

enum OrbMode { idle, listening, hearing, thinking, speaking, paused }

/// Sfera animata stile assistente vocale, con la bandiera al centro.
class Orb extends StatefulWidget {
  final OrbMode mode;
  final double level; // 0..1 volume della voce
  final Color color;
  final String flag;
  final double size;
  final VoidCallback? onTap;

  const Orb({
    super.key,
    required this.mode,
    required this.level,
    required this.color,
    required this.flag,
    this.size = 230,
    this.onTap,
  });

  @override
  State<Orb> createState() => _OrbState();
}

class _OrbState extends State<Orb> with SingleTickerProviderStateMixin {
  late final AnimationController _t =
      AnimationController(vsync: this, duration: const Duration(seconds: 6))
        ..repeat();
  double _smooth = 0;

  @override
  void dispose() {
    _t.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      child: SizedBox(
        width: widget.size * 1.35,
        height: widget.size * 1.35,
        child: AnimatedBuilder(
          animation: _t,
          builder: (_, __) {
            // volume ammorbidito per un movimento fluido
            final target = widget.mode == OrbMode.hearing ||
                    widget.mode == OrbMode.listening
                ? min(1.0, sqrt(widget.level) * 2.2)
                : 0.0;
            _smooth += (target - _smooth) * 0.25;
            return CustomPaint(
              painter: _OrbPainter(
                t: _t.value,
                mode: widget.mode,
                level: _smooth,
                color: widget.color,
              ),
              child: Center(
                child: AnimatedScale(
                  duration: const Duration(milliseconds: 200),
                  scale: widget.mode == OrbMode.paused ? 0.85 : 1,
                  child: Container(
                    width: widget.size * 0.42,
                    height: widget.size * 0.42,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withValues(alpha: 0.92),
                      boxShadow: [
                        BoxShadow(
                          color: widget.color.withValues(alpha: 0.35),
                          blurRadius: 24,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: widget.mode == OrbMode.paused
                        ? Icon(Icons.pause_rounded,
                            size: widget.size * 0.2, color: widget.color)
                        : Text(widget.flag,
                            style: TextStyle(fontSize: widget.size * 0.2)),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _OrbPainter extends CustomPainter {
  final double t, level;
  final OrbMode mode;
  final Color color;
  _OrbPainter(
      {required this.t,
      required this.mode,
      required this.level,
      required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final base = size.width / 1.35 / 2;
    final a = t * 2 * pi;

    // respiro lento + reazione alla voce
    final breathe = mode == OrbMode.paused ? 0.0 : sin(a * 2) * 0.02;
    var r = base * (1 + breathe + level * 0.16);
    if (mode == OrbMode.paused) r = base * 0.86;

    // onde quando la voce legge la traduzione
    if (mode == OrbMode.speaking) {
      for (var i = 0; i < 3; i++) {
        final p = (t * 3 + i / 3) % 1.0;
        canvas.drawCircle(
          c,
          base * (1 + p * 0.32),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3
            ..color = color.withValues(alpha: (1 - p) * 0.35),
        );
      }
    }

    // alone
    canvas.drawCircle(
      c,
      r * 1.18,
      Paint()
        ..shader = RadialGradient(colors: [
          color.withValues(alpha: 0.28),
          color.withValues(alpha: 0),
        ]).createShader(Rect.fromCircle(center: c, radius: r * 1.18)),
    );

    // sfera con gradiente che ruota (effetto nuvola lucida)
    final rect = Rect.fromCircle(center: c, radius: r);
    final light = Color.lerp(color, Colors.white, 0.75)!;
    final mid = Color.lerp(color, Colors.white, 0.3)!;
    canvas.save();
    canvas.clipPath(Path()..addOval(rect));
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment(cos(a), sin(a)),
          end: Alignment(-cos(a), -sin(a)),
          colors: [color, mid, light],
          stops: const [0.0, 0.55, 1.0],
        ).createShader(rect),
    );
    // "nuvole" morbide che si muovono
    for (var i = 0; i < 3; i++) {
      final ang = a * (i.isEven ? 1 : -1) + i * 2.1;
      final o = c + Offset(cos(ang), sin(ang)) * r * 0.45;
      canvas.drawCircle(
        o,
        r * (0.55 + 0.1 * sin(a * 3 + i)),
        Paint()
          ..shader = RadialGradient(colors: [
            Colors.white.withValues(alpha: 0.45),
            Colors.white.withValues(alpha: 0),
          ]).createShader(Rect.fromCircle(center: o, radius: r * 0.65)),
      );
    }
    // riflesso lucido in alto
    canvas.drawOval(
      Rect.fromCenter(
          center: c + Offset(-r * 0.25, -r * 0.55),
          width: r * 0.9,
          height: r * 0.35),
      Paint()..color = Colors.white.withValues(alpha: 0.35),
    );
    canvas.restore();

    // anello che gira mentre traduce
    if (mode == OrbMode.thinking) {
      canvas.drawArc(
        Rect.fromCircle(center: c, radius: r + 10),
        a * 3,
        pi * 0.7,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 5
          ..strokeCap = StrokeCap.round
          ..color = color,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _OrbPainter old) => true;
}
