import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../theme/app_theme.dart';
import 'wardrobe_selection_state.dart';

/// Standard luminance-weighted greyscale matrix, applied to locked nodes.
const _greyscaleFilter = ColorFilter.matrix(<double>[
  0.2126, 0.7152, 0.0722, 0, 0,
  0.2126, 0.7152, 0.0722, 0, 0,
  0.2126, 0.7152, 0.0722, 0, 0,
  0, 0, 0, 1, 0,
]);

/// Applies the greyscale filter only when [locked] — a no-op passthrough otherwise.
Widget _maybeGreyscale(bool locked, Widget child) =>
    locked ? ColorFiltered(colorFilter: _greyscaleFilter, child: child) : child;

const _canvasWidth = 400.0;
const _canvasHeight = 260.0;
const _hubRadius = 32.0;
const _nodeRadius = 28.0;

class _HubSpec {
  final String slug;
  final String emoji;
  final String name;
  final Offset pos;
  const _HubSpec(this.slug, this.emoji, this.name, this.pos);
}

// Fixed coordinates, not derived from a radius/angle formula — each hub's
// two paths render as straight columns beneath it, not a radial fan.
const _hubs = <_HubSpec>[
  _HubSpec('wolf', '🐺', 'Wolf', Offset(67, 60)),
  _HubSpec('bear', '🐻', 'Bear', Offset(200, 60)),
  _HubSpec('lion', '🦁', 'Lion', Offset(333, 60)),
];

class _PathLayout {
  final String key;
  final String label;
  final Color Function(AppColors) color;
  final Offset hub;
  final Offset tier1;
  final Offset tier2;
  const _PathLayout(this.key, this.label, this.color, this.hub, this.tier1, this.tier2);
}

// Reuses existing accent-aware semantic roles — no new hardcoded hex.
final _paths = <_PathLayout>[
  _PathLayout('level', 'Level', (c) => c.warn, const Offset(67, 60), const Offset(35, 150), const Offset(35, 220)),
  _PathLayout('social', 'Social', (c) => c.subtleText, const Offset(67, 60), const Offset(99, 150), const Offset(99, 220)),
  _PathLayout('workout', 'Workout', (c) => c.streakOrange, const Offset(200, 60), const Offset(168, 150), const Offset(168, 220)),
  _PathLayout('special', 'Special', (c) => c.info, const Offset(200, 60), const Offset(232, 150), const Offset(232, 220)),
  _PathLayout('coop', 'Co-op', (c) => c.successGreen, const Offset(333, 60), const Offset(333, 150), const Offset(333, 220)),
];

class _TreeNode {
  final String pathKey;
  final int tier;
  final String name;
  final String emoji;
  final int? requiredLevel;
  final String? achievementId;
  final int? targetValue;
  final int progress;
  final bool unlocked;
  final bool isSocialPlaceholder;
  // The bare legacy avatar_id slug (e.g. 'wolf') this node equips to — null
  // when the species has no rendering support elsewhere in the app yet
  // (Mammoth, Seasonal Creature), in which case no Select button is shown.
  final String? equipSlug;

  const _TreeNode({
    required this.pathKey,
    required this.tier,
    required this.name,
    required this.emoji,
    this.requiredLevel,
    this.achievementId,
    this.targetValue,
    this.progress = 0,
    this.unlocked = false,
    this.isSocialPlaceholder = false,
    this.equipSlug,
  });
}

/// The forest-layout avatar unlock tree — embedded in [WardrobeAvatarScreen]
/// as the sole lock/unlock authority and equip surface for avatar species.
/// Three always-unlocked starter hubs (Wolf/Bear/Lion), each owning a fixed
/// pair of unlock paths rendered as straight two-node columns beneath it.
class AvatarUnlockTree extends StatefulWidget {
  const AvatarUnlockTree({super.key});

  @override
  State<AvatarUnlockTree> createState() => _AvatarUnlockTreeState();
}

class _AvatarUnlockTreeState extends State<AvatarUnlockTree> {
  bool _loading = true;
  String? _error;
  List<_TreeNode> _nodes = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final client = Supabase.instance.client;
      final userId = client.auth.currentUser!.id;

