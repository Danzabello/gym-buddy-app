// lib/widgets/friends_page_modern.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/friend_service.dart';
import '../services/nudge_service.dart';
import '../services/achievement_service.dart';
import '../theme/app_theme.dart';
import 'user_avatar.dart';
import 'profile_view_dialog.dart';
import 'schedule_workout_sheet.dart';
import 'achievement_toast.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/invite_service.dart';
import '../services/team_streak_service.dart';
import '../services/presence_service.dart';

class FriendsPageModern extends StatefulWidget {
  const FriendsPageModern({super.key});

  @override
  State<FriendsPageModern> createState() => _FriendsPageModernState();
}

class _FriendsPageModernState extends State<FriendsPageModern> {
  final FriendService _friendService = FriendService();
  final NudgeService _nudgeService = NudgeService();

  List<Map<String, dynamic>> _friends = [];
  List<Map<String, dynamic>> _pendingRequests = []; // count only → + badge

  // Which friend IDs have been checked in today
  Set<String> _checkedInToday = {};
  // Which friend IDs have already been nudged today
  Set<String> _nudgedToday = {};
  // Friend IDs currently being nudged (loading state)
  Set<String> _nudging = {};

  // buddy userId → our shared team streak (for search-page sublines/sort)
  Map<String, TeamStreak> _buddyStreaks = {};

  bool _isLoading = true;
  String? _removingFriendId;

