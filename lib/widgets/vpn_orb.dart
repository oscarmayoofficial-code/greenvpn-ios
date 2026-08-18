import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../services/vpn_bridge.dart';

/// Same orb look as the Android app (see D:\greenvpn\android-proxy
/// activity_main.xml + MainActivity's tintRings/tintPower/applyOrbVisual):
/// a soft glow, two slowly counter-rotating decorative rings, a 238dp
/// gradient core, and a centered power icon — all tinted RING_GREEN when
/// connected / RING_RED otherwise, with a pulse while connected and an
/// overshoot "pop" whenever the state flips.
class VpnOrb extends StatefulWidget {
  const VpnOrb({super.key, required this.state, this.onTap});

  final VpnState state;
  final VoidCallback? onTap;

  @override
  State<VpnOrb> createState() => _VpnOrbState();
}

class _VpnOrbState extends State<VpnOrb> with TickerProviderStateMixin {
  static const ringGreen = Color(0xFF2FE84A);
  static const ringRed = Color(0xFFF0453B);

  late final AnimationController _ringMid =
      AnimationController(vsync: this, duration: const Duration(seconds: 16))..repeat();
  late final AnimationController _ringInner =
      AnimationController(vsync: this, duration: const Duration(seconds: 11))..repeat();
  late final AnimationController _pulse =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1300))
        ..repeat(reverse: true);
  late final AnimationController _pop = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 480),
  )..value = 1;

  @override
  void didUpdateWidget(covariant VpnOrb old) {
    super.didUpdateWidget(old);
    if (old.state != widget.state) _pop.forward(from: 0);
  }

  @override
  void dispose() {
    _ringMid.dispose();
    _ringInner.dispose();
    _pulse.dispose();
    _pop.dispose();
    super.dispose();
  }

  Color get _ringColor =>
      widget.state == VpnState.connected ? ringGreen : ringRed;

  @override
  Widget build(BuildContext context) {
    final connected = widget.state == VpnState.connected;
    final ringColor = _ringColor;

    return GestureDetector(
      onTap: widget.onTap,
      child: SizedBox(
        width: 160,
        height: 160,
        child: AnimatedBuilder(
          animation: Listenable.merge([_ringMid, _ringInner, _pulse, _pop]),
          builder: (context, _) {
            final pop = CurvedAnimation(parent: _pop, curve: Curves.elasticOut).value;
            final pulseScale = connected ? 1.0 + 0.08 * (_pulse.value) : 1.0;
            return Stack(
              alignment: Alignment.center,
              children: [
                // soft glow, brighter + wider once connected
                _Glow(color: ringColor, strength: connected ? 0.55 : 0.22),
                // two decorative rings, slowly counter-rotating, tinted to state
                Transform.rotate(
                  angle: _ringMid.value * 2 * math.pi,
                  child: CustomPaint(
                    size: const Size(160, 160),
                    painter: _RingPainter(color: ringColor, radius: 78, dashed: true),
                  ),
                ),
                Transform.rotate(
                  angle: -_ringInner.value * 2 * math.pi,
                  child: CustomPaint(
                    size: const Size(160, 160),
                    painter: _RingPainter(color: ringColor, radius: 64, dashed: true),
                  ),
                ),
                // core
                Transform.scale(
                  scale: 0.9 + 0.1 * pop,
                  child: Container(
                    width: 103,
                    height: 103,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        center: const Alignment(-0.16, -0.24),
                        radius: 0.9,
                        colors: connected
                            ? const [Color(0xFF22D38A), Color(0xFF0E7A55), Color(0xFF06392A)]
                            : const [Color(0xFF2E3B36), Color(0xFF23302B), Color(0xFF14201B)],
                      ),
                      border: Border.all(
                        color: connected
                            ? const Color(0x5A3DDC84)
                            : Colors.white.withValues(alpha: 0.06),
                        width: 2,
                      ),
                    ),
                  ),
                ),
                // power icon
                Transform.scale(
                  scale: pulseScale,
                  child: Transform.rotate(
                    angle: (1 - pop) * -2.1,
                    child: Icon(
                      Icons.power_settings_new_rounded,
                      size: 52,
                      color: ringColor,
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _Glow extends StatelessWidget {
  const _Glow({required this.color, required this.strength});
  final Color color;
  final double strength;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 160,
      height: 160,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [
            Colors.white.withValues(alpha: 0.35),
            color.withValues(alpha: strength * 0.5),
            color.withValues(alpha: 0),
          ],
          stops: const [0.0, 0.5, 1.0],
        ),
      ),
    );
  }
}

/// A segmented ring approximating the Android hud_ring_mid/hud_ring_inner
/// vector art (tick marks + a couple of brighter accent arcs), tinted to
/// [color] via opacity-graded strokes.
class _RingPainter extends CustomPainter {
  _RingPainter({required this.color, required this.radius, required this.dashed});

  final Color color;
  final double radius;
  final bool dashed;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final base = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = color.withValues(alpha: 0.2);
    canvas.drawCircle(center, radius, base);

    if (dashed) {
      const tickCount = 48;
      for (var i = 0; i < tickCount; i++) {
        final angle = (i / tickCount) * 2 * math.pi;
        final outer = center + Offset(math.cos(angle), math.sin(angle)) * radius;
        final inner = center + Offset(math.cos(angle), math.sin(angle)) * (radius - 4);
        canvas.drawLine(
          inner,
          outer,
          Paint()
            ..strokeWidth = i % 6 == 0 ? 1.6 : 1.0
            ..color = color.withValues(alpha: i % 6 == 0 ? 0.55 : 0.28),
        );
      }
    }

    // bright thick accent arc SEGMENTS, like the Android HUD ring's bold
    // broken red/green arcs (several around the ring at different lengths).
    final accent = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = dashed ? 5.5 : 6.5
      ..strokeCap = StrokeCap.round
      ..color = color.withValues(alpha: 0.95);
    final rect = Rect.fromCircle(center: center, radius: radius);
    // four arcs of varying sweep, spaced around the circle
    canvas.drawArc(rect, -math.pi * 0.62, math.pi * 0.34, false, accent);
    canvas.drawArc(rect, -math.pi * 0.10, math.pi * 0.20, false, accent);
    canvas.drawArc(rect, math.pi * 0.30, math.pi * 0.30, false, accent);
    canvas.drawArc(rect, math.pi * 0.78, math.pi * 0.16, false, accent);
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) =>
      old.color != color || old.radius != radius;
}