      final results = await Future.wait<dynamic>([
        client.from('user_profiles').select('level').eq('id', userId).single(),
        client
            .from('shop_items')
            .select('name, emoji, asset_id, unlock_level, unlock_achievement_id, unlock_path, unlock_tier')
            .not('unlock_path', 'is', null),
        client
            .from('user_achievements')
            .select('achievement_id, progress, unlocked_at')
            .eq('user_id', userId),
        client.from('achievements').select('id, target_value').eq('category', 'avatar_unlock'),
      ]);

      final userLevel = (results[0] as Map<String, dynamic>)['level'] as int? ?? 1;
      final shopItems = results[1] as List<dynamic>;
      final userAchievements = {
        for (final row in results[2] as List<dynamic>)
          (row as Map<String, dynamic>)['achievement_id'] as String: row,
      };
      final achievementTargets = {
        for (final row in results[3] as List<dynamic>)
          (row as Map<String, dynamic>)['id'] as String: row['target_value'] as int,
      };

      final nodes = <_TreeNode>[];
      for (final raw in shopItems) {
        final item = raw as Map<String, dynamic>;
        final equipSlug = item['asset_id'] as String?;
        final path = item['unlock_path'] as String;
        final tier = item['unlock_tier'] as int;
        final achievementId = item['unlock_achievement_id'] as String?;

        if (path == 'level') {
          final requiredLevel = item['unlock_level'] as int;
          nodes.add(_TreeNode(
            pathKey: path,
            tier: tier,
            name: item['name'] as String,
            emoji: item['emoji'] as String,
            requiredLevel: requiredLevel,
            progress: userLevel,
            targetValue: requiredLevel,
            unlocked: userLevel >= requiredLevel,
            equipSlug: equipSlug,
          ));
        } else if (achievementId != null) {
          final ua = userAchievements[achievementId];
          final target = achievementTargets[achievementId] ?? 1;
          nodes.add(_TreeNode(
            pathKey: path,
            tier: tier,
            name: item['name'] as String,
            emoji: item['emoji'] as String,
            achievementId: achievementId,
            targetValue: target,
            progress: (ua?['progress'] as int?) ?? 0,
            unlocked: ua?['unlocked_at'] != null,
            equipSlug: equipSlug,
          ));
        } else {
          // Event-gated tier (e.g. Seasonal Creature) — no achievement to track yet.
          nodes.add(_TreeNode(
            pathKey: path,
            tier: tier,
            name: item['name'] as String,
            emoji: item['emoji'] as String,
            equipSlug: equipSlug,
          ));
        }
      }

      // Social path is a client-only placeholder — no backing data exists yet.
      nodes.addAll(const [
        _TreeNode(pathKey: 'social', tier: 1, name: 'Coming soon', emoji: '❔', isSocialPlaceholder: true),
        _TreeNode(pathKey: 'social', tier: 2, name: 'Coming soon', emoji: '❔', isSocialPlaceholder: true),
      ]);

      // shop_items RLS ("Users see all shop items") only exposes rows where
      // is_available = true. Seasonal Creature is intentionally false (its
      // unlock isn't built yet, and purchase_shop_item gates on that same
      // flag) so it never comes back from the query above — hardcode its
      // display here rather than loosening the RLS/purchase gate for it.
      if (!nodes.any((n) => n.pathKey == 'special' && n.tier == 2)) {
        nodes.add(const _TreeNode(
          pathKey: 'special',
          tier: 2,
          name: 'Seasonal Creature',
          emoji: '❄️',
        ));
      }

      if (mounted) setState(() { _nodes = nodes; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = 'Failed to load — please try again'; _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final appColors = AppColors.of(context);
    if (_loading) {
      return const SizedBox(height: _canvasHeight, child: Center(child: CircularProgressIndicator()));
    }
    if (_error != null) {
      return SizedBox(
        height: _canvasHeight,
        child: Center(child: Text(_error!, style: TextStyle(color: appColors.subtleText))),
      );
    }
    final selection = context.watch<WardrobeSelectionState>();
    // Scales down on narrow phones rather than overflowing — never scales up.
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: _buildTree(appColors, selection),
    );
  }