  // ── Border colour map ─────────────────────────────────────
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
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);

    final friends = await _friendService.getFriends();
    final pending = await _friendService.getPendingRequests();

    // Load today's check-ins for all friends in parallel
    final friendIds = friends.map((f) => f['id'] as String).toList();
    final checkedIn = await _getCheckedInToday(friendIds);
    final nudged = await _nudgeService.getNudgedTodaySet(friendIds);
    final buddyStreaks = await _loadBuddyStreaks();

    if (!mounted) return;
    setState(() {
      _friends = friends;
      _pendingRequests = pending;
      _checkedInToday = checkedIn;
      _nudgedToday = nudged;
      _buddyStreaks = buddyStreaks;
      _isLoading = false;
    });
  }

  // Map each buddy's userId → our shared team streak (skips Coach Max).
  // Reuses the dashboard's service — no new query or FriendService change.
  Future<Map<String, TeamStreak>> _loadBuddyStreaks() async {
    try {
      final me = Supabase.instance.client.auth.currentUser?.id;
      final streaks = await TeamStreakService().getAllUserStreaks();
      final map = <String, TeamStreak>{};
      for (final s in streaks) {
        if (s.isCoachMaxTeam) continue;
        for (final m in s.members) {
          if (m.userId != me) map[m.userId] = s;
        }
      }
      return map;
    } catch (_) {
      return {};
    }
  }

  Future<Set<String>> _getCheckedInToday(List<String> friendIds) async {
    if (friendIds.isEmpty) return {};
    try {
      final now = DateTime.now();
      final today =
          '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      final supabase = Supabase.instance.client;
      final rows = await supabase
          .from('daily_team_checkins')
          .select('user_id')
          .eq('check_in_date', today)
          .inFilter('user_id', friendIds);
      return {for (final r in rows) r['user_id'] as String};
    } catch (_) {
      return {};
    }
  }

  // ── Separated buddy lists ─────────────────────────────────
  List<Map<String, dynamic>> get _checkedInFriends =>
      _friends.where((f) => _checkedInToday.contains(f['id'])).toList();

  List<Map<String, dynamic>> get _notCheckedInFriends =>
      _friends.where((f) => !_checkedInToday.contains(f['id'])).toList();

  // ── Nudge ─────────────────────────────────────────────────
  Future<void> _nudge(Map<String, dynamic> friend) async {
    final id = friend['id'] as String;
    final name = friend['display_name'] as String? ?? 'your buddy';

    setState(() => _nudging.add(id));

    final result = await _nudgeService.sendNudge(
      targetUserId: id,
      targetDisplayName: name,
    );

    setState(() {
      _nudging.remove(id);
      if (result == NudgeResult.sent) _nudgedToday.add(id);
    });

    if (!mounted) return;

    switch (result) {
      case NudgeResult.sent:
        HapticFeedback.mediumImpact();
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Nudge sent to $name! 🔔'),
          backgroundColor: const Color(0xFF10B981),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10)),
        ));
        break;
      case NudgeResult.alreadySent:
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Already nudged $name today'),
          backgroundColor: AppColors.of(context).subtleText,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10)),
        ));
        break;
      case NudgeResult.tooEarly:
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Too early to nudge — try after 10am'),
          backgroundColor: Color(0xFFF97316),
          behavior: SnackBarBehavior.floating,
        ));
        break;
      case NudgeResult.error:
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Failed to send nudge'),
          backgroundColor: Color(0xFFEF4444),
          behavior: SnackBarBehavior.floating,
        ));
        break;
    }
  }

  Future<void> _removeFriend(
      String friendId, String friendName) async {
    final appColors = AppColors.of(context);
    final cs = Theme.of(context).colorScheme;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: appColors.cardBackground,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20)),
        title: Column(children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFF97316).withOpacity(0.12),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.warning_amber_rounded,
                color: Color(0xFFF97316), size: 28),
          ),
          const SizedBox(height: 12),
          Text('Remove Buddy?',
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: cs.onSurface)),
        ]),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Are you sure you want to remove $friendName?',
                textAlign: TextAlign.center,
                style: TextStyle(color: appColors.subtleText)),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFEF4444).withOpacity(0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: const Color(0xFFEF4444).withOpacity(0.2),
                    width: 0.5),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    const Icon(Icons.info_outline,
                        size: 15, color: Color(0xFFEF4444)),
                    const SizedBox(width: 6),
                    Text('This will:',
                        style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: cs.onSurface,
                            fontSize: 13)),
                  ]),
                  const SizedBox(height: 8),
                  _consequenceRow(Icons.timeline, 'Delete your shared streak'),
                  const SizedBox(height: 5),
                  _consequenceRow(
                      Icons.person_remove, 'Remove them from buddies'),
                  const SizedBox(height: 5),
                  _consequenceRow(Icons.history, 'Delete workout history'),
                ],
              ),
            ),
          ],
        ),
        actionsPadding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        actions: [
          Row(children: [
            Expanded(
              child: GestureDetector(
                onTap: () => Navigator.pop(context, false),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: appColors.cardBorder, width: 0.5),
                  ),
                  child: Center(
                      child: Text('Cancel',
                          style: TextStyle(
                              color: appColors.subtleText,
                              fontWeight: FontWeight.w600))),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: GestureDetector(
                onTap: () => Navigator.pop(context, true),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEF4444),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Center(
                      child: Text('Remove',
                          style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800))),
                ),
              ),
            ),
          ]),
        ],
      ),
    );

    if (confirmed != true) return;
    setState(() => _removingFriendId = friendId);
    await _friendService.removeFriend(friendId);
    setState(() => _removingFriendId = null);
    await _load();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Removed $friendName'),
        backgroundColor: const Color(0xFF10B981),
        behavior: SnackBarBehavior.floating,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ));
    }
  }

  Widget _consequenceRow(IconData icon, String text) {
    return Row(children: [
      Icon(icon, size: 14, color: const Color(0xFFEF4444)),
      const SizedBox(width: 8),
      Expanded(
          child: Text(text,
              style: const TextStyle(
                  fontSize: 12, color: Color(0xFFEF4444)))),
    ]);
  }

  Future<void> _shareInviteLink() async {
    HapticFeedback.mediumImpact();
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Row(children: [
        SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
                strokeWidth: 2, color: Colors.white)),
        SizedBox(width: 12),
        Text('Generating invite link...'),
      ]),
      duration: Duration(seconds: 10),
      behavior: SnackBarBehavior.floating,
    ));
    final link = await InviteService().createInviteLink();
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    if (link == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Failed to generate link. Try again!'),
        backgroundColor: Color(0xFFEF4444),
        behavior: SnackBarBehavior.floating,
      ));
      return;
    }
    await SharePlus.instance.share(ShareParams(
      text:
          '💪 Join me on Gym Buddy! We\'ll keep each other accountable and build streaks together.\n\n$link',
      subject: 'Join me on Gym Buddy!',
    ));
  }

  // ── Open chat (tap a buddy) → single touchpoint below. ──
  void _openChat(Map<String, dynamic> friend) =>
      _openBuddyChat(context, friend);

  // ══════════════════════════════════════════════════════════
  // BUDDY OPTIONS SHEET (long-press)
  // ══════════════════════════════════════════════════════════
  void _showBuddySheet(Map<String, dynamic> friend) {
    final appColors = AppColors.of(context);
    final cs = Theme.of(context).colorScheme;
    final id = friend['id'] as String;
    final name = friend['display_name'] as String? ?? 'Buddy';
    final checkedIn = _checkedInToday.contains(id);
    final borderColor = _borderColor(friend['avatar_border'] as String?);

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => Container(
        decoration: BoxDecoration(
          color: appColors.cardBackground,
          borderRadius:
              const BorderRadius.vertical(top: Radius.circular(20)),
          border: Border.all(color: appColors.cardBorder, width: 0.5),
        ),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 36),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle
            Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                  color: appColors.divider,
                  borderRadius: BorderRadius.circular(2)),
            ),
            // User row
            Row(children: [
              _avatarWidget(friend, 44, borderColor),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name,
                        style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: cs.onSurface)),
                    Text(
                        '${friend['fitness_level']?.toString().toUpperCase() ?? 'BEGINNER'}',
                        style: TextStyle(
                            fontSize: 11,
                            color: appColors.subtleText)),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: checkedIn
                      ? const Color(0xFF10B981).withOpacity(0.12)
                      : const Color(0xFFF97316).withOpacity(0.12),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                      color: checkedIn
                          ? const Color(0xFF10B981).withOpacity(0.25)
                          : const Color(0xFFF97316).withOpacity(0.25),
                      width: 0.5),
                ),
                child: Text(
                  checkedIn ? '✓ Checked in' : 'Not checked in',
                  style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: checkedIn
                          ? const Color(0xFF10B981)
                          : const Color(0xFFF97316)),
                ),
              ),
            ]),
            const SizedBox(height: 20),
            // Action rows
            _sheetAction(
              icon: Icons.chat_bubble_outline,
              iconBg: const Color(0xFF3B82F6).withOpacity(0.12),
              iconColor: const Color(0xFF3B82F6),
              label: 'Message',
              subtitle: 'Open your chat',
              onTap: () {
                Navigator.pop(context);
                _openChat(friend);
              },
              appColors: appColors,
              cs: cs,
            ),
            _sheetDivider(appColors),
            _sheetAction(
              icon: Icons.fitness_center_outlined,
              iconBg: const Color(0xFFF97316).withOpacity(0.12),
              iconColor: const Color(0xFFF97316),
              label: 'Invite to workout',
              subtitle: 'Schedule a session together',
              onTap: () {
                Navigator.pop(context);
                ScheduleWorkoutSheet.show(
                  context,
                  buddyId: friend['id'] as String?,
                  buddyName: friend['display_name'] as String?,
                );
              },
              appColors: appColors,
              cs: cs,
            ),
            _sheetDivider(appColors),
            _sheetAction(
              icon: Icons.person_outline,
              iconBg: const Color(0xFF7C3AED).withOpacity(0.12),
              iconColor: const Color(0xFF7C3AED),
              label: 'View profile',
              subtitle: 'Stats, achievements & history',
              onTap: () {
                Navigator.pop(context);
                showDialog(
                  context: context,
                  builder: (_) =>
                      ProfileViewDialog(friendProfile: friend),
                );
              },
              appColors: appColors,
              cs: cs,
            ),
            _sheetDivider(appColors),
            _sheetAction(
              icon: Icons.person_remove_outlined,
              iconBg: const Color(0xFFEF4444).withOpacity(0.10),
              iconColor: const Color(0xFFEF4444),
              label: 'Remove buddy',
              subtitle: 'Deletes your shared streak',
              labelColor: const Color(0xFFEF4444),
              onTap: () {
                Navigator.pop(context);
                _removeFriend(id, name);
              },
              appColors: appColors,
              cs: cs,
            ),
          ],
        ),
      ),
    );
  }

  Widget _sheetAction({
    required IconData icon,
    required Color iconBg,
    required Color iconColor,
    required String label,
    required String subtitle,
    required VoidCallback? onTap,
    required AppColors appColors,
    required ColorScheme cs,
    Color? labelColor,
    bool disabled = false,
  }) {
    return GestureDetector(
      onTap: disabled ? null : onTap,
      child: Opacity(
        opacity: disabled ? 0.45 : 1.0,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 11),
          child: Row(children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                  color: iconBg, borderRadius: BorderRadius.circular(10)),
              child: Icon(icon, color: iconColor, size: 18),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: labelColor ?? cs.onSurface)),
                  Text(subtitle,
                      style: TextStyle(
                          fontSize: 11, color: appColors.subtleText)),
                ],
              ),
            ),
            Icon(Icons.chevron_right,
                color: disabled
                    ? Colors.transparent
                    : appColors.subtleText,
                size: 18),
          ]),
        ),
      ),
    );
  }

  Widget _sheetDivider(AppColors appColors) =>
      Divider(height: 1, color: appColors.divider);

  // ══════════════════════════════════════════════════════════
  // MAIN BUILD
  // ══════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    final appColors = AppColors.of(context);
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.transparent,
        centerTitle: true,
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF1D4ED8), Color(0xFF7C3AED)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        // ── Left: search → opens dedicated finder page ──
        leading: IconButton(
          icon: const Icon(Icons.search, color: Colors.white),
          tooltip: 'Search buddies',
          onPressed: () {
            // Snapshot of who's working out right now — read only, never
            // touch the singleton's callback/join (that's the dashboard's).
            final ids = _friends.map((f) => f['id'] as String).toList();
            final workingOut = PresenceService()
                .getFriendsWorkingOut(ids)
                .map((p) => p['user_id'] as String)
                .toSet();
            Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => _SearchBuddiesPage(
                      friends: _friends,
                      streaks: _buddyStreaks,
                      workingOut: workingOut)),
            );
          },
        ),
        // ── Center: title ──
        title: const Text('Gym Buddies',
            style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: Colors.white,
                letterSpacing: -0.5)),
        // ── Right: add + requests (badge = pending count) ──
        actions: [
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.person_add_outlined,
                            color: Colors.white, size: 22),
                        tooltip: 'Add buddies & requests',
                        onPressed: () async {
                          await Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) => const _AddBuddiesPage()),
                          );
                          _load(); // refresh badge + any new buddies
                        },
                      ),
                      if (_pendingRequests.isNotEmpty)
                        Positioned(
                          right: 6,
                          top: 6,
                          child: Container(
                            padding: const EdgeInsets.all(2),
                            constraints: const BoxConstraints(
                                minWidth: 16, minHeight: 16),
                            decoration: BoxDecoration(
                              color: const Color(0xFFEF4444),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                  color: const Color(0xFF5B3CC4),
                                  width: 1.5),
                            ),
                            child: Center(
                              child: Text('${_pendingRequests.length}',
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 9,
                                      fontWeight: FontWeight.w800)),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator(color: cs.primary))
          : RefreshIndicator(
              onRefresh: _load,
              color: cs.primary,
              child: _buildBuddiesFeed(),
            ),
    );
  }

  // ══════════════════════════════════════════════════════════
  // BUDDIES FEED — activity feed layout
  // ══════════════════════════════════════════════════════════
  Widget _buildBuddiesFeed() {
    if (_friends.isEmpty) return _buildEmptyBuddies();

    final checkedIn = _checkedInFriends;
    final notChecked = _notCheckedInFriends;

    return ListView(
      padding: const EdgeInsets.only(bottom: 20),
      children: [
        // ── Summary tiles ──────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
          child: Row(children: [
            Expanded(
                child: _summaryTile(
              value: '${_checkedInFriends.length} / ${_friends.length}',
              label: 'Checked in today',
              color: const Color(0xFF10B981),
            )),
            const SizedBox(width: 6),
            Expanded(
                child: _summaryTile(
              value: '🔥 ${_bestStreak()}',
              label: 'Best streak',
              color: const Color(0xFFF97316),
            )),
          ]),
        ),

        // ── Not checked in section (at-risk first) ─────────
        if (notChecked.isNotEmpty) ...[
          _sectionDivider('Not checked in yet', context),
          ...notChecked.map((f) => _buddyCard(f, dimmed: true)),
        ],

        // ── Checked in section ─────────────────────────────
        if (checkedIn.isNotEmpty) ...[
          _sectionDivider('Checked in today', context),
          ...checkedIn.map((f) => _buddyCard(f, dimmed: false)),
        ],

        // ── Ghost invite link ──────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: _inviteGhost(),
        ),
      ],
    );
  }

  Widget _summaryTile({
    required String value,
    required String label,
    required Color color,
  }) {
    final appColors = AppColors.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: appColors.cardBackground,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: appColors.cardBorder, width: 0.5),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(value,
            style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w900,
                letterSpacing: -0.5,
                color: color)),
        const SizedBox(height: 2),
        Text(label.toUpperCase(),
            style: TextStyle(
                fontSize: 8,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.6,
                color: appColors.subtleText)),
      ]),
    );
  }

  Widget _sectionDivider(String label, BuildContext context) {
    final appColors = AppColors.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
      child: Row(children: [
        Expanded(child: Container(height: 0.5, color: appColors.divider)),
        const SizedBox(width: 8),
        Text(label.toUpperCase(),
            style: TextStyle(
                fontSize: 8,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.7,
                color: appColors.subtleText)),
        const SizedBox(width: 8),
        Expanded(child: Container(height: 0.5, color: appColors.divider)),
      ]),
    );
  }

  Widget _buddyCard(Map<String, dynamic> friend,
      {required bool dimmed}) {
    final appColors = AppColors.of(context);
    final cs = Theme.of(context).colorScheme;
    final id = friend['id'] as String;
    final name = friend['display_name'] as String? ?? 'Buddy';
    final isRemoving = _removingFriendId == id;
    final borderColor = _borderColor(friend['avatar_border'] as String?);
    final hasNudged = _nudgedToday.contains(id);
    final isNudging = _nudging.contains(id);

    return Opacity(
      opacity: dimmed ? 0.5 : 1.0,
      child: GestureDetector(
        onTap: () => _openChat(friend),
        onLongPress: () {
          HapticFeedback.mediumImpact();
          _showBuddySheet(friend);
        },
        child: Container(
          margin: const EdgeInsets.fromLTRB(12, 0, 12, 6),
          decoration: BoxDecoration(
            color: appColors.cardBackground,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: appColors.cardBorder, width: 0.5),
          ),
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Row(children: [
              _avatarWidget(friend, 40, borderColor),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name,
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: cs.onSurface)),
                    const SizedBox(height: 2),
                    Text(
                      dimmed ? 'Not checked in today' : 'Checked in today',
                      style: TextStyle(
                          fontSize: 9, color: appColors.subtleText),
                    ),
                    const SizedBox(height: 4),
                    // streak pill — extend getFriends() to include streak
                    // data later to show real numbers here
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: dimmed
                            ? appColors.sectionBackground
                            : const Color(0xFFF97316).withOpacity(0.12),
                        borderRadius: BorderRadius.circular(5),
                        border: Border.all(
                            color: dimmed
                                ? appColors.cardBorder
                                : const Color(0xFFF97316)
                                    .withOpacity(0.2),
                            width: 0.5),
                      ),
                      child: Text(
                        dimmed ? 'Streak at risk' : 'On streak 🔥',
                        style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w600,
                            color: dimmed
                                ? appColors.subtleText
                                : const Color(0xFFF97316)),
                      ),
                    ),
                  ],
                ),
              ),
              // Nudge button (only for not-checked-in)
              if (dimmed) ...[
                const SizedBox(width: 8),
                isRemoving
                    ? SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: cs.primary))
                    : GestureDetector(
                        onTap: isNudging || hasNudged
                            ? null
                            : () => _nudge(friend),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: hasNudged
                                ? appColors.sectionBackground
                                : const Color(0xFFF97316)
                                    .withOpacity(0.10),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                                color: hasNudged
                                    ? appColors.cardBorder
                                    : const Color(0xFFF97316)
                                        .withOpacity(0.3),
                                width: 0.5),
                          ),
                          child: Center(
                            child: isNudging
                                ? const SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Color(0xFFF97316)))
                                : Icon(
                                    hasNudged
                                        ? Icons.check
                                        : Icons.notifications_outlined,
                                    size: 17,
                                    color: hasNudged
                                        ? appColors.subtleText
                                        : const Color(0xFFF97316),
                                  ),
                          ),
                        ),
                      ),
              ] else ...[
                const SizedBox(width: 8),
                Icon(Icons.chevron_right,
                    color: appColors.subtleText, size: 18),
              ],
            ]),
          ),
        ),
      ),
    );
  }

  // ── Avatar with border ─────────────────────────────────────
  Widget _avatarWidget(
      Map<String, dynamic> friend, double size, Color borderColor) {
    final avatarId = friend['avatar_id'] as String?;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: borderColor, width: 2.5),
      ),
      child: ClipOval(
        child: UserAvatar(avatarId: avatarId, size: size - 5),
      ),
    );
  }

  Color _borderColor(String? borderKey) {
    if (borderKey == null) return const Color(0xFF6B7280).withOpacity(0.4);
    return _borderColors[borderKey] ??
        const Color(0xFF6B7280).withOpacity(0.4);
  }

  int _bestStreak() {
    // Placeholder until getFriends() returns streak data
    return 0;
  }

  // ── Subtle invite link at list end ─────────────────────────
  Widget _inviteGhost() {
    final appColors = AppColors.of(context);
    return GestureDetector(
      onTap: _shareInviteLink,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 13),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: appColors.cardBorder, width: 1),
        ),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.add, size: 18, color: appColors.subtleText),
          const SizedBox(width: 8),
          Text('Invite a friend',
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: appColors.subtleText)),
        ]),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════
  // EMPTY STATE
  // ══════════════════════════════════════════════════════════
  Widget _buildEmptyBuddies() {
    final appColors = AppColors.of(context);
    final cs = Theme.of(context).colorScheme;
    return ListView(
      // ListView so RefreshIndicator pull-to-refresh still works
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        SizedBox(
          height: MediaQuery.of(context).size.height * 0.6,
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(26),
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                          colors: [Color(0xFF1D4ED8), Color(0xFF7C3AED)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.group_add,
                        size: 52, color: Colors.white),
                  ),
                  const SizedBox(height: 20),
                  Text('No Gym Buddies Yet',
                      style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: cs.onSurface)),
                  const SizedBox(height: 10),
                  Text(
                    'Tap the + button to find buddies,\nor invite someone who isn\'t on the app yet!',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 14,
                        color: appColors.subtleText,
                        height: 1.5),
                  ),
                  const SizedBox(height: 28),
                  _inviteButton(),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _inviteButton() {
    return GestureDetector(
      onTap: _shareInviteLink,
      child: Container(
        decoration: BoxDecoration(
          gradient: const LinearGradient(
              colors: [Color(0xFF1D4ED8), Color(0xFF7C3AED)],
              begin: Alignment.centerLeft,
              end: Alignment.centerRight),
          borderRadius: BorderRadius.circular(14),
        ),
        padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 28),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.link, color: Colors.white, size: 18),
            SizedBox(width: 8),
            Text('Invite a Buddy',
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: Colors.white)),
          ],
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════
// Single touchpoint for opening a buddy chat. Messaging isn't
// built yet → stub. Swap the snackbar for a Navigator.push to
// your ChatPage when it ships; tap, search and the options
// sheet all route through here.
// ════════════════════════════════════════════════════════════
void _openBuddyChat(BuildContext context, Map<String, dynamic> friend) {
  HapticFeedback.selectionClick();
  final name = friend['display_name'] as String? ?? 'Buddy';
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content: Text('Chat with $name — coming soon! 💬'),
    behavior: SnackBarBehavior.floating,
    backgroundColor: AppColors.of(context).subtleText,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
  ));
  // TODO: Navigator.push(context,
  //   MaterialPageRoute(builder: (_) => ChatPage(buddy: friend)));
}

