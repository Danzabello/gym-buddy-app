import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../pages/wardrobe/wardrobe_avatar_render.dart' show hexToColor;
import '../services/coin_service.dart';
import '../theme/app_theme.dart';
import '../widgets/user_avatar.dart';
import 'onboarding_host.dart';
import 'onboarding_max.dart';
import 'onboarding_theme.dart';

class _Ring {
  final String name;
  final Color color;
  final String? unlock;
  const _Ring(this.name, this.color, [this.unlock]);
}

/// Parked: not in the flow, because no ring colour is free yet. Pick a ring colour from the shop's ring colours. Only rings that
/// cost nothing and need no achievement are pickable; the next two are shown
/// locked with their real unlock text.
class BorderStep extends StatefulWidget {
  const BorderStep({super.key});

  @override
  State<BorderStep> createState() => _BorderStepState();
}

class _BorderStepState extends State<BorderStep>
    with SingleTickerProviderStateMixin {
  late final AnimationController _arc = AnimationController(
      vsync: this, duration: const Duration(seconds: 1));
  List<ShopItem> _items = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _arc.value = 1;
    } else if (_arc.isDismissed) {
      _arc.forward();
    }
  }

  @override
  void dispose() {
    _arc.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final all = await CoinService().getShopItems();
    if (!mounted) return;
    setState(() => _items = [
          for (final i in all)
            if (i.category == 'ring_color' && i.colorHex != null) i
        ]);
  }

  static String _plain(String name) => name.replaceAll(' Ring', '');

  static bool _free(ShopItem i) =>
      i.cost == 0 && i.unlockAchievementId == null && i.unlockLevel <= 1;

  String _unlockText(ShopItem i) {
    if (i.unlockAchievementId != null) {
      return i.unlockAchievementName ?? 'Achievement';
    }
    if (i.unlockLevel > 1) return 'Level ${i.unlockLevel}';
    return '${i.cost} coins in Shop';
  }

  void _pick(_Ring r) {
    final draft = OnbScope.of(context).draft;
    setState(() {
      draft.ringColor = r.color;
      draft.ringName = r.name;
    });
    if (!MediaQuery.disableAnimationsOf(context)) _arc.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    final host = OnbScope.of(context);
    final draft = host.draft;
    final c = AppColors.of(context);
    final cs = Theme.of(context).colorScheme;

    final free = [
      _Ring('Classic', c.avatarRing),
      for (final i in _items)
        if (_free(i)) _Ring(_plain(i.name), hexToColor(i.colorHex!)),
    ];
    final locked = [
      for (final i in _items)
        if (!_free(i))
          _Ring(_plain(i.name), hexToColor(i.colorHex!), _unlockText(i)),
    ].take(2).toList();
    final chosen = free.firstWhere((r) => r.name == draft.ringName,
        orElse: () => free.first);

    return OnbStepFrame(
      footer: ObPrimaryButton(
          label: 'Choose ${chosen.name}', onTap: () => host.next()),
      child: Column(
        children: [
          MaxStrip(
            anchor: host.anchors[MaxSpot.border]!,
            spot: MaxSpot.border,
            text: 'Choose a ring. Rarer ones are earned.',
            bubbleVisible: host.bubbleVisible,
          ),
          const SizedBox(height: 20),
          Semantics(
            header: true,
            child: Text('Pick a border',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 30, fontWeight: FontWeight.w800, color: cs.onSurface)),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: 200,
            height: 200,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Positioned.fill(
                  child: AnimatedBuilder(
                    animation: _arc,
                    builder: (_, __) => CustomPaint(
                      painter: _RingPainter(
                          track: c.claySurface,
                          color: chosen.color,
                          progress: Curves.easeOut.transform(_arc.value)),
                    ),
                  ),
                ),
                Container(
                  width: 158,
                  height: 158,
                  decoration: BoxDecoration(
                      shape: BoxShape.circle, color: c.claySurface),
                  child: Center(
                    child: UserAvatar(
                        avatarId: draft.avatarId,
                        size: 130,
                        bare: true,
                        semanticLabel: 'Your avatar'),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Text(chosen.name,
              style: TextStyle(
                  fontSize: 22, fontWeight: FontWeight.w800, color: cs.onSurface)),
          const SizedBox(height: 18),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 12,
            runSpacing: 12,
            children: [
              for (final r in free)
                _Swatch(
                    ring: r,
                    selected: r.name == chosen.name,
                    onTap: () => _pick(r)),
            ],
          ),
          const SizedBox(height: 12),
          Text('Earn rarer rings by playing',
              style: TextStyle(fontSize: 13, color: c.subtleText)),
          if (locked.isNotEmpty) ...[
            const SizedBox(height: 18),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final r in locked) ...[
                  if (r != locked.first) const SizedBox(width: 12),
                  Expanded(child: _LockedTile(ring: r)),
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _Swatch extends StatelessWidget {
  final _Ring ring;
  final bool selected;
  final VoidCallback onTap;
  const _Swatch(
      {required this.ring, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final cs = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      inMutuallyExclusiveGroup: true,
      selected: selected,
      label: '${ring.name} ring',
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
                color: selected ? cs.onSurface : Colors.transparent, width: 2),
          ),
          child: Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: c.inputFill,
              border: Border.all(color: ring.color, width: 6),
            ),
          ),
        ),
      ),
    );
  }
}

class _LockedTile extends StatelessWidget {
  final _Ring ring;
  const _LockedTile({required this.ring});

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final cs = Theme.of(context).colorScheme;
    return Semantics(
      container: true,
      label: '${ring.name} ring, locked. ${ring.unlock}',
      excludeSemantics: true,
      child: Opacity(
        opacity: 0.85,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: c.claySurface,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: ring.color, width: 4),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(ring.name,
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: cs.onSurface)),
                    Text(ring.unlock ?? '',
                        style: TextStyle(fontSize: 12, color: c.subtleText)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  final Color track;
  final Color color;
  final double progress;
  const _RingPainter(
      {required this.track, required this.color, required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 10.0;
    final rect = Offset.zero & size;
    final arcRect = rect.deflate(stroke / 2);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(arcRect, 0, 2 * math.pi, false, paint..color = track);
    canvas.drawArc(
        arcRect, -math.pi / 2, 2 * math.pi * progress, false, paint..color = color);
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.color != color || old.progress != progress || old.track != track;
}
