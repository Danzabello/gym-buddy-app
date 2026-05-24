// lib/widgets/profile_view_dialog.dart
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../theme/app_theme.dart';
import 'user_avatar.dart';

class ProfileViewDialog extends StatefulWidget {
  final Map<String, dynamic> friendProfile;
  const ProfileViewDialog({super.key, required this.friendProfile});

  @override
  State<ProfileViewDialog> createState() => _ProfileViewDialogState();
}

class _ProfileViewDialogState extends State<ProfileViewDialog> {
  List<Map<String, dynamic>> _sharedStreaks = [];
  bool _isLoadingStreaks = true;

  String _checkInFrequency = '—';
  bool _isNewUser = false;

  static const Map<String, Color> _borderColors = {
    'gold':   Color(0xFFFBBF24),
    'purple': Color(0xFF7C3AED),
    'blue':   Color(0xFF3B82F6),
    'green':  Color(0xFF10B981),
    'orange': Color(0xFFF97316),
    'red':    Color(0xFFEF4444),
    'pink':   Color(0xFFEC4899),
    'teal':   Color(0xFF14B8A6),
  };

  @override
  void initState() {
    super.initState();
    _loadSharedStreaks();
    _loadCheckInFrequency();
  }

  // ── Real check-in frequency (last 30 days) ──────────────
  Future<void> _loadCheckInFrequency() async {
    try {
      final friendId = widget.friendProfile['id'] as String?;
      if (friendId == null) return;

      final now = DateTime.now().toUtc();
      final thirtyDaysAgo = now.subtract(const Duration(days: 30));
      final thirtyDaysAgoStr =
          thirtyDaysAgo.toIso8601String().split('T')[0];

      // Get join date to handle new users
      final profileData = await Supabase.instance.client
          .from('user_profiles')
          .select('created_at')
          .eq('id', friendId)
          .maybeSingle();

      DateTime? joinedAt;
      if (profileData?['created_at'] != null) {
        joinedAt = DateTime.tryParse(
            profileData!['created_at'] as String);
      }

      final daysOnApp =
          joinedAt != null ? now.difference(joinedAt).inDays : 30;

      // New user < 14 days — don't show misleading avg
      if (daysOnApp < 14) {
        if (mounted) {
          setState(() {
            _checkInFrequency = 'New';
            _isNewUser = true;
          });
        }
        return;
      }

      // Count distinct check-in dates in last 30 days
      final rows = await Supabase.instance.client
          .from('daily_team_checkins')
          .select('check_in_date')
          .eq('user_id', friendId)
          .gte('check_in_date', thirtyDaysAgoStr);

      final distinctDates = <String>{};
      for (final r in rows) {
        final d = r['check_in_date'] as String?;
        if (d != null) distinctDates.add(d);
      }

      final windowDays = daysOnApp.clamp(1, 30);
      final weeksInWindow = windowDays / 7.0;
      final avgPerWeek = distinctDates.length / weeksInWindow;

      String label;
      if (distinctDates.isEmpty) {
        label = '0 days/wk · last 30d';
      } else if (avgPerWeek < 1) {
        label = '< 1 day/wk · last 30d';
      } else {
        label = '${avgPerWeek.round()} days/wk · last 30d';
      }

      if (mounted) {
        setState(() {
          _checkInFrequency = label;
          _isNewUser = false;
        });
      }
    } catch (e) {
      // Fallback to onboarding value silently
      if (mounted) {
        final fallback =
            widget.friendProfile['workout_days_per_week'];
        setState(() {
          _checkInFrequency =
              fallback != null ? '$fallback days/wk' : '—';
        });
      }
    }
  }

