part of '../home_screen.dart';

class _AllStreaksDialog extends StatefulWidget {
  final List<TeamStreak> streaks;
  const _AllStreaksDialog({required this.streaks});

  @override
  State<_AllStreaksDialog> createState() => _AllStreaksDialogState();
}

class _AllStreaksDialogState extends State<_AllStreaksDialog> {
  late List<TeamStreak> _streaks;
  final _once = RunOnce();

  @override
  void initState() {
    super.initState();
    _streaks = List.from(widget.streaks);
  }

  @override
  void dispose() {
    _once.dispose();
    super.dispose();
  }

  // ── Rename ──────────────────────────────────────────────
  Future<void> _showRenameDialog(TeamStreak streak) async {
    final appColors = AppColors.of(context);
    final cs = Theme.of(context).colorScheme;
    var input = streak.teamName;

    final newName = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: appColors.cardBackground,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16)),
        title: Row(children: [
          Icon(Icons.edit_outlined,
              color: const Color(0xFF3B82F6), size: 20),
          const SizedBox(width: 10),
          Text('Rename team',
              style: TextStyle(
                  color: cs.onSurface,
                  fontSize: 16,
                  fontWeight: FontWeight.w700)),
        ]),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Give your partnership a custom name',
                style: TextStyle(
                    fontSize: 13, color: appColors.subtleText)),
            const SizedBox(height: 14),
            TextFormField(
              initialValue: input,
              onChanged: (v) => input = v,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              style: TextStyle(color: cs.onSurface),
              decoration: InputDecoration(
                labelText: 'Team name',
                hintText: 'e.g. Morning Crew',
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10)),
                prefixIcon: const Icon(Icons.group_outlined),
              ),
              onFieldSubmitted: (v) => Navigator.pop(context, v),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel',
                style:
                    TextStyle(color: appColors.subtleText)),
          ),
          GestureDetector(
            onTap: () =>
                Navigator.pop(context, input),
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF3B82F6),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text('Save',
                  style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700)),
            ),
          ),
        ],
      ),
    );

    if (newName != null &&
        newName.trim().isNotEmpty &&
        newName != streak.teamName) {
      await _updateTeamName(streak, newName.trim());
    }
  }

  Future<void> _updateTeamName(
      TeamStreak streak, String newName) async {
    try {
      await Supabase.instance.client
          .from('buddy_teams')
          .update({'team_name': newName})
          .eq('id', streak.teamId);

      // Update local list immediately without waiting for a full reload
      if (mounted) {
        setState(() {
          final idx = _streaks.indexWhere((s) => s.teamId == streak.teamId);
          if (idx != -1) {
            final updated = List<TeamStreak>.from(_streaks);
            updated[idx] = TeamStreak(
              id: streak.id,
              teamId: streak.teamId,
              teamName: newName,
              teamEmoji: streak.teamEmoji,
              currentStreak: streak.currentStreak,
              longestStreak: streak.longestStreak,
              totalWorkouts: streak.totalWorkouts,
              bestStreak: streak.bestStreak,
              lastWorkoutDate: streak.lastWorkoutDate,
              lastInteractionAt: streak.lastInteractionAt,
              isCoachMaxTeam: streak.isCoachMaxTeam,
              members: streak.members,
              todayCheckIns: streak.todayCheckIns,
              isFavorite: streak.isFavorite,
            );
            _streaks = updated;
          }
        });
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Renamed to "$newName"'),
          backgroundColor: AppColors.of(context).success,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8)),
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Failed to rename')));
      }
    }
  }

  // ── Buddy helpers ────────────────────────────────────────
  String _buddyName(TeamStreak streak) {
    if (streak.isCoachMaxTeam) return 'Coach Max';
    final me =
        Supabase.instance.client.auth.currentUser?.id;
    final buddy = streak.members.firstWhere(
        (m) => m.userId != me,
        orElse: () => streak.members.first);
    return buddy.displayName;
  }

  String _buddyAvatar(TeamStreak streak) {
    if (streak.isCoachMaxTeam) return 'coach_max';
    final me =
        Supabase.instance.client.auth.currentUser?.id;
    final buddy = streak.members.firstWhere(
        (m) => m.userId != me,
        orElse: () => streak.members.first);
    return buddy.avatarId ?? 'avatar_1';
  }

  @override
  Widget build(BuildContext context) {
    final appColors = AppColors.of(context);
    final cs = Theme.of(context).colorScheme;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding:
          const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
      child: Container(
            constraints: const BoxConstraints(
            maxWidth: 400),
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
            // ── Header ──────────────────────────────────
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Color(0xFFF97316),
                    AppColors.of(context).streakOrange
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.vertical(
                    top: Radius.circular(20)),
              ),
              child: Row(children: [
                const Text('🔥',
                    style: TextStyle(fontSize: 20)),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text('All Your Streaks',
                      style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                          letterSpacing: -0.3)),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text('${_streaks.length}',
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 13)),
                ),
              ]),
            ),

            // ── Tip ──────────────────────────────────────
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 14, vertical: 9),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                      color: appColors.divider, width: 0.5),
                ),
              ),
              child: Row(children: [
                const Text('✏️',
                    style: TextStyle(fontSize: 12)),
                const SizedBox(width: 7),
                Text('Tap the edit icon to rename any team',
                    style: TextStyle(
                        fontSize: 10,
                        color: appColors.subtleText)),
              ]),
            ),

            // ── List ──────────────────────────────────────
            Flexible(
              child: _streaks.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.sentiment_neutral,
                                size: 48,
                                color: appColors.subtleText),
                            const SizedBox(height: 12),
                            Text('No active streaks yet!',
                                style: TextStyle(
                                    color: appColors.subtleText)),
                          ],
                        ),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(
                          12, 8, 12, 4),
                      shrinkWrap: true,
                      itemCount: _streaks.length,
                      itemBuilder: (context, i) =>
                          _streakRow(_streaks[i],
                              appColors, cs),
                    ),
            ),

            // ── Close ─────────────────────────────────────
            Padding(
              padding: const EdgeInsets.all(12),
              child: GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Container(
                  width: double.infinity,
                  padding:
                      const EdgeInsets.symmetric(vertical: 13),
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
        ), // SingleChildScrollView
      ),
    );
  }

  Widget _streakRow(TeamStreak streak,
      AppColors appColors, ColorScheme cs) {
    final isCoach = streak.isCoachMaxTeam;
    final isComplete = streak.isCompleteToday;
    final buddyName = _buddyName(streak);

    return Container(
      margin: const EdgeInsets.only(bottom: 7),
      decoration: BoxDecoration(
        color: isCoach
            ? const Color(0xFFF97316).withValues(alpha: 0.06)
            : appColors.sectionBackground,
        borderRadius: BorderRadius.circular(11),
        border: Border.all(
          color: isCoach
              ? const Color(0xFFF97316).withValues(alpha: 0.2)
              : appColors.cardBorder,
          width: 0.5,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(9),
        child: Row(children: [
          // Avatar
          Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: isCoach
                        ? [
                            const Color(0xFF1D4ED8),
                            const Color(0xFF7C3AED)
                          ]
                        : [
                            const Color(0xFFF97316),
                            AppColors.of(context).streakOrange
                          ],
                  ),
                ),
                child: isCoach
                    ? const Center(
                        child: Text('🤖',
                            style: TextStyle(fontSize: 20)))
                    : ClipOval(
                        child: UserAvatar(
                            avatarId: _buddyAvatar(streak),
                            size: 40)),
              ),
              // 🤖 AI disclosure — this row sits in the same list as real buddies.
              if (isCoach)
                Positioned(
                  bottom: -2,
                  right: -6,
                  child: AiCornerBadge(scale: 0.85),
                ),
            ],
          ),
          const SizedBox(width: 10),
          // Name + buddy
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isCoach ? 'Coach Max' : streak.teamName,
                  style: TextStyle(
                      fontSize: streak.teamName.length > 20
                          ? 10
                          : 12,
                      fontWeight: FontWeight.w700,
                      color: cs.onSurface),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  isCoach
                      ? 'always here'
                      : 'with $buddyName',
                  style: TextStyle(
                      fontSize: 9,
                      color: appColors.subtleText),
                ),
              ],
            ),
          ),
          // Streak count
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${streak.currentStreak}',
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.5,
                    color: isComplete
                        ? appColors.success
                        : const Color(0xFFF97316)),
              ),
              Text('day streak',
                  style: TextStyle(
                      fontSize: 8,
                      color: appColors.subtleText)),
            ],
          ),
          const SizedBox(width: 6),
          // Status + edit
          if (!isCoach)
            GestureDetector(
              onTap: () => _once.run(() => _showRenameDialog(streak)),
              child: Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: appColors.cardBackground,
                  borderRadius: BorderRadius.circular(7),
                  border: Border.all(
                      color: appColors.cardBorder, width: 0.5),
                ),
                child: Icon(Icons.edit_outlined,
                    size: 14,
                    color: appColors.subtleText),
              ),
            )
          else
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: isComplete
                    ? appColors.success.withValues(alpha: 0.12)
                    : appColors.sectionBackground,
                shape: BoxShape.circle,
              ),
              child: Icon(
                isComplete ? Icons.check : Icons.access_time,
                size: 15,
                color: isComplete
                    ? appColors.success
                    : appColors.subtleText,
              ),
            ),
        ]),
      ),
    );
  }
}
