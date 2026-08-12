import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../services/vpn_bridge.dart';

/// The central connect button. Same look language as the Android app's power
/// orb (bright green when connected, red when off, amber while connecting) —
/// see greenvpn-android memory for RING_GREEN/RING_RED reference values.
class VpnOrb extends StatefulWidget {
  const VpnOrb({super.key, required this.state, this.onTap});

  final VpnState state;
  final VoidCallback? onTap;

  @override
  State<VpnOrb> createState() => _VpnOrbState();
}

class _VpnOrbState extends State<VpnOrb> with TickerProviderStateMixin {
  late final AnimationController _pulse =
      AnimationController(vsync: this, duration: const Duration(seconds: 2))
        ..repeat(reverse: true);
  late final AnimationController _spin =
      AnimationController(vsync: this, duration: const Duration(seconds: 1))
        ..repeat();

  static const _green = Color(0xFF2FE84A);
  static const _red = Color(0xFFF0453B);
  static const _amber = Color(0xFFFFB020);

  @override
  void dispose() {
    _pulse.dispose();
    _spin.dispose();
    super.dispose();
  }

  Color get _accent => switch (widget.state) {
        VpnState.connected => _green,
        VpnState.connecting => _amber,
        VpnState.error => _red,
        VpnState.disconnected => _red,
      };

  @override
  Widget build(BuildContext context) {
    const size = 220.0;
    return GestureDetector(
      onTap: widget.onTap,
      child: AnimatedBuilder(
        animation: Listenable.merge([_pulse, _spin]),
        builder: (context, _) {
          final pulse = widget.state == VpnState.connected
              ? 0.96 + 0.04 * _pulse.value
              : 1.0;
          return SizedBox(
            width: size,
            height: size,
            child: CustomPaint(
              painter: _OrbPainter(
                accent: _accent,
                connecting: widget.state == VpnState.connecting,
                spin: _spin.value,
                pulse: pulse,
              ),
              child: Center(
                child: Icon(
                  Icons.power_settings_new_rounded,
                  color: Colors.white,
                  size: 56,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _OrbPainter extends CustomPainter {
  _OrbPainter({
    required this.accent,
    required this.connecting,
    required this.spin,
    required this.pulse,
  });

  final Color accent;
  final bool connecting;
  final double spin;
  final double pulse;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 * pulse;

    final glow = Paint()
      ..shader = RadialGradient(
        colors: [accent.withValues(alpha: 0.35), accent.withValues(alpha: 0)],
      ).createShader(Rect.fromCircle(center: center, radius: radius));
    canvas.drawCircle(center, radius, glow);

    final body = Paint()
      ..shader = RadialGradient(
        center: const Alignment(-0.3, -0.4),
        colors: [
          Color.lerp(accent, Colors.white, 0.2)!,
          accent,
          Color.lerp(accent, Colors.black, 0.55)!,
        ],
        stops: const [0.0, 0.55, 1.0],
      ).createShader(Rect.fromCircle(center: center, radius: radius * 0.72));
    canvas.drawCircle(center, radius * 0.72, body);

    if (connecting) {
      final ringRect = Rect.fromCircle(center: center, radius: radius * 0.86);
      final track = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5
        ..color = Colors.white.withValues(alpha: 0.12);
      canvas.drawCircle(center, radius * 0.86, track);

      final ring = Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = 5
        ..color = Colors.white;
      canvas.drawArc(ringRect, 2 * math.pi * spin, math.pi * 0.6, false, ring);
    }
  }

  @override
  bool shouldRepaint(covariant _OrbPainter old) =>
      old.accent != accent ||
      old.connecting != connecting ||
      old.spin != spin ||
      old.pulse != pulse;
}
