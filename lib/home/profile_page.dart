part of '../home_screen.dart';

/// What Profile knows, part by part. A null part was never answered by the
/// server or the saved copy, and is never painted as a default.
typedef ProfileParts = ({
  Map<String, dynamic>? profile,
  List<TeamStreak>? streaks,
  LevelInfo? level,
  int? workouts,
  int? buddies,
  List<Map<String, dynamic>>? favs,
});

const ProfileParts noProfileParts =
    (profile: null, streaks: null, level: null, workouts: null, buddies: null, favs: null);

/// What the page knows after a load: each part the server answered, else the
/// one known now (the saved copy or an earlier load). A null in [answered] is
/// a failed read, so a failing part never blocks the others.
@visibleForTesting
ProfileParts profileAfterLoad(ProfileParts shown, ProfileParts answered) => (
      profile: answered.profile ?? shown.profile,
      streaks: answered.streaks ?? shown.streaks,
      level: answered.level ?? shown.level,
      workouts: answered.workouts ?? shown.workouts,
      buddies: answered.buddies ?? shown.buddies,
      favs: answered.favs ?? shown.favs,
    );

/// Whether every part the page prints a name or a number from is known. Until
/// then it stays on the skeleton, so no default is painted. Favourites are not
/// needed: that card hides itself when it has nothing to show.
@visibleForTesting
bool profileReady(ProfileParts p) =>
    p.profile != null &&
    p.streaks != null &&
    p.level != null &&
    p.workouts != null &&
    p.buddies != null;

/// Whether one load answered every part. Only then is the saved copy written,
/// so it never holds a default or an incomplete list.
@visibleForTesting
bool profileComplete(ProfileParts answered) => profileReady(answered) && answered.favs != null;

// Profile Page
class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}
 