// ════════════════════════════════════════════════════════════
// SEARCH BUDDIES PAGE — find one of your buddies and message
// them. Reached via the search icon on the buddies header.
// ════════════════════════════════════════════════════════════
class _SearchBuddiesPage extends StatefulWidget {
  final List<Map<String, dynamic>> friends;
  final Map<String, TeamStreak> streaks;
  final Set<String> workingOut;
  const _SearchBuddiesPage(
      {required this.friends,
      required this.streaks,
      required this.workingOut});

  @override
  State<_SearchBuddiesPage> createState() => _SearchBuddiesPageState();
}

class _SearchBuddiesPageState extends State<_SearchBuddiesPage> {
  final TextEditingController _searchController = TextEditingController();
  String _query = '';

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
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> get _matches {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return widget.friends;
    return widget.friends.where((f) {
      final name = (f['display_name'] as String? ?? '').toLowerCase();
      final user = (f['username'] as String? ?? '').toLowerCase();
      return name.contains(q) || user.contains(q);
    }).toList();
  }

  Color _borderColor(String? key) {
    if (key == null) return const Color(0xFF6B7280).withOpacity(0.4);
    return _borderColors[key] ?? const Color(0xFF6B7280).withOpacity(0.4);
  }

  Widget _avatarWidget(
      Map<String, dynamic> friend, double size, Color borderColor) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: borderColor, width: 2.5),
      ),
      child: ClipOval(
        child: UserAvatar(avatarId: friend['avatar_id'], size: size - 5),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final appColors = AppColors.of(context);
    final cs = Theme.of(context).colorScheme;
    final matches = _matches;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.transparent,
        iconTheme: const IconThemeData(color: Colors.white),
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF1D4ED8), Color(0xFF7C3AED)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        title: const Text('Message a buddy',
            style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: Colors.white)),
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          // Search field
          Container(
            decoration: BoxDecoration(
              color: appColors.cardBackground,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: appColors.cardBorder, width: 0.5),
            ),
            child: TextField(
              controller: _searchController,
              autofocus: true,
              style: TextStyle(color: cs.onSurface, fontSize: 14),
              decoration: InputDecoration(
                hintText: 'Search your buddies...',
                hintStyle:
                    TextStyle(color: appColors.subtleText, fontSize: 14),
                prefixIcon: Icon(Icons.search,
                    color: appColors.subtleText, size: 20),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: Icon(Icons.clear,
                            color: appColors.subtleText, size: 18),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _query = '');
                        },
                      )
                    : null,
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 14),
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
          const SizedBox(height: 14),

          if (widget.friends.isEmpty)
            _hint(appColors, cs, Icons.group_outlined, 'No buddies yet',
                'Add buddies with the + button first')
          else if (matches.isEmpty)
            _hint(appColors, cs, Icons.search_off, 'No buddy matches',
                '"${_query.trim()}" isn\'t in your buddies')
          else if (_query.trim().isNotEmpty)
            ...matches.map((f) => _row(f, appColors, cs))
          else
            ..._sectioned(appColors, cs),
        ],
      ),
    );
  }

  // Buddies grouped: top streaks pinned as "Best buddies", rest below.
  List<Widget> _sectioned(AppColors appColors, ColorScheme cs) {
    final withStreak = widget.friends
        .where((f) => (_streakOf(f)?.currentStreak ?? 0) > 0)
        .toList()
      ..sort((a, b) =>
          _streakOf(b)!.currentStreak.compareTo(_streakOf(a)!.currentStreak));

    final best = withStreak.take(3).toList();
    final bestIds = best.map((f) => f['id']).toSet();
    final rest =
        widget.friends.where((f) => !bestIds.contains(f['id'])).toList();
    final topId = best.isNotEmpty ? best.first['id'] : null;

    final out = <Widget>[];
    if (best.isNotEmpty) {
      out.add(_sectionLabel('⭐ BEST BUDDIES', const Color(0xFFFBBF24),
          appColors));
      out.addAll(best
          .map((f) => _row(f, appColors, cs, isTop: f['id'] == topId)));
    }
    if (rest.isNotEmpty) {
      out.add(_sectionLabel(best.isEmpty ? 'YOUR BUDDIES' : 'ALL BUDDIES',
          appColors.subtleText, appColors));
      out.addAll(rest.map((f) => _row(f, appColors, cs)));
    }
    return out;
  }

  TeamStreak? _streakOf(Map<String, dynamic> friend) =>
      widget.streaks[friend['id'] as String];

  String? _lastTogether(TeamStreak? s) {
    final d = s?.lastWorkoutDate ?? s?.lastInteractionAt;
    if (d == null) return null;
    final days = DateTime.now().difference(d).inDays;
    if (days <= 0) return 'today';
    if (days == 1) return 'yesterday';
    if (days < 7) return '${days}d ago';
    final weeks = (days / 7).floor();
    return weeks == 1 ? '1w ago' : '${weeks}w ago';
  }

  Widget _sectionLabel(String text, Color color, AppColors appColors) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 4, 2, 10),
      child: Row(children: [
        Text(text,
            style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.9,
                color: color)),
        const SizedBox(width: 8),
        Expanded(child: Container(height: 0.5, color: appColors.divider)),
      ]),
    );
  }

  Widget _row(Map<String, dynamic> friend, AppColors appColors,
      ColorScheme cs,
      {bool isTop = false}) {
    final name = friend['display_name'] as String? ?? 'Buddy';
    final username = friend['username'] as String?;
    final streak = _streakOf(friend);
    final live = widget.workingOut.contains(friend['id'] as String);
    final borderColor = live
        ? const Color(0xFF22C55E)
        : isTop
            ? const Color(0xFFFBBF24)
            : _borderColor(friend['avatar_border'] as String?);

    Widget subline;
    if (live) {
      subline = const Text('🟢 Working out now',
          style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Color(0xFF22C55E)));
    } else if (streak != null && streak.currentStreak > 0) {
      subline = Text(
        isTop
            ? '🔥 ${streak.currentStreak}-day streak · top buddy'
            : '🔥 ${streak.currentStreak}-day streak',
        style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: Color(0xFFF97316)),
      );
    } else {
      final ago = _lastTogether(streak);
      if (ago != null) {
        subline = Text('Trained together $ago',
            style: TextStyle(fontSize: 11, color: appColors.subtleText));
      } else if (username != null) {
        subline = Text('@$username',
            style: TextStyle(fontSize: 11, color: appColors.subtleText));
      } else {
        subline = const SizedBox.shrink();
      }
    }

    return GestureDetector(
      onTap: () => _openBuddyChat(context, friend),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: appColors.cardBackground,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: appColors.cardBorder, width: 0.5),
        ),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                _avatarWidget(friend, 40, borderColor),
                if (isTop)
                  const Positioned(
                    top: -8,
                    right: -6,
                    child: Text('👑', style: TextStyle(fontSize: 13)),
                  ),
                if (live)
                  Positioned(
                    bottom: -1,
                    right: -1,
                    child: Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: const Color(0xFF22C55E),
                        shape: BoxShape.circle,
                        border: Border.all(
                            color: appColors.cardBackground, width: 2.5),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name,
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: cs.onSurface)),
                  const SizedBox(height: 2),
                  subline,
                ],
              ),
            ),
            const Icon(Icons.chat_bubble_outline,
                size: 18, color: Color(0xFF3B82F6)),
          ]),
        ),
      ),
    );
  }

  Widget _hint(AppColors appColors, ColorScheme cs, IconData icon,
      String title, String sub) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 50, 12, 12),
      child: Column(children: [
        Icon(icon, size: 52, color: appColors.subtleText),
        const SizedBox(height: 14),
        Text(title,
            style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: cs.onSurface)),
        const SizedBox(height: 6),
        Text(sub,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: appColors.subtleText)),
      ]),
    );
  }
}