  Widget _buildTree(AppColors appColors, WardrobeSelectionState selection) {
    return SizedBox(
      width: _canvasWidth,
      height: _canvasHeight,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          CustomPaint(
            size: const Size(_canvasWidth, _canvasHeight),
            painter: _ConnectorPainter(paths: _paths, appColors: appColors),
          ),
          for (final hub in _hubs) _buildHubNode(hub, appColors, selection),
          for (final path in _paths) ...[
            for (final node in _nodes.where((n) => n.pathKey == path.key))
              _buildNode(node, path, appColors, node.tier == 1 ? path.tier1 : path.tier2),
          ],
        ],
      ),
    );
  }

  Widget _buildHubNode(_HubSpec hub, AppColors appColors, WardrobeSelectionState selection) {
    final equipped = selection.avatarId == hub.slug;
    return Positioned(
      left: hub.pos.dx - _hubRadius,
      top: hub.pos.dy - _hubRadius,
      child: GestureDetector(
        onTap: () => _showHubSheet(hub, equipped, appColors),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              width: _hubRadius * 2,
              height: _hubRadius * 2,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: appColors.cardBackground,
                border: Border.all(
                  color: equipped ? appColors.avatarRing : appColors.cardBorder,
                  width: equipped ? 3 : 1.5,
                ),
              ),
              alignment: Alignment.center,
              child: Text(hub.emoji, style: const TextStyle(fontSize: 28)),
            ),
            if (equipped)
              Positioned(
                right: -2,
                bottom: -2,
                child: Container(
                  width: 18,
                  height: 18,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: appColors.successGreen,
                    border: Border.all(color: appColors.sectionBackground, width: 2),
                  ),
                  alignment: Alignment.center,
                  child: Icon(Icons.check_rounded,
                      size: 10, color: appColors.readableForeground(appColors.successGreen)),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildNode(_TreeNode node, _PathLayout path, AppColors appColors, Offset point) {
    final pathColor = path.color(appColors);
    final locked = node.isSocialPlaceholder || !node.unlocked;

    return Positioned(
      left: point.dx - _nodeRadius,
      top: point.dy - _nodeRadius,
      child: GestureDetector(
        onTap: () => _showNodeSheet(node, path, appColors),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              width: _nodeRadius * 2,
              height: _nodeRadius * 2,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: appColors.cardBackground,
                border: Border.all(
                  color: locked ? appColors.cardBorder : pathColor,
                  width: locked ? 1.5 : 2.5,
                ),
              ),
              alignment: Alignment.center,
              child: _maybeGreyscale(
                locked,
                Opacity(
                  opacity: locked ? 0.45 : 1.0,
                  child: Text(node.emoji, style: const TextStyle(fontSize: 24)),
                ),
              ),
            ),
            Positioned(
              right: -2,
              bottom: -2,
              child: Container(
                width: 18,
                height: 18,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: locked ? appColors.cardBackground : appColors.successGreen,
                  border: Border.all(color: appColors.sectionBackground, width: 2),
                ),
                alignment: Alignment.center,
                child: Icon(
                  locked ? Icons.lock_rounded : Icons.check_rounded,
                  size: 10,
                  color: locked ? appColors.subtleText : appColors.readableForeground(appColors.successGreen),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _conditionText(_TreeNode node) {
    switch (node.pathKey) {
      case 'hub':
        return 'Always unlocked';
      case 'level':
        return 'Reach level ${node.requiredLevel}';
      case 'workout':
        return 'Complete ${node.targetValue} workouts';
      case 'coop':
        return 'Reach a ${node.targetValue}-day team streak';
      case 'special':
        return node.achievementId != null
            ? 'Check in with Coach Max ${node.targetValue} times'
            : 'Unlocked during a limited-time seasonal event';
      default:
        return '';
    }
  }

  /// Hubs are just always-unlocked, progress-less species nodes — represent
  /// one as a [_TreeNode] and reuse [_showNodeSheet] verbatim instead of a
  /// second sheet builder.
  void _showHubSheet(_HubSpec hub, bool equipped, AppColors appColors) {
    final hubNode = _TreeNode(
      pathKey: 'hub',
      tier: 0,
      name: hub.name,
      emoji: hub.emoji,
      unlocked: true,
      equipSlug: hub.slug,
    );
    final hubPath = _PathLayout('hub', 'Starter', (c) => c.avatarRing,
        hub.pos, hub.pos, hub.pos);
    _showNodeSheet(hubNode, hubPath, appColors);
  }

  void _showNodeSheet(_TreeNode node, _PathLayout path, AppColors appColors) {
    HapticFeedback.selectionClick();
    // Read outside the sheet builder — showModalBottomSheet's builder context
    // sits under a different route, context.read still resolves the ancestor
    // provider fine here, but capturing it up front keeps intent explicit.
    final selection = context.read<WardrobeSelectionState>();
    showModalBottomSheet(
      context: context,
      backgroundColor: appColors.cardBackground,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        final locked = node.isSocialPlaceholder || !node.unlocked;
        final pathColor = path.color(appColors);
        final canSelect = !locked && node.equipSlug != null;
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _maybeGreyscale(
                    locked,
                    Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: appColors.tint(pathColor),
                        border: Border.all(color: pathColor, width: 2),
                      ),
                      alignment: Alignment.center,
                      child: Text(node.emoji, style: const TextStyle(fontSize: 28)),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(node.name,
                            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: appColors.tint(pathColor),
                            borderRadius: BorderRadius.circular(100),
                          ),
                          child: Text(path.label,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: appColors.readableForeground(appColors.tint(pathColor)),
                              )),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              if (node.isSocialPlaceholder) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: appColors.tint(appColors.subtleText),
                    borderRadius: BorderRadius.circular(100),
                  ),
                  child: Text('Coming soon',
                      style: TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w600, color: appColors.subtleText)),
                ),
              ] else ...[
                Text(_conditionText(node),
                    style: TextStyle(fontSize: 14, color: appColors.subtleText)),
                if (node.targetValue != null) ...[
                  const SizedBox(height: 14),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(100),
                    child: LinearProgressIndicator(
                      value: (node.progress / node.targetValue!).clamp(0.0, 1.0),
                      minHeight: 8,
                      backgroundColor: appColors.cardBorder,
                      valueColor: AlwaysStoppedAnimation(pathColor),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text('${node.progress} / ${node.targetValue}',
                      style: TextStyle(fontSize: 12, color: appColors.subtleText)),
                ],
                if (canSelect) ...[
                  const SizedBox(height: 18),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () {
                        HapticFeedback.mediumImpact();
                        selection.setAvatar(node.equipSlug!);
                        Navigator.of(sheetContext).pop();
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: pathColor,
                        foregroundColor: appColors.readableForeground(pathColor),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        elevation: 0,
                      ),
                      child: const Text('Select', style: TextStyle(fontWeight: FontWeight.w600)),
                    ),
                  ),
                ],
              ],
            ],
          ),
        );
      },
    );
  }
}