  // ── Shared streaks ───────────────────────────────────────
  Future<void> _loadSharedStreaks() async {
    try {
      final currentUserId =
          Supabase.instance.client.auth.currentUser?.id;
      if (currentUserId == null) return;

      final myTeams = await Supabase.instance.client
          .from('team_members')
          .select('team_id')
          .eq('user_id', currentUserId);

      final friendTeams = await Supabase.instance.client
          .from('team_members')
          .select('team_id')
          .eq('user_id', widget.friendProfile['id']);

      final myIds = myTeams.map((t) => t['team_id']).toSet();
      final friendIds =
          friendTeams.map((t) => t['team_id']).toSet();
      final sharedIds = myIds.intersection(friendIds).toList();

      final streaks = <Map<String, dynamic>>[];
      for (final teamId in sharedIds) {
        final teamInfo = await Supabase.instance.client
            .from('buddy_teams')
            .select('id, team_name, team_emoji, is_coach_max_team')
            .eq('id', teamId)
            .single();

        if (teamInfo['is_coach_max_team'] == true) continue;

        final streakInfo = await Supabase.instance.client
            .from('team_streaks')
            .select('current_streak, longest_streak, is_active')
            .eq('team_id', teamId)
            .eq('is_active', true)
            .maybeSingle();

        if (streakInfo != null) {
          streaks.add({
            'team_name': teamInfo['team_name'],
            'team_emoji': teamInfo['team_emoji'],
            'current_streak': streakInfo['current_streak'],
            'longest_streak': streakInfo['longest_streak'],
          });
        }
      }

      if (mounted) {
        setState(() {
          _sharedStreaks = streaks;
          _isLoadingStreaks = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoadingStreaks = false);
    }
  }

  Color _borderColor(String? key) =>
      _borderColors[key] ??
      const Color(0xFF6B7280).withOpacity(0.4);

  // ── Build ────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final appColors = AppColors.of(context);
    final cs = Theme.of(context).colorScheme;
    final displayName =
        widget.friendProfile['display_name'] ?? 'Unknown';
    final username =
        widget.friendProfile['username'] as String? ?? '';
    final fitnessLevel =
        _formatLevel(widget.friendProfile['fitness_level']);
    final borderColor =
        _borderColor(widget.friendProfile['avatar_border'] as String?);

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding:
          const EdgeInsets.symmetric(horizontal: 28, vertical: 40),
      child: Container(
        decoration: BoxDecoration(
          color: appColors.cardBackground,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color: appColors.cardBorder, width: 0.5),
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── Gradient header ──────────────────────────
              Container(
                padding:
                    const EdgeInsets.fromLTRB(16, 20, 16, 16),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Color(0xFF1D4ED8),
                      Color(0xFF7C3AED)
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.vertical(
                      top: Radius.circular(20)),
                ),
                child: Stack(
                  children: [
                    // Avatar + name centred
                    Align(
                      alignment: Alignment.center,
                      child: Column(
                        children: [
                          Container(
                            width: 72,
                            height: 72,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                  color: borderColor, width: 3),
                            ),
                            child: ClipOval(
                              child: UserAvatar(
                                avatarId: widget
                                    .friendProfile['avatar_id'],
                                size: 66,
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            displayName,
                            style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                                letterSpacing: -0.3),
                          ),
                          if (username.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text('@$username',
                                style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.white
                                        .withOpacity(0.65))),
                          ],
                        ],
                      ),
                    ),
                    // Close X
                    Positioned(
                      top: 0,
                      right: 0,
                      child: GestureDetector(
                        onTap: () => Navigator.pop(context),
                        child: Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            color:
                                Colors.white.withOpacity(0.15),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.close,
                              size: 14, color: Colors.white),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // ── Stats grid ───────────────────────────────
              Padding(
                padding:
                    const EdgeInsets.fromLTRB(14, 14, 14, 0),
                child: Row(children: [
                  Expanded(
                    child: _statTile(
                      icon: '📅',
                      label: _isNewUser
                          ? 'Just joined'
                          : 'Avg check-ins',
                      value: _checkInFrequency,
                      appColors: appColors,
                      cs: cs,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: _statTile(
                      icon: '💪',
                      label: 'Fitness level',
                      value: fitnessLevel,
                      appColors: appColors,
                      cs: cs,
                    ),
                  ),
                ]),
              ),

              // ── Shared streak section ────────────────────
              Padding(
                padding:
                    const EdgeInsets.fromLTRB(14, 14, 14, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _sectionHeader('Shared streak', appColors),
                    const SizedBox(height: 8),
                    _isLoadingStreaks
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: CircularProgressIndicator(
                                  color: cs.primary,
                                  strokeWidth: 2),
                            ),
                          )
                        : _sharedStreaks.isEmpty
                            ? Padding(
                                padding:
                                    const EdgeInsets.symmetric(
                                        vertical: 12),
                                child: Center(
                                  child: Text(
                                    'No shared streaks yet',
                                    style: TextStyle(
                                        fontSize: 13,
                                        color:
                                            appColors.subtleText),
                                  ),
                                ),
                              )
                            : Column(
                                children: _sharedStreaks
                                    .map((s) => _streakCard(
                                        s, appColors, cs))
                                    .toList(),
                              ),
                  ],
                ),
              ),

              // ── Close button ─────────────────────────────
              Padding(
                padding: const EdgeInsets.all(14),
                child: GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                        vertical: 14),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [
                          Color(0xFF1D4ED8),
                          Color(0xFF7C3AED)
                        ],
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Center(
                      child: Text('Close',
                          style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: Colors.white)),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _statTile({
    required String icon,
    required String label,
    required String value,
    required AppColors appColors,
    required ColorScheme cs,
  }) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: appColors.sectionBackground,
        borderRadius: BorderRadius.circular(10),
        border:
            Border.all(color: appColors.cardBorder, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(icon, style: const TextStyle(fontSize: 16)),
          const SizedBox(height: 4),
          Text(label,
              style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5,
                  color: appColors.subtleText)),
          const SizedBox(height: 2),
          Text(value,
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: cs.onSurface)),
        ],
      ),
    );
  }

  Widget _sectionHeader(String label, AppColors appColors) {
    return Row(children: [
      Expanded(
          child: Container(
              height: 0.5, color: appColors.divider)),
      const SizedBox(width: 8),
      Text(label.toUpperCase(),
          style: TextStyle(
              fontSize: 8,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
              color: appColors.subtleText)),
      const SizedBox(width: 8),
      Expanded(
          child: Container(
              height: 0.5, color: appColors.divider)),
    ]);
  }

  Widget _streakCard(Map<String, dynamic> streak,
      AppColors appColors, ColorScheme cs) {
    final current = streak['current_streak'] as int? ?? 0;
    final longest = streak['longest_streak'] as int? ?? 0;
    final emoji = streak['team_emoji'] as String? ?? '💪';
    final name =
        streak['team_name'] as String? ?? 'Shared streak';

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: appColors.sectionBackground,
        borderRadius: BorderRadius.circular(10),
        border:
            Border.all(color: appColors.cardBorder, width: 0.5),
      ),
      child: Row(children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color:
                const Color(0xFFF97316).withOpacity(0.12),
            shape: BoxShape.circle,
            border: Border.all(
                color:
                    const Color(0xFFF97316).withOpacity(0.2),
                width: 0.5),
          ),
          child: Center(
              child: Text(emoji,
                  style: const TextStyle(fontSize: 18))),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(name,
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: cs.onSurface),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
              Text('Best: $longest days',
                  style: TextStyle(
                      fontSize: 9,
                      color: appColors.subtleText)),
            ],
          ),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text('$current',
                style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -1,
                    color: Color(0xFFF97316))),
            Text('day streak',
                style: TextStyle(
                    fontSize: 8,
                    color: appColors.subtleText)),
          ],
        ),
      ]),
    );
  }

  String _formatLevel(dynamic level) {
    switch (level?.toString().toUpperCase()) {
      case 'BEGINNER':     return 'Beginner';
      case 'INTERMEDIATE': return 'Intermediate';
      case 'ADVANCED':     return 'Advanced';
      case 'EXPERT':       return 'Expert';
      default:
        return level?.toString() ?? 'Beginner';
    }
  }
}