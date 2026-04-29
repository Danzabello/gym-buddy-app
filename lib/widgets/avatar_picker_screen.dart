import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'user_avatar.dart';
import '../services/level_service.dart';


enum AvatarBorderStyle { simple, bold, arc }

class AvatarPickerScreen extends StatefulWidget {
  final void Function(String avatarId, String borderStyle)? onCompleteWithData;
  final VoidCallback? onComplete;
  final bool showHeader;

  const AvatarPickerScreen({
    super.key,
    this.onComplete,
    this.onCompleteWithData,
    this.showHeader = true,
  }) : assert(
          onComplete != null || onCompleteWithData != null,
          'Provide either onComplete or onCompleteWithData',
        );

  @override
  State<AvatarPickerScreen> createState() => _AvatarPickerScreenState();
}

class _AvatarPickerScreenState extends State<AvatarPickerScreen>
    with SingleTickerProviderStateMixin {

  // ── Starter avatars (always available) ─────────────────────────────────
  static const _starters = [
    _AvatarOption(
      id: 'lion',
      emoji: '🦁',
      name: 'Lion',
      desc: 'Power & Courage',
      traits: ['Strength', 'Bold', 'Leader'],
      color: Color(0xFFD85A30),
      bgColor: Color(0xFFFAECE7),
      borderColor: Color(0xFFC07010),
    ),
    _AvatarOption(
      id: 'wolf',
      emoji: '🐺',
      name: 'Wolf',
      desc: 'Speed & Loyalty',
      traits: ['Speed', 'Loyal', 'Sharp'],
      color: Color(0xFF185FA5),
      bgColor: Color(0xFFE6F1FB),
      borderColor: Color(0xFF3E6890),
    ),
    _AvatarOption(
      id: 'bear',
      emoji: '🐻',
      name: 'Bear',
      desc: 'Power & Endurance',
      traits: ['Strength', 'Steady', 'Calm'],
      color: Color(0xFF0F6E56),
      bgColor: Color(0xFFE1F5EE),
      borderColor: Color(0xFF8B5E10),
    ),
  ];

  // ── All earnable avatars — order matches the grid display ───────────────
  static const _earnable = [
    _EarnableAvatar(id: 'eagle',        emoji: '🦅', name: 'Eagle',       req: '30-day streak'),
    _EarnableAvatar(id: 'shark',        emoji: '🦈', name: 'Shark',       req: '60-day streak'),
    _EarnableAvatar(id: 'gorilla',      emoji: '🦍', name: 'Gorilla',     req: '100-day streak'),
    _EarnableAvatar(id: 'tiger',        emoji: '🐯', name: 'Tiger',       req: '50 co-ops'),
    _EarnableAvatar(id: 'buffalo',      emoji: '🦬', name: 'Buffalo',     req: 'Level 5'),
    _EarnableAvatar(id: 'robot',        emoji: '🤖', name: 'Robot',       req: 'Level 10'),
    _EarnableAvatar(id: 'flexed',       emoji: '💪', name: 'Flex',        req: '90-day streak'),
    _EarnableAvatar(id: 'weightlifter', emoji: '🏋️', name: 'Lifter',     req: '100 co-ops'),
    _EarnableAvatar(id: 'runner',       emoji: '🏃', name: 'Runner',      req: '150 co-ops'),
  ];

  // ── State ───────────────────────────────────────────────────────────────
  int _selectedAvatarIndex = 0;
  AvatarBorderStyle _selectedBorder = AvatarBorderStyle.simple;
  bool _isSaving = false;

  // Unlock data
  Set<String> _unlockedAvatarIds = {};
  Set<String> _unlockedBorderIds = {};
  bool _loadingUnlocks = true;

  late final AnimationController _bounceController;
  late final Animation<double> _bounceAnim;

  _AvatarOption get _selected => _starters[_selectedAvatarIndex];

  @override
  void initState() {
    super.initState();
    _bounceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _bounceAnim = Tween<double>(begin: 1.0, end: 1.08).animate(
      CurvedAnimation(parent: _bounceController, curve: Curves.elasticOut),
    );
    _loadUnlocks();
  }

  Future<void> _loadUnlocks() async {
    // Skip unlock loading during onboarding — no user exists yet
    if (Supabase.instance.client.auth.currentUser == null) {
      if (mounted) setState(() => _loadingUnlocks = false);
      return;
    }
    try {
      final unlocks = await LevelService().getUnlockedCosmetics();
      if (mounted) {
        setState(() {
          _unlockedAvatarIds = unlocks
              .where((u) => u['unlock_reason']?.toString().contains('streak') == true ||
                            u['unlock_reason']?.toString().contains('coop') == true ||
                            u['unlock_reason']?.toString().contains('level') == true)
              .map((u) => u['shop_item_id'] as String)
              .toSet();
          // For borders, check by shop_item_id directly
          _unlockedBorderIds = unlocks
              .where((u) => u['shop_item_id'] == 'bold' || u['shop_item_id'] == 'arc')
              .map((u) => u['shop_item_id'] as String)
              .toSet();
          _loadingUnlocks = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loadingUnlocks = false);
    }
  }

  @override
  void dispose() {
    _bounceController.dispose();
    super.dispose();
  }

  void _selectAvatar(int index) {
    if (_selectedAvatarIndex == index) return;
    HapticFeedback.selectionClick();
    setState(() {
      _selectedAvatarIndex = index;
      _selectedBorder = AvatarBorderStyle.simple;
    });
    _bounceController.forward(from: 0);
  }

  void _selectBorder(AvatarBorderStyle border) {
    // Only allow selecting border if it's unlocked (simple is always free)
    if (border == AvatarBorderStyle.bold && !_unlockedBorderIds.contains('bold')) {
      _showLockedToast('Bold border unlocks at Level 3');
      return;
    }
    if (border == AvatarBorderStyle.arc && !_unlockedBorderIds.contains('arc')) {
      _showLockedToast('Arc border unlocks at Level 7');
      return;
    }
    if (_selectedBorder == border) return;
    HapticFeedback.selectionClick();
    setState(() => _selectedBorder = border);
  }

  void _showLockedToast(String message) {
    HapticFeedback.lightImpact();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.lock_rounded, color: Colors.white, size: 16),
            const SizedBox(width: 8),
            Text(message),
          ],
        ),
        backgroundColor: const Color(0xFF534AB7),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _confirm() async {
    HapticFeedback.mediumImpact();
    setState(() => _isSaving = true);

    try {
      // ── Onboarding flow — no user exists yet, just pass data back ──────
      if (widget.onCompleteWithData != null) {
        widget.onCompleteWithData!(_selected.id, _selectedBorder.name);
        return;
      }

      // ── Profile edit flow — user is authenticated ────────────────────
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) throw Exception('Not authenticated');

      await Supabase.instance.client.from('user_profiles').update({
        'avatar_id': _selected.id,
        'avatar_border': _selectedBorder.name,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', userId);
      
      widget.onComplete!();
    } catch (e) {
      debugPrint('❌ Avatar save failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to save — please try again')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  // ── Build ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(24, widget.showHeader ? 20 : 8, 24, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.showHeader) ...[
            _buildHeader(),
            const SizedBox(height: 28),
          ],
          _buildStarterRow(),
          const SizedBox(height: 24),
          _buildDetailCard(),
          const SizedBox(height: 28),
          _buildEarnableSection(),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Your profile icon',
          style: Theme.of(context)
              .textTheme
              .headlineSmall
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 6),
        Text(
          'Pick your icon — unlock more as you level up',
          style: TextStyle(fontSize: 14, color: Colors.grey[600]),
        ),
      ],
    );
  }

  Widget _buildStarterRow() {
    return Row(
      children: List.generate(_starters.length, (i) {
        final a = _starters[i];
        final isSelected = i == _selectedAvatarIndex;
        return Expanded(
          child: Padding(
            padding: EdgeInsets.only(right: i < _starters.length - 1 ? 10 : 0),
            child: GestureDetector(
              onTap: () => _selectAvatar(i),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 4),
                decoration: BoxDecoration(
                  color: isSelected ? a.bgColor : Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: isSelected ? a.borderColor : Colors.grey[200]!,
                    width: isSelected ? 2 : 1.5,
                  ),
                ),
                child: Column(
                  children: [
                    _AvatarWithBorder(
                      emoji: a.emoji,
                      borderStyle: isSelected ? _selectedBorder : AvatarBorderStyle.simple,
                      borderColor: a.borderColor,
                      bgColor: a.bgColor,
                      size: 72,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      a.name,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: isSelected ? a.color : Colors.grey[600],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      }),
    );
  }

  Widget _buildDetailCard() {
    final a = _selected;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ScaleTransition(
                scale: _bounceAnim,
                child: _AvatarWithBorder(
                  emoji: a.emoji,
                  borderStyle: _selectedBorder,
                  borderColor: a.borderColor,
                  bgColor: a.bgColor,
                  size: 130,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(a.name,
                        style: const TextStyle(
                            fontSize: 22, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text(a.desc,
                        style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: a.traits
                          .map((t) => Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: a.bgColor,
                                  borderRadius: BorderRadius.circular(100),
                                ),
                                child: Text(t,
                                    style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                        color: a.color)),
                              ))
                          .toList(),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),
          const Divider(height: 1),
          const SizedBox(height: 14),

          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'BORDER STYLE',
              style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey[500],
                  letterSpacing: 0.8),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: AvatarBorderStyle.values.map((style) {
              final isOn = _selectedBorder == style;
              final label = style.name[0].toUpperCase() + style.name.substring(1);
              final isLocked = _isBorderLocked(style);
              return Expanded(
                child: Padding(
                  padding: EdgeInsets.only(
                      right: style != AvatarBorderStyle.arc ? 8 : 0),
                  child: GestureDetector(
                    onTap: () => _selectBorder(style),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(
                        color: isOn ? a.bgColor : Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isOn ? a.borderColor : Colors.grey[300]!,
                          width: isOn ? 2 : 1,
                        ),
                      ),
                      child: Column(
                        children: [
                          Stack(
                            alignment: Alignment.topRight,
                            children: [
                              Opacity(
                                opacity: isLocked ? 0.4 : 1.0,
                                child: _AvatarWithBorder(
                                  emoji: a.emoji,
                                  borderStyle: style,
                                  borderColor: a.borderColor,
                                  bgColor: a.bgColor,
                                  size: 72,
                                ),
                              ),
                              if (isLocked)
                                Container(
                                  padding: const EdgeInsets.all(2),
                                  decoration: const BoxDecoration(
                                      color: Colors.white,
                                      shape: BoxShape.circle),
                                  child: Icon(Icons.lock_rounded,
                                      size: 12, color: Colors.grey[400]),
                                ),
                            ],
                          ),
                          const SizedBox(height: 5),
                          Text(label,
                              style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: isLocked
                                      ? Colors.grey[400]
                                      : isOn
                                          ? a.color
                                          : Colors.grey[500])),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),

          const SizedBox(height: 16),

          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _isSaving ? null : _confirm,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF7F77DD),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
                elevation: 0,
              ),
              child: _isSaving
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : Text(
                      "I'm ${a.name} — let's go",
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w600),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  bool _isBorderLocked(AvatarBorderStyle style) {
    if (_loadingUnlocks) return false; // show as unlocked while loading
    return switch (style) {
      AvatarBorderStyle.simple => false,
      AvatarBorderStyle.bold   => !_unlockedBorderIds.contains('bold'),
      AvatarBorderStyle.arc    => !_unlockedBorderIds.contains('arc'),
    };
  }

  // ── Earnable section ────────────────────────────────────────────────────

  Widget _buildEarnableSection() {
    if (_loadingUnlocks) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionLabel('UNLOCK AS YOU LEVEL UP'),
          const SizedBox(height: 12),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
              childAspectRatio: 0.9,
            ),
            itemCount: _earnable.length,
            itemBuilder: (_, i) => _buildLockedCard(_earnable[i]),
          ),
        ],
      );
    }

    final unlocked = _earnable
        .where((e) => _unlockedAvatarIds.contains(e.id))
        .toList();
    final locked = _earnable
        .where((e) => !_unlockedAvatarIds.contains(e.id))
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Unlocked earnable avatars (if any)
        if (unlocked.isNotEmpty) ...[
          _sectionLabel('UNLOCKED'),
          const SizedBox(height: 12),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
              childAspectRatio: 0.9,
            ),
            itemCount: unlocked.length,
            itemBuilder: (_, i) => _buildUnlockedEarnableCard(unlocked[i]),
          ),
          const SizedBox(height: 24),
        ],

        // Still locked
        if (locked.isNotEmpty) ...[
          _sectionLabel('UNLOCK AS YOU LEVEL UP'),
          const SizedBox(height: 12),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
              childAspectRatio: 0.9,
            ),
            itemCount: locked.length,
            itemBuilder: (_, i) => _buildLockedCard(locked[i]),
          ),
        ],
      ],
    );
  }

  Widget _sectionLabel(String text) {
    return Text(
      text,
      style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: Colors.grey[500],
          letterSpacing: 0.8),
    );
  }

  /// Card for an avatar the user has unlocked (earnable, not a starter).
  /// Tapping it selects it as a starter-like option — we treat it as a
  /// virtual "starter" so the full detail card renders correctly.
  Widget _buildUnlockedEarnableCard(_EarnableAvatar e) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        // Save directly since earnable avatars don't go through the starter flow
        if (widget.onCompleteWithData == null) {
          _saveEarnableAvatar(e.id);
        } else {
          widget.onCompleteWithData!(e.id, _selectedBorder.name);
        }
      },
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFF7F77DD).withOpacity(0.4)),
          color: const Color(0xFFEEEDFE),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(e.emoji, style: const TextStyle(fontSize: 36)),
            const SizedBox(height: 5),
            Text(e.name,
                style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF534AB7))),
            const SizedBox(height: 2),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFF7F77DD),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text('USE',
                  style: TextStyle(
                      fontSize: 8,
                      fontWeight: FontWeight.w700,
                      color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _saveEarnableAvatar(String avatarId) async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;
    try {
      await Supabase.instance.client.from('user_profiles').update({
        'avatar_id': avatarId,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', userId);
      widget.onComplete?.call();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to save — please try again')),
        );
      }
    }
  }

  Widget _buildLockedCard(_EarnableAvatar l) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey[200]!),
        color: Colors.grey[50],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Stack(
            alignment: Alignment.bottomRight,
            children: [
              Opacity(
                opacity: 0.35,
                child: Text(l.emoji, style: const TextStyle(fontSize: 36)),
              ),
              Container(
                padding: const EdgeInsets.all(2),
                decoration: const BoxDecoration(
                    color: Colors.white, shape: BoxShape.circle),
                child: Icon(Icons.lock_rounded,
                    size: 14, color: Colors.grey[400]),
              ),
            ],
          ),
          const SizedBox(height: 5),
          Text(l.name,
              style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey[500])),
          const SizedBox(height: 2),
          Text(l.req,
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 8, color: Colors.grey[400], height: 1.3)),
        ],
      ),
    );
  }
}

