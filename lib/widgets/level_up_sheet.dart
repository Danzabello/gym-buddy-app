import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/level_service.dart';

class LevelUpSheet extends StatefulWidget {
  final LevelUpResult result;

  const LevelUpSheet({super.key, required this.result});

  /// Call this from anywhere after awardXP returns a LevelUpResult
  static Future<void> show(BuildContext context, LevelUpResult result) {
    HapticFeedback.heavyImpact();
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => LevelUpSheet(result: result),
    );
  }

  @override
  State<LevelUpSheet> createState() => _LevelUpSheetState();
}

class _LevelUpSheetState extends State<LevelUpSheet>
    with TickerProviderStateMixin {
  late AnimationController _scaleController;
  late AnimationController _confettiController;
  late AnimationController _slideController;
  late Animation<double> _scaleAnim;
  late Animation<double> _fadeAnim;
  late Animation<Offset> _slideAnim;

  final List<_ConfettiParticle> _particles = [];

  @override
  void initState() {
    super.initState();

    // Scale bounce for level badge
    _scaleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _scaleAnim = CurvedAnimation(
      parent: _scaleController,
      curve: Curves.elasticOut,
    );

    // Confetti fade
    _confettiController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    );
    _fadeAnim = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(
        parent: _confettiController,
        curve: const Interval(0.6, 1.0),
      ),
    );

    // Sheet slide up
    _slideController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 0.3),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _slideController,
      curve: Curves.easeOutCubic,
    ));

    // Spawn confetti particles
    _spawnParticles();

    // Sequence the animations
    _slideController.forward();
    Future.delayed(const Duration(milliseconds: 200), () {
      _scaleController.forward();
      _confettiController.forward();
    });
  }

  void _spawnParticles() {
    final colors = [
      const Color(0xFFFF6B6B),
      const Color(0xFFFFD93D),
      const Color(0xFF6BCB77),
      const Color(0xFF4D96FF),
      const Color(0xFFFF922B),
      const Color(0xFFCC5DE8),
      const Color(0xFF20C997),
    ];
    for (int i = 0; i < 40; i++) {
      _particles.add(_ConfettiParticle(
        color: colors[i % colors.length],
        x: 0.1 + (i / 40) * 0.8,
        delay: (i * 30).toDouble(),
        size: 6 + (i % 4) * 3.0,
        isRect: i % 3 == 0,
      ));
    }
  }

  @override
  void dispose() {
    _scaleController.dispose();
    _confettiController.dispose();
    _slideController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final level = widget.result.newLevel;
    final unlocked = widget.result.unlockedItems;

    return SlideTransition(
      position: _slideAnim,
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 32),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(28),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.15),
              blurRadius: 30,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(28),
          child: Stack(
            children: [
              // Gradient header
              Container(
                height: 180,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF7C3AED), Color(0xFFDB2777)],
                  ),
                ),
              ),

              // Confetti layer
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                height: 180,
                child: AnimatedBuilder(
                  animation: _confettiController,
                  builder: (_, __) => FadeTransition(
                    opacity: _fadeAnim,
                    child: CustomPaint(
                      painter: _ConfettiPainter(
                        particles: _particles,
                        progress: _confettiController.value,
                      ),
                    ),
                  ),
                ),
              ),

              // Content
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Level badge
                    ScaleTransition(
                      scale: _scaleAnim,
                      child: Container(
                        width: 100,
                        height: 100,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white,
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF7C3AED).withOpacity(0.4),
                              blurRadius: 20,
                              spreadRadius: 4,
                            ),
                          ],
                        ),
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                '$level',
                                style: const TextStyle(
                                  fontSize: 36,
                                  fontWeight: FontWeight.w900,
                                  color: Color(0xFF7C3AED),
                                  height: 1.0,
                                ),
                              ),
                              const Text(
                                'LEVEL',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF7C3AED),
                                  letterSpacing: 1.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 20),

                    // Title
                    const Text(
                      'Level Up! 🎉',
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'You reached Level $level!',
                      style: TextStyle(
                        fontSize: 15,
                        color: Colors.white.withOpacity(0.85),
                      ),
                    ),

                    const SizedBox(height: 28),

                    // Unlocked items
                    if (unlocked.isNotEmpty) ...[
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF5F3FF),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: const Color(0xFF7C3AED).withOpacity(0.2),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              '🔓 Newly Unlocked',
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                                color: Color(0xFF7C3AED),
                              ),
                            ),
                            const SizedBox(height: 12),
                            ...unlocked.map((item) => Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Row(
                                children: [
                                  Container(
                                    width: 40,
                                    height: 40,
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF7C3AED)
                                          .withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Center(
                                      child: Text(
                                        item.emoji,
                                        style: const TextStyle(fontSize: 20),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          item.name,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w600,
                                            fontSize: 14,
                                          ),
                                        ),
                                        Text(
                                          _categoryLabel(item.category),
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.grey[600],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 10, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF10B981)
                                          .withOpacity(0.12),
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: const Text(
                                      'NEW',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                        color: Color(0xFF10B981),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            )),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                    ] else ...[
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Colors.grey[50],
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.emoji_events,
                                color: Colors.amber[600], size: 20),
                            const SizedBox(width: 8),
                            Text(
                              'Keep going — more unlocks ahead!',
                              style: TextStyle(
                                color: Colors.grey[700],
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],

                    // CTA button
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () => Navigator.pop(context),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF7C3AED),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          elevation: 0,
                        ),
                        child: const Text(
                          'Let\'s Go! 💪',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _categoryLabel(String category) {
    switch (category) {
      case 'avatar': return 'Avatar icon';
      case 'avatar_frame': return 'Profile frame';
      case 'badge': return 'Badge';
      case 'streak_emoji': return 'Streak emoji';
      default: return category;
    }
  }
}

// ============================================================
// CONFETTI PAINTER
// ============================================================
class _ConfettiParticle {
  final Color color;
  final double x;
  final double delay;
  final double size;
  final bool isRect;

  const _ConfettiParticle({
    required this.color,
    required this.x,
    required this.delay,
    required this.size,
    required this.isRect,
  });
}

class _ConfettiPainter extends CustomPainter {
  final List<_ConfettiParticle> particles;
  final double progress;

  const _ConfettiPainter({required this.particles, required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    for (final p in particles) {
      final t = ((progress * 2000 - p.delay) / 1700).clamp(0.0, 1.0);
      if (t <= 0) continue;

      final x = p.x * size.width + (t * 30 * (p.x > 0.5 ? 1 : -1));
      final y = size.height * t * 1.2;

      final paint = Paint()..color = p.color.withOpacity((1 - t * 0.8));

      if (p.isRect) {
        canvas.save();
        canvas.translate(x, y);
        canvas.rotate(t * 6.28);
        canvas.drawRect(
          Rect.fromCenter(center: Offset.zero, width: p.size, height: p.size * 0.5),
          paint,
        );
        canvas.restore();
      } else {
        canvas.drawCircle(Offset(x, y), p.size / 2, paint);
      }
    }
  }

  @override
  bool shouldRepaint(_ConfettiPainter old) => old.progress != progress;
}