class _ConnectorPainter extends CustomPainter {
  final List<_PathLayout> paths;
  final AppColors appColors;
  _ConnectorPainter({required this.paths, required this.appColors});

  @override
  void paint(Canvas canvas, Size size) {
    for (final path in paths) {
      final paint = Paint()
        ..color = path.color(appColors).withValues(alpha: 0.5)
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round;

      _drawDashed(canvas, _trim(path.hub, path.tier1, _hubRadius, _nodeRadius), paint);
      _drawDashed(canvas, _trim(path.tier1, path.tier2, _nodeRadius, _nodeRadius), paint);
    }
  }

  /// Trims a straight segment inward at both ends by the given radii, so the
  /// dashed line starts/ends at the node circles' edges, not their centers.
  (Offset, Offset) _trim(Offset a, Offset b, double ra, double rb) {
    final total = (b - a).distance;
    if (total <= 0) return (a, b);
    final dir = (b - a) / total;
    return (a + dir * ra, b - dir * rb);
  }

  void _drawDashed(Canvas canvas, (Offset, Offset) segment, Paint paint) {
    final (start, end) = segment;
    const dashLength = 6.0;
    const gapLength = 5.0;
    final total = (end - start).distance;
    if (total <= 0) return;
    final direction = (end - start) / total;
    var covered = 0.0;
    while (covered < total) {
      final dashEnd = math.min(covered + dashLength, total);
      canvas.drawLine(start + direction * covered, start + direction * dashEnd, paint);
      covered += dashLength + gapLength;
    }
  }

  @override
  bool shouldRepaint(covariant _ConnectorPainter oldDelegate) => false;
}