class _ProfilePageState extends State<ProfilePage>
    with TickerProviderStateMixin, AutomaticKeepAliveClientMixin, TabKeepAlive {
  @override
  AppTab get tab => AppTab.profile;

  /// _loadAll never shows the skeleton again, and the fade has already run.
  @override
  void refreshInBackground() => _loadAll();

  ProfileParts _parts = noProfileParts;
  // The page builds only once [profileReady], so the fallbacks below are never
  // painted, except favourites, whose card hides when empty.
  Map<String, dynamic>? get _profile => _parts.profile;
  List<TeamStreak> get _allStreaks => _parts.streaks ?? const [];
  StreakSortMode get _streakSortMode => StreakSortMode.values.firstWhere(
        (e) => e.name == _parts.profile?['preferred_streak_sort'],
        orElse: () => StreakSortMode.highestCurrent,
      );
  /// Mirrors the dashboard's list so both entry points agree.
  List<TeamStreak> get _listStreaks => sortStreaks(_allStreaks, _streakSortMode);
  /// Total sortable streaks (friends only), independent of sort/filter mode.
  int get _streakCount => _allStreaks.where((s) => !s.isCoachMaxTeam).length;
  LevelInfo? get _levelInfo => _parts.level;
  int get _totalWorkouts => _parts.workouts ?? 0;
  int get _buddyCount => _parts.buddies ?? 0;
  /// Top 3 workout_category values for the CURRENT CALENDAR MONTH in the
  /// user's own local timezone, from get_favourite_categories (the RPC does
  /// the month + tz resolution server-side). Each row:
  /// {workout_category, category_count}. Empty is a normal state — the card
  /// is hidden rather than showing a zero.
  List<Map<String, dynamic>> get _favouriteCategories => _parts.favs ?? const [];
  bool _isLoading = true;
  final _once = RunOnce();

  late AnimationController _fadeController;
  late Animation<double> _xpAnimation;
  late Animation<double> _ringAnimation;
 
  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );
    _xpAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _fadeController, curve: const Interval(0.3, 1.0, curve: Curves.easeOut)),
    );
    _ringAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _fadeController, curve: const Interval(0.2, 1.0, curve: Curves.easeOut)),
    );
    _restoreSaved();
    _loadAll();
    EconomySync.instance.numbers.addListener(_onEconomyChanged);
  }

  /// xp or level changed. Shown, the tab keeps what it has, as before;
  /// hidden, it is refetched on a show once the data is more than 2 minutes
  /// old. A finished check-in marks it stale outright (applyFinishResult).
  void _onEconomyChanged() {
    if (!tabShown) markDirty({AppTab.profile});
  }

  @override
  void dispose() {
    EconomySync.instance.numbers.removeListener(_onEconomyChanged);
    _once.dispose();
    _fadeController.dispose();
    super.dispose();
  }
 
  // ── data loading ──────────────────────────────────────────────

  /// First paint from the saved copy (same local day only: it carries streak
  /// numbers). A load that finished first wins.
  Future<void> _restoreSaved() async {
    final saved = await SavedCopy.read<Map<String, dynamic>>(
      SavedCopy.uid,
      'profile',
      maxAge: kSavedMaxAgeProfile,
      sameDay: true,
      parse: (d) {
        final m = d as Map<String, dynamic>;
        return {
          'profile': Map<String, dynamic>.from(m['profile'] as Map),
          'streaks': [
            for (final s in m['streaks'] as List)
              TeamStreak.fromSaved(Map<String, dynamic>.from(s as Map)),
          ],
          'level': LevelInfo.fromSaved(Map<String, dynamic>.from(m['level'] as Map)),
          'workouts': m['workouts'] as int,
          'buddies': m['buddies'] as int,
          'favs': [
            for (final f in m['favs'] as List) Map<String, dynamic>.from(f as Map),
          ],
        };
      },
    );
    // A load that already answered everything wins; one that answered only
    // some parts (or failed) leaves the rest to the saved copy.
    if (saved == null || !mounted || profileReady(_parts)) return;
    setState(() {
      _parts = profileAfterLoad((
        profile: saved['profile'] as Map<String, dynamic>,
        streaks: saved['streaks'] as List<TeamStreak>,
        level: saved['level'] as LevelInfo,
        workouts: saved['workouts'] as int,
        buddies: saved['buddies'] as int,
        favs: saved['favs'] as List<Map<String, dynamic>>,
      ), _parts);
      _isLoading = false;
    });
    _fadeController.forward();
  }

  void _retry() {
    setState(() => _isLoading = true);
    _loadAll();
  }

  Future<void> _loadAll() => refreshState.track(() async {
    try {
      final uid = Supabase.instance.client.auth.currentUser?.id;
      if (uid == null) return;

      // Each read answers null when it fails: one failing part never blocks
      // the others, and no error is left unobserved. Offline is expected;
      // anything else is sent to Crashlytics as a non-fatal.
      Future<T?> part<T>(String label, Future<T> read) =>
          read.then<T?>((v) => v, onError: (Object e, StackTrace st) {
            if (kDebugMode) debugLog('⚠️ Profile read failed, kept as shown: $e');
            reportNonFatal(e, st, label);
            return null;
          });

      final (profile, streaks, level, workouts, friends, favs) = await (
        part<Map<String, dynamic>>(
            'profile_row',
            Supabase.instance.client
                .rpc('get_my_profile')
                .select('avatar_id, display_name, created_at, xp, level, preferred_streak_sort')
                .single()),
        part('profile_streaks', TeamStreakService().getAllUserStreaks(strict: true)),
        part('profile_level', LevelService().getLevelInfo()),
        part('profile_workouts', WorkoutService().completedWorkoutCount(uid)),
        part('profile_buddies', FriendService().getFriends(strict: true)),
        part<List<Map<String, dynamic>>>(
            'profile_favs',
            Supabase.instance.client
                .rpc('get_favourite_categories', params: {'p_user_id': uid}).then((r) =>
                    [for (final f in r as List) Map<String, dynamic>.from(f as Map)])),
      ).wait;

      if (!mounted) return;

      // Coach Max's team means a real account never has no streaks, so an
      // empty list is a failed read too.
      final answered = (
        profile: profile,
        streaks: streaks == null || streaks.isEmpty ? null : streaks,
        level: level,
        workouts: workouts,
        buddies: friends?.length,
        favs: favs,
      );
      setState(() {
        _parts = profileAfterLoad(_parts, answered);
        _isLoading = false;
      });

      if (profileComplete(answered)) {
        unawaited(SavedCopy.write(SavedCopy.uid, 'profile', {
          'profile': answered.profile,
          'streaks': [for (final s in answered.streaks!) s.toSaved()],
          'level': answered.level!.toSaved(),
          'workouts': answered.workouts,
          'buddies': answered.buddies,
          'favs': answered.favs,
        }, zone: profileZone));
      } else {
        refreshState.failed(); // retried on the next show
      }
    } catch (e, st) {
      if (kDebugMode) debugLog('❌ ProfilePage._loadAll: $e');
      reportNonFatal(e, st, 'profile_load');
      refreshState.failed(); // retried on the next show
      if (mounted) setState(() => _isLoading = false);
    } finally {
      // Every exit runs the fade, so a pull-to-refresh that reset it never
      // leaves the XP ring and bar at 0%.
      await Future.delayed(const Duration(milliseconds: 50));
      if (mounted) _fadeController.forward();
    }
  });

  int get _bestStreak => _allStreaks.isEmpty
      ? 0
      : _allStreaks.map((s) => s.bestStreak).reduce((a, b) => a > b ? a : b);

 
  // ══════════════════════════════════════════════════════════════
  // BUILD
  // ══════════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    super.build(context); // keep-alive
    if (_isLoading) return _buildSkeleton();
    // Nothing known yet and the load failed: the skeleton with a retry, never defaults.
    if (!profileReady(_parts)) return _buildSkeleton(failed: true);

    final appColors = AppColors.of(context);
    final profile  = _profile!;
    final level    = _levelInfo!.level;
    final title    = _levelInfo!.title;
    final avatarId = profile['avatar_id'] as String? ?? 'lion';
    final name     = profile['display_name'] as String? ?? 'User';
    final year     = formatYear(profile['created_at'] as String?);

    return Scaffold(
      backgroundColor: appColors.sectionBackground,
      body: RefreshIndicator(
        onRefresh: () async {
          _fadeController.reset();
          await _loadAll();
        },
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          // The nav bar floats over the body (extendBody), so
          // reserve its height or the last card hides under it.
          padding: EdgeInsets.only(
            bottom: 62 + MediaQuery.paddingOf(context).bottom,
          ),
          children: [
            _buildHero(
              name: name, year: year, avatarId: avatarId,
              level: level, title: title,
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 5, 16, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                      _buildXpCard(),
                      const SizedBox(height: 14),
                      _buildLifetimeStatsCard(),
                      // Hidden entirely when the user has logged nothing this
                      // month (e.g. the first days of a new month).
                      if (_favouriteCategories.isNotEmpty) ...[
                        const SizedBox(height: 14),
                        _buildTopCategoriesCard(),
                      ],
                      const SizedBox(height: 22),
                      _sectionLabel('Activity'),
                      const SizedBox(height: 10),
                      buildMenuCard(context, [
                        MenuItem(
                          emoji: '🔥',
                          color: appColors.sectionBackground,
                          label: 'All Streaks',
                          sub: '$_streakCount active streaks',
                          onTap: () => showDialog(
                            context: context,
                            builder: (_) => _AllStreaksDialog(streaks: _listStreaks),
                          ),
                        ),
                        MenuItem(
                          emoji: '🏆',
                          color: appColors.sectionBackground,
                          label: 'Achievements',
                          sub: 'View all achievements',
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => achievements_page.AchievementsPage()),
                          ),
                        ),
                        MenuItem(
                          emoji: '📊',
                          color: appColors.sectionBackground,
                          label: 'Progress',
                          sub: 'View your history',
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) => const WorkoutHistoryPage()),
                          ),
                        ),
                      ]),
                      const SizedBox(height: 22),
                      _sectionLabel('Settings'),
                      const SizedBox(height: 10),
                      buildMenuCard(context, [
                        MenuItem(
                          emoji: '🔔',
                          color: appColors.sectionBackground,
                          label: 'Notifications',
                          sub: 'Manage alerts',
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => const NotificationSettingsPage()),
                          ),
                        ),
                        MenuItem(
                          emoji: '🌈',
                          color: appColors.sectionBackground,
                          label: 'Accent Theme',
                          sub: _accentThemeLabel(context),
                          onTap: () => _showAccentThemePicker(context),
                        ),
                        MenuItem(
                          emoji: '❓',
                          color: appColors.sectionBackground,
                          label: 'Help & Support',
                          sub: 'FAQs & contact',
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => const HelpSupportPage()),
                          ),
                        ),
                        MenuItem(
                          icon: Icons.person_outline,
                          iconColor: appColors.subtleText,
                          color: appColors.sectionBackground,
                          label: 'Account',
                          sub: 'Email, username, delete',
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => const AccountPage()),
                          ),
                        ),
                      ]),
                      const SizedBox(height: 22),
                  _buildLogoutButton(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _accentThemeLabel(BuildContext context) {
    final theme = context.watch<AccentThemeProvider>().accentTheme;
    return AccentPalette.forTheme(theme).name;
  }

  Future<void> _showAccentThemePicker(BuildContext context) {
    final provider = context.read<AccentThemeProvider>();
    return showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final appColors = AppColors.of(context);
        return Container(
          decoration: BoxDecoration(
            color: appColors.cardBackground,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Handle
              Container(
                width: 40, height: 4,
                decoration: BoxDecoration(
                  color: appColors.divider,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Accent Theme',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 20),
              // Every skin's label, blurb and swatch comes off its palette —
              // adding an accent never touches this screen again.
              for (final theme in AccentTheme.values) ...[
                if (theme != AccentTheme.values.first)
                  const SizedBox(height: 10),
                _accentOption(ctx, provider, theme),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _accentOption(
    BuildContext ctx,
    AccentThemeProvider provider,
    AccentTheme theme,
  ) {
    final palette = AccentPalette.forTheme(theme);
    final isSelected = provider.accentTheme == theme;
    final appColors = AppColors.of(ctx);
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        provider.setAccentTheme(theme);
        Navigator.pop(ctx);
        setState(() {}); // refresh sub-label
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: isSelected
              ? appColors.avatarRing.withValues(alpha: 0.1)
              : appColors.sectionBackground,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected ? appColors.avatarRing : appColors.cardBorder,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: palette.swatch,
                border: Border.all(color: appColors.cardBorder),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    palette.name,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: isSelected
                          ? appColors.avatarRing
                          : Theme.of(ctx).colorScheme.onSurface,
                    ),
                  ),
                  Text(
                    palette.description,
                    style: TextStyle(fontSize: 12, color: appColors.subtleText),
                  ),
                ],
              ),
            ),
            if (isSelected)
              Icon(Icons.check_circle, color: appColors.avatarRing, size: 22),
          ],
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════
  // HERO
  // ══════════════════════════════════════════════════════════════
  Widget _buildHero({
    required String name, required String year,
    required String avatarId, required int level, required String title,
  }) {
    // Hero fill follows the active accent theme (was a fixed purple gradient)
    final appColors = AppColors.of(context);
    return Container(
      decoration: BoxDecoration(
        color: appColors.cardBackground,
      ),
      child: SafeArea(
        bottom: false,
        child: Stack(
          children: [
            Positioned(
              top: -30, right: -30,
              child: Container(
                width: 160, height: 160,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.06),
                ),
              ),
            ),
            Positioned(
              bottom: 20, left: -20,
              child: Container(
                width: 120, height: 120,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.04),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 25),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Profile',
                        style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700),
                      ),
                      GestureDetector(
                        onTap: () => _once.run(() => Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const NotificationSettingsPage()),
                        )),
                        child: Container(
                          width: 36, height: 36,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white.withValues(alpha: 0.15),
                          ),
                          child: const Icon(Icons.settings_outlined, color: Colors.white, size: 18),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      GestureDetector(
                        onTap: () => _once.run(() async {
                          final saved = await Navigator.push<bool>(
                            context,
                            MaterialPageRoute(builder: (_) => const WardrobePage()),
                          );
                          if (saved == true) {
                            _fadeController.reset();
                            _loadAll();
                          }
                        }),
                        child: Stack(
                          clipBehavior: Clip.none,
                          alignment: Alignment.center,
                          children: [
                            SizedBox(
                              width: 98, height: 98,
                              child: AnimatedBuilder(
                                animation: _ringAnimation,
                                builder: (context, _) => CircularProgressIndicator(
                                  value: (_levelInfo?.progressPercent ?? 0.0) * _ringAnimation.value,
                                  strokeWidth: 4,
                                  backgroundColor: Colors.white.withValues(alpha: 0.2),
                                  valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
                                ),
                              ),
                            ),
                            Container(
                              width: 86, height: 86,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.white.withValues(alpha: 0.15),
                                border: Border.all(color: Colors.white.withValues(alpha: 0.3), width: 2),
                              ),
                              child: Center(
                                child: UserAvatar(
                                  avatarId: avatarId,
                                  size: 86,
                                  bare: true,
                                  animated: true,
                                  semanticLabel: '',
                                ),
                              ),
                            ),
                            Positioned(
                              bottom: -4, right: -4,
                              child: Container(
                                width: 30, height: 30,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  gradient: LinearGradient(
                                    colors: levelGradient(level),
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                  ),
                                  border: Border.all(color: Colors.white, width: 2),
                                  boxShadow: [
                                    BoxShadow(
                                      color: levelGradient(level).last.withValues(alpha: 0.5),
                                      blurRadius: 8,
                                    ),
                                  ],
                                ),
                                child: Center(
                                  child: Text(
                                    '$level',
                                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Colors.white),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            Text(
                              name,
                              style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Member since $year',
                              style: TextStyle(color: Colors.white.withValues(alpha: 0.65), fontSize: 13),
                            ),
                            const SizedBox(height: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(20),
                                color: Colors.white.withValues(alpha: 0.18),
                                border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
                              ),
                              child: Text(
                                '${titleIcon(title)}  $title',
                                style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
 
  // ══════════════════════════════════════════════════════════════
  // XP CARD
  // ══════════════════════════════════════════════════════════════
  Widget _buildXpCard() {
    final appColors = AppColors.of(context);
    final accentPalette = context.watch<AccentThemeProvider>().palette;
    return Container(
      decoration: BoxDecoration(
        color: appColors.cardBackground,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: accentPalette.statusInfo.withValues(alpha: 0.1),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: _levelInfo == null
          ? const Padding(
              padding: EdgeInsets.all(20),
              child: Center(child: CircularProgressIndicator()),
            )
          : Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Row(
                    children: [
                      Container(
                        width: 40, height: 40,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          color: accentPalette.statusInfo,
                        ),
                        child: const Center(child: Text('⭐', style: TextStyle(fontSize: 20))),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Level ${_levelInfo!.level} — ${_levelInfo!.title}',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: Theme.of(context).colorScheme.onSurface,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              _levelInfo!.level >= 99
                                  ? 'Max level reached 🏆'
                                  : '${_levelInfo!.xpNeededForNext} XP to level ${_levelInfo!.level + 1}',
                              style: TextStyle(fontSize: 12, color: appColors.subtleText),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                        decoration: BoxDecoration(
                          color: accentPalette.statusInfo.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          '${_levelInfo!.currentXp} XP',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: accentPalette.statusInfo,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(100),
                    child: AnimatedBuilder(
                      animation: _xpAnimation,
                      builder: (context, _) => LinearProgressIndicator(
                        value: _levelInfo!.progressPercent * _xpAnimation.value,
                        minHeight: 8,
                        backgroundColor: appColors.sectionBackground,
                        valueColor: AlwaysStoppedAnimation<Color>(accentPalette.statusInfo),
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '${_levelInfo!.xpIntoCurrentLevel} / ${_levelInfo!.xpForNextLevel - _levelInfo!.xpForThisLevel} XP',
                        style: TextStyle(fontSize: 11, color: appColors.subtleText),
                      ),
                      Text(
                        '${(_levelInfo!.progressPercent * 100).toStringAsFixed(0)}%',
                        style: TextStyle(fontSize: 11, color: appColors.subtleText),
                      ),
                    ],
                  ),
                ],
              ),
            ),
    );
  }
 
  // ══════════════════════════════════════════════════════════════
  // STATS ROW
  // ══════════════════════════════════════════════════════════════
  // ══════════════════════════════════════════════════════════════
  // LIFETIME STATS
  // ══════════════════════════════════════════════════════════════
  // Replaces the old four-tile emoji stats row. The dropped 4th tile was
  // 'Streaks' showing _allStreaks.length -- every streak INCLUDING the Coach
  // Max team, which disagreed with the "All Streaks" menu row below (that one
  // uses _streakCount, friends-only). Dropping it removes the mismatch rather
  // than carrying it into the new card.
  //
  // Uses the radius-20 card token shared with _buildXpCard and the top
  // categories card, not the lighter radius-16 one the old tiles had.
  Widget _buildLifetimeStatsCard() {
    final appColors = AppColors.of(context);
    final accentPalette = context.watch<AccentThemeProvider>().palette;

    return Container(
      decoration: BoxDecoration(
        color: appColors.cardBackground,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: accentPalette.statusInfo.withValues(alpha: 0.1),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'LIFETIME STATS',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
              color: appColors.subtleText,
            ),
          ),
          const SizedBox(height: 10),
          // IntrinsicHeight so the hairline dividers span the tallest block
          // rather than collapsing to zero height.
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: _lifetimeStatBlock(_bestStreak, 'Best streak')),
                _statDivider(),
                Expanded(child: _lifetimeStatBlock(_totalWorkouts, 'Workouts')),
                _statDivider(),
                Expanded(child: _lifetimeStatBlock(_buddyCount, 'Buddies')),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _statDivider() {
    final appColors = AppColors.of(context);
    return Container(width: 1, color: appColors.divider);
  }

  Widget _lifetimeStatBlock(int value, String caption) {
    final appColors = AppColors.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        CappedCount(
          value: value,
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w800,
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
        Text(
          caption,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w500,
            color: appColors.subtleText,
          ),
        ),
      ],
    );
  }

  // ══════════════════════════════════════════════════════════════
  // THIS MONTH'S TOP CATEGORIES
  // ══════════════════════════════════════════════════════════════
  // Category keys/labels mirror WorkoutSelectionModal._categoryDefs (the
  // canonical "10 category tile" list from the check-in grid). Not shared as
  // a common lookup — this page only touches its own file, matching
  // titleIcon above.
  //
  // The per-category emoji lookup that used to live here is gone: rows are
  // ranked 1/2/3 by number now, and neither of the two new cards uses emoji.
  String _categoryLabel(String category) {
    const map = {
      'strength': 'Strength',
      'cardio': 'Cardio',
      'hiit': 'HIIT',
      'yoga': 'Yoga / stretch',
      'outside': 'Outside',
      'sports': 'Sports',
      'swimming': 'Swimming',
      'cycling': 'Cycling',
      'martial_arts': 'Martial arts',
      'recovery': 'Recovery',
    };
    return map[category] ?? category;
  }

  Widget _buildTopCategoriesCard() {
    final appColors = AppColors.of(context);
    final accentPalette = context.watch<AccentThemeProvider>().palette;
    final topCount = (_favouriteCategories.first['category_count'] as num).toInt();

    return Container(
      decoration: BoxDecoration(
        color: appColors.cardBackground,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: accentPalette.statusInfo.withValues(alpha: 0.1),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // The title carries the timeframe on its own — no corner tag.
          Text(
            "This Month's Top Categories",
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 8),
          for (int i = 0; i < _favouriteCategories.length; i++)
            _buildCategoryRow(
              rank: i + 1,
              category: _favouriteCategories[i]['workout_category'] as String,
              count: (_favouriteCategories[i]['category_count'] as num).toInt(),
              topCount: topCount,
              isTop: i == 0,
            ),
        ],
      ),
    );
  }

  Widget _buildCategoryRow({
    required int rank,
    required String category,
    required int count,
    required int topCount,
    required bool isTop,
  }) {
    final appColors = AppColors.of(context);
    final accentPalette = context.watch<AccentThemeProvider>().palette;
    // No gold slot exists on AccentPalette; statusWarning is its amber, and
    // it is the one warm token that is contrast-tuned per palette (action is
    // reserved for the primary CTA per the brand rule).
    final gold = accentPalette.statusWarning;
    final rankColor = isTop ? gold : appColors.subtleText;
    final barColor = isTop ? gold : appColors.subtleText;
    final fraction = topCount == 0 ? 0.0 : count / topCount;

    return Row(
      children: [
        SizedBox(
          width: 16,
          child: Text(
            '$rank',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: rankColor,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _categoryLabel(category),
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(100),
                child: LinearProgressIndicator(
                  value: fraction,
                  minHeight: 5,
                  backgroundColor: appColors.sectionBackground,
                  valueColor: AlwaysStoppedAnimation<Color>(barColor),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        CappedCount(
          value: count,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w800,
            color: rankColor,
          ),
        ),
      ],
    );
  }

  // ══════════════════════════════════════════════════════════════
  // MENU
  // ══════════════════════════════════════════════════════════════
  Widget _sectionLabel(String text) {
    final appColors = AppColors.of(context);
    return Text(
      text.toUpperCase(),
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        color: appColors.subtleText,
        letterSpacing: 0.8,
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════
  // LOG OUT
  // ══════════════════════════════════════════════════════════════
  Widget _buildLogoutButton() => LogoutButton(onLogout: _logOut);

  Future<void> _logOut() async {
    HapticFeedback.mediumImpact();
    // AuthService.signOut releases this handset's FCM token while the user is
    // still signed in, ends the Supabase session and clears the Google
    // session so the account picker shows again.
    await AuthService().signOut();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => LoginScreen()),
      (route) => false,
    );
  }
 
  // ══════════════════════════════════════════════════════════════
  // SKELETON — shown while data loads
  // Shows a realistic shimmer layout matching the real page
  // ══════════════════════════════════════════════════════════════
   Widget _buildSkeleton({bool failed = false}) {
    final appColors = AppColors.of(context);
    return Scaffold(
      backgroundColor: appColors.sectionBackground,
      body: Column(
        children: [
          Container(
            height: 220,
            // Matches _buildHero's fill so the load-flash stays invisible
            decoration: BoxDecoration(
              color: appColors.cardBackground,
            ),
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        SkeletonBox(width: 60, height: 18, radius: 6),
                        SkeletonBox.circle(size: 36),
                      ],
                    ),
                    const SizedBox(height: 24),
                    const Row(
                      children: [
                        SkeletonBox.circle(size: 86),
                        SizedBox(width: 16),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SkeletonBox(width: 120, height: 20, radius: 6),
                            SizedBox(height: 8),
                            SkeletonBox(width: 90, height: 14, radius: 6),
                            SizedBox(height: 10),
                            SkeletonBox(width: 100, height: 26, radius: 13),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (failed) ...[
                    Center(
                      child: Column(
                        children: [
                          Text(
                            'Could not load your profile',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                color: Theme.of(context).colorScheme.onSurface, fontSize: 16),
                          ),
                          TextButton(
                            onPressed: _retry,
                            child: const Text(
                              'Try again',
                              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                  ],
                  const SkeletonBox(width: double.infinity, height: 110, radius: 18),
                  const SizedBox(height: 14),
                  const Row(
                    children: [
                      Expanded(child: SkeletonBox(width: double.infinity, height: 90, radius: 18)),
                      SizedBox(width: 10),
                      Expanded(child: SkeletonBox(width: double.infinity, height: 90, radius: 18)),
                      SizedBox(width: 10),
                      Expanded(child: SkeletonBox(width: double.infinity, height: 90, radius: 18)),
                      SizedBox(width: 10),
                      Expanded(child: SkeletonBox(width: double.infinity, height: 90, radius: 18)),
                    ],
                  ),
                  const SizedBox(height: 22),
                  const SkeletonBox(width: 70, height: 12, radius: 4),
                  const SizedBox(height: 10),
                  const SkeletonBox(width: double.infinity, height: 160, radius: 18),
                  const SizedBox(height: 22),
                  const SkeletonBox(width: 70, height: 12, radius: 4),
                  const SizedBox(height: 10),
                  const SkeletonBox(width: double.infinity, height: 160, radius: 18),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

}