// ── Avatar with border renderer ─────────────────────────────────────────────
class _AvatarWithBorder extends StatelessWidget {
  final String emoji;
  final AvatarBorderStyle borderStyle;
  final Color borderColor;
  final Color bgColor;
  final double size;

  const _AvatarWithBorder({
    required this.emoji,
    required this.borderStyle,
    required this.borderColor,
    required this.bgColor,
    required this.size,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(size, size),
      foregroundPainter: _BorderPainter(borderStyle, borderColor),
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(shape: BoxShape.circle, color: bgColor),
        child: Center(
          child: Text(emoji, style: TextStyle(fontSize: size * 0.48)),
        ),
      ),
    );
  }
}

class _BorderPainter extends CustomPainter {
  final AvatarBorderStyle style;
  final Color color;
  _BorderPainter(this.style, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    switch (style) {
      case AvatarBorderStyle.simple:
        paint.strokeWidth = size.width * 0.06;
        final r = size.width / 2 - paint.strokeWidth / 2 - 1;
        canvas.drawCircle(c, r, paint);
        break;
      case AvatarBorderStyle.bold:
        paint.strokeWidth = size.width * 0.13;
        final r = size.width / 2 - paint.strokeWidth / 2 - 1;
        canvas.drawCircle(c, r, paint);
        paint
          ..strokeWidth = size.width * 0.03
          ..color = color.withOpacity(0.4);
        canvas.drawCircle(c, r - size.width * 0.10, paint);
        break;
      case AvatarBorderStyle.arc:
        paint.strokeWidth = size.width * 0.07;
        final r = size.width / 2 - paint.strokeWidth / 2 - 1;
        final rect = Rect.fromCircle(center: c, radius: r);
        canvas.drawArc(rect, -2.36, 4.71, false, paint);
        paint
          ..style = PaintingStyle.fill
          ..color = color.withOpacity(0.5);
        final capR = paint.strokeWidth * 0.5;
        canvas.drawCircle(
            Offset(c.dx - r * 0.71, c.dy + r * 0.71), capR, paint);
        canvas.drawCircle(
            Offset(c.dx + r * 0.71, c.dy + r * 0.71), capR, paint);
        break;
    }
  }

  @override
  bool shouldRepaint(_BorderPainter old) =>
      old.style != style || old.color != color;
}

// ── Data models ─────────────────────────────────────────────────────────────
class _AvatarOption {
  final String id;
  final String emoji;
  final String name;
  final String desc;
  final List<String> traits;
  final Color color;
  final Color bgColor;
  final Color borderColor;

  const _AvatarOption({
    required this.id,
    required this.emoji,
    required this.name,
    required this.desc,
    required this.traits,
    required this.color,
    required this.bgColor,
    required this.borderColor,
  });
}

class _EarnableAvatar {
  final String id;
  final String emoji;
  final String name;
  final String req;
  const _EarnableAvatar({
    required this.id,
    required this.emoji,
    required this.name,
    required this.req,
  });
}