// ════════════════════════════════════════════════════════════
// ADD BUDDIES PAGE — search for new users + handle requests
// Reached via the + button on the buddies header.
// ════════════════════════════════════════════════════════════
class _AddBuddiesPage extends StatefulWidget {
  const _AddBuddiesPage();

  @override
  State<_AddBuddiesPage> createState() => _AddBuddiesPageState();
}

class _AddBuddiesPageState extends State<_AddBuddiesPage> {
  final FriendService _friendService = FriendService();
  final TextEditingController _searchController = TextEditingController();

  List<Map<String, dynamic>> _pendingRequests = [];
  List<Map<String, dynamic>> _searchResults = [];

  bool _isLoading = true;
  bool _isSearching = false;
  String? _sendingRequestTo;
  String? _processingRequestId;

  @override
  void initState() {
    super.initState();
    _loadRequests();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadRequests() async {
    final pending = await _friendService.getPendingRequests();
    if (!mounted) return;
    setState(() {
      _pendingRequests = pending;
      _isLoading = false;
    });
  }

  Future<void> _searchUsers(String query) async {
    if (query.trim().isEmpty) {
      setState(() {
        _searchResults = [];
        _isSearching = false;
      });
      return;
    }
    setState(() => _isSearching = true);
    final results = await _friendService.searchUsers(query);
    if (!mounted) return;
    setState(() {
      _searchResults = results;
      _isSearching = false;
    });
  }

  Future<void> _sendFriendRequest(String friendId) async {
    setState(() => _sendingRequestTo = friendId);
    final success = await _friendService.sendFriendRequest(friendId);
    if (!mounted) return;
    setState(() => _sendingRequestTo = null);

    if (success) {
      HapticFeedback.mediumImpact();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Row(children: [
          Icon(Icons.check_circle, color: Colors.white),
          SizedBox(width: 12),
          Text('Friend request sent! 🎉'),
        ]),
        backgroundColor: Color(0xFF10B981),
        behavior: SnackBarBehavior.floating,
      ));
      _searchController.clear();
      setState(() => _searchResults = []);
      final results =
          await AchievementService().checkConnectorAchievement();
      if (mounted) AchievementToast.show(context, results);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Already friends or request pending'),
        backgroundColor: Color(0xFFF97316),
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  Future<void> _acceptRequest(String requestId) async {
    setState(() => _processingRequestId = requestId);
    final success = await _friendService.acceptFriendRequest(requestId);
    if (!mounted) return;
    setState(() => _processingRequestId = null);

    if (success) {
      HapticFeedback.heavyImpact();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Row(children: [
          Icon(Icons.celebration, color: Colors.white),
          SizedBox(width: 12),
          Text('Buddy added! 🎉'),
        ]),
        backgroundColor: Color(0xFF10B981),
        behavior: SnackBarBehavior.floating,
      ));
      await _loadRequests();
      final results =
          await AchievementService().checkSocialAchievements();
      if (mounted) AchievementToast.show(context, results);
    }
  }

  Future<void> _declineRequest(String requestId) async {
    final appColors = AppColors.of(context);
    final cs = Theme.of(context).colorScheme;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: appColors.cardBackground,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20)),
        title:
            Text('Decline request', style: TextStyle(color: cs.onSurface)),
        content: Text(
            'Are you sure you want to decline this buddy request?',
            style: TextStyle(color: appColors.subtleText)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel',
                style: TextStyle(color: appColors.subtleText)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Decline',
                style: TextStyle(color: Color(0xFFEF4444))),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _processingRequestId = requestId);
    await _friendService.declineFriendRequest(requestId);
    if (!mounted) return;
    setState(() => _processingRequestId = null);
    _loadRequests();
  }

  @override
  Widget build(BuildContext context) {
    final appColors = AppColors.of(context);
    final cs = Theme.of(context).colorScheme;
    final searching = _searchController.text.trim().isNotEmpty;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.transparent,
        iconTheme: const IconThemeData(color: Colors.white),
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF1D4ED8), Color(0xFF7C3AED)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        title: const Text('Add buddies',
            style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: Colors.white)),
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator(color: cs.primary))
          : ListView(
              padding: const EdgeInsets.all(12),
              children: [
                // ── Search-for-new-users field ──
                Container(
                  decoration: BoxDecoration(
                    color: appColors.cardBackground,
                    borderRadius: BorderRadius.circular(14),
                    border:
                        Border.all(color: appColors.cardBorder, width: 0.5),
                  ),
                  child: TextField(
                    controller: _searchController,
                    style: TextStyle(color: cs.onSurface, fontSize: 14),
                    decoration: InputDecoration(
                      hintText: 'Search by username...',
                      hintStyle: TextStyle(
                          color: appColors.subtleText, fontSize: 14),
                      prefixIcon: Icon(Icons.search,
                          color: appColors.subtleText, size: 20),
                      suffixIcon: _searchController.text.isNotEmpty
                          ? IconButton(
                              icon: Icon(Icons.clear,
                                  color: appColors.subtleText, size: 18),
                              onPressed: () {
                                _searchController.clear();
                                setState(() => _searchResults = []);
                              },
                            )
                          : null,
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 14),
                    ),
                    onChanged: (v) {
                      setState(() {});
                      _searchUsers(v);
                    },
                  ),
                ),
                const SizedBox(height: 14),

                // ── Searching → results; else → requests ──
                if (searching) ...[
                  if (_isSearching)
                    Padding(
                      padding: const EdgeInsets.all(24),
                      child: Center(
                          child: CircularProgressIndicator(
                              color: cs.primary)),
                    )
                  else if (_searchResults.isNotEmpty)
                    ..._searchResults.map(_searchResultCard)
                  else
                    _noResults(appColors, cs),
                ] else ...[
                  _requestsHeader(appColors, cs),
                  const SizedBox(height: 8),
                  if (_pendingRequests.isEmpty)
                    _emptyRequests(appColors, cs)
                  else
                    ..._pendingRequests.map(_requestCard),
                ],
              ],
            ),
    );
  }

  Widget _requestsHeader(AppColors appColors, ColorScheme cs) {
    return Row(children: [
      Text('Buddy requests',
          style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: cs.onSurface)),
      const SizedBox(width: 8),
      if (_pendingRequests.isNotEmpty)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
          decoration: BoxDecoration(
              color: const Color(0xFFF97316),
              borderRadius: BorderRadius.circular(10)),
          child: Text('${_pendingRequests.length}',
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w800)),
        ),
    ]);
  }

  Widget _searchResultCard(Map<String, dynamic> user) {
    final appColors = AppColors.of(context);
    final cs = Theme.of(context).colorScheme;
    final isSending = _sendingRequestTo == user['id'];
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: appColors.cardBackground,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: appColors.cardBorder, width: 0.5),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.all(12),
        leading: UserAvatar(avatarId: user['avatar_id'], size: 48),
        title: Text(user['display_name'] ?? 'Unknown',
            style: TextStyle(
                fontWeight: FontWeight.w700,
                color: cs.onSurface,
                fontSize: 14)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('@${user['username'] ?? 'unknown'}',
                style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF3B82F6),
                    fontWeight: FontWeight.w500)),
            Text(
                user['fitness_level']?.toString().toUpperCase() ??
                    'BEGINNER',
                style: TextStyle(
                    fontSize: 11, color: appColors.subtleText)),
          ],
        ),
        trailing: isSending
            ? SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: cs.primary))
            : GestureDetector(
                onTap: () => _sendFriendRequest(user['id']),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 7),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1D4ED8),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.person_add, size: 14, color: Colors.white),
                      SizedBox(width: 5),
                      Text('Add',
                          style: TextStyle(
                              fontSize: 12,
                              color: Colors.white,
                              fontWeight: FontWeight.w700)),
                    ],
                  ),
                ),
              ),
      ),
    );
  }

  Widget _requestCard(Map<String, dynamic> request) {
    final appColors = AppColors.of(context);
    final cs = Theme.of(context).colorScheme;
    final profile = request['user_profiles'];
    final isProcessing = _processingRequestId == request['id'];

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: appColors.cardBackground,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: const Color(0xFFF97316).withOpacity(0.25), width: 0.5),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(children: [
          Row(children: [
            UserAvatar(avatarId: profile?['avatar_id'], size: 50),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(profile?['display_name'] ?? 'Unknown',
                      style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                          color: cs.onSurface)),
                  const SizedBox(height: 3),
                  Text('Wants to be your gym buddy',
                      style: TextStyle(
                          fontSize: 12, color: appColors.subtleText)),
                ],
              ),
            ),
          ]),
          const SizedBox(height: 14),
          if (isProcessing)
            Center(child: CircularProgressIndicator(color: cs.primary))
          else
            Row(children: [
              Expanded(
                child: GestureDetector(
                  onTap: () => _acceptRequest(request['id']),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF10B981),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.check, size: 15, color: Colors.white),
                        SizedBox(width: 5),
                        Text('Accept',
                            style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                                fontSize: 13)),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: GestureDetector(
                  onTap: () => _declineRequest(request['id']),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                          color: const Color(0xFFEF4444), width: 0.5),
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.close,
                            size: 15, color: Color(0xFFEF4444)),
                        SizedBox(width: 5),
                        Text('Decline',
                            style: TextStyle(
                                color: Color(0xFFEF4444),
                                fontWeight: FontWeight.w700,
                                fontSize: 13)),
                      ],
                    ),
                  ),
                ),
              ),
            ]),
        ]),
      ),
    );
  }

  Widget _noResults(AppColors appColors, ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 40, 12, 12),
      child: Column(
        children: [
          Icon(Icons.search_off, size: 56, color: appColors.subtleText),
          const SizedBox(height: 14),
          Text('No user found',
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: cs.onSurface)),
          const SizedBox(height: 6),
          Text('"${_searchController.text.trim()}" doesn\'t exist',
              textAlign: TextAlign.center,
              style: TextStyle(color: appColors.subtleText)),
          const SizedBox(height: 4),
          Text('Search by exact username',
              style: TextStyle(fontSize: 12, color: appColors.subtleText)),
        ],
      ),
    );
  }

  Widget _emptyRequests(AppColors appColors, ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 40, 12, 12),
      child: Column(
        children: [
          Icon(Icons.inbox, size: 56, color: appColors.subtleText),
          const SizedBox(height: 14),
          Text('No Pending Requests',
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: cs.onSurface)),
          const SizedBox(height: 6),
          Text('Search above to add a buddy',
              style: TextStyle(fontSize: 13, color: appColors.subtleText)),
        ],
      ),
    );
  }
}