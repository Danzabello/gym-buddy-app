part of '../home_screen.dart';

/// The dashboard's saved copy as [dashboardFromSaved] reads it back. A null
/// part was never answered by the server and stays as the page starts it.
typedef SavedDashboard = ({
  List<TeamStreak> streaks,
  String? sort,
  List<String>? customOrder,
  String? zone,
  Map<String, String>? nicknames,
  Set<String>? checkIns,
  Set<String>? breakDates,
  Map<String, bool>? buddyOnBreak,
  Map<String, String>? buddyZones,
  Map<String, String>? ringHex,
  bool? hasCheckedIn,
  List<Map<String, dynamic>>? workouts,
});

/// What the dashboard saves after a load, or null when its streak read
/// failed (every account has Coach Max's team, so no streaks is a failed
/// read). Every other part is saved only when its own read answered; null
/// is a failed read, which keeps that part's value from [saved] (the
/// same-day entry already stored) or leaves it out. An empty answer is saved
/// as empty.
@visibleForTesting
Map<String, dynamic>? dashboardSavedPayload({
  required Map<String, dynamic>? saved,
  required List<TeamStreak> streaks,
  ({String sort, List<String> customOrder, String? zone})? prefs,
  Map<String, String>? nicknames,
  Set<String>? checkIns,
  Set<String>? breakDates,
  Map<String, bool>? buddyOnBreak,
  Map<String, String>? buddyZones,
  Map<String, String>? ringHex,
  bool? hasCheckedIn,
  List<Map<String, dynamic>>? workouts,
}) {
  if (streaks.isEmpty) return null;
  return {
    ...?saved,
    'streaks': [for (final s in streaks) s.toSaved()],
    if (prefs != null) ...{
      'sort': prefs.sort,
      'customOrder': prefs.customOrder,
      'zone': prefs.zone,
    },
    if (nicknames != null) 'nicknames': nicknames,
    if (checkIns != null) 'checkIns': checkIns.toList(),
    if (breakDates != null) 'breakDates': breakDates.toList(),
    if (buddyOnBreak != null) 'buddyOnBreak': buddyOnBreak,
    if (buddyZones != null) 'buddyZones': buddyZones,
    if (ringHex != null) 'ringHex': ringHex,
    if (hasCheckedIn != null) 'hasCheckedIn': hasCheckedIn,
    if (workouts != null) 'workouts': workouts,
  };
}

/// Reads [dashboardSavedPayload]'s output back; a missing part reads as
/// null. No streaks, or a part of the wrong shape, throws (corrupt).
@visibleForTesting
SavedDashboard dashboardFromSaved(Object d) {
  final m = d as Map<String, dynamic>;
  Map<String, T>? strings<T>(String k) =>
      m[k] == null ? null : Map<String, T>.from(m[k] as Map);
  Set<String>? dates(String k) =>
      m[k] == null ? null : Set<String>.from(m[k] as List);
  final streaks = [
    for (final s in m['streaks'] as List)
      TeamStreak.fromSaved(Map<String, dynamic>.from(s as Map)),
  ];
  if (streaks.isEmpty) throw const FormatException('no streaks saved');
  return (
    streaks: streaks,
    sort: m['sort'] as String?,
    customOrder: m['customOrder'] == null ? null : List<String>.from(m['customOrder'] as List),
    zone: m['zone'] as String?,
    nicknames: strings<String>('nicknames'),
    checkIns: dates('checkIns'),
    breakDates: dates('breakDates'),
    buddyOnBreak: strings<bool>('buddyOnBreak'),
    buddyZones: strings<String>('buddyZones'),
    ringHex: strings<String>('ringHex'),
    hasCheckedIn: m['hasCheckedIn'] as bool?,
    workouts: m['workouts'] == null
        ? null
        : [for (final w in m['workouts'] as List) Map<String, dynamic>.from(w as Map)],
  );
}


// Dashboard/Home Page with Real Streak Data
class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key, this.clock = DateTime.now});

  /// The time the clock-dependent parts of the page are built from (the coach
  /// tip, the week card, the danger countdown, the feed ages).
  final Clock clock;

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

/// One row of the post-check-in team activity feed. Nothing persists these —
/// they're assembled from the tables that already record the underlying facts.
enum _FeedKind { checkIn, milestone, breakDay }

class _FeedEvent {
  final _FeedKind kind;
  final String text;
  final DateTime at;
  const _FeedEvent(this.kind, this.text, this.at);
}

class _DashboardPageState extends State<DashboardPage>
    with TickerProviderStateMixin, AutomaticKeepAliveClientMixin {
  /// Kept alive across tab switches: the dashboard loads once and refreshes
  /// only on the triggers in [_onTabShown] and its callers.
  @override
  bool get wantKeepAlive => true;

  final SupabaseClient _supabase = Supabase.instance.client;
  final TeamStreakService _teamStreakService = TeamStreakService();
  final WorkoutService _workoutService = WorkoutService();
  final TeamSyncService _teamSyncService = TeamSyncService();
  final BreakDayService _breakDayService = BreakDayService();
  final NudgeService _nudgeService = NudgeService();
  final _once = RunOnce();
  final _trayOnce = RunOnce();
  // The custom sort tile closes the sort sheet. This State outlives the sheet,
  // so a fresh latch is made each time the sheet opens.
  var _sortCustomLatch = RunOnce();
  Map<String, String> _nicknames = {};

  /// Buddy id -> IANA zone (user_profiles.timezone), for the danger
  /// countdown's deadline. Empty until the first fresh load; every lookup
  /// falls back the way safe_user_tz does.
  Map<String, String> _buddyTimezones = {};

  /// Activity-feed futures per team_streak_id, memoised so a page rebuild
  /// (every carousel swipe) doesn't refire the query. Dropped
  /// on refresh and whenever a live check-in lands for that team — which is
  /// all the realtime wiring the feed needs.
  final Map<String, Future<List<_FeedEvent>>> _teamFeeds = {};

  
  TeamStreak? _highestStreak;
  Set<String> _myCheckInDates = {}; // real check-in dates, fixes heatmap fabrication bug
  Set<String> _myBreakDates = {};   // own uncancelled break_day_usage dates (local-labelled)
  bool _isOnBreakToday = false;     // signed-in user on break for their local today
  Map<String, bool> _buddyOnBreakToday = {}; // buddy id -> on break in THEIR local today
  List<TeamStreak> _allStreaks = [];
  /// What the "All Streaks" list shows: friends only, in the selected order.
  /// In favourites mode this is a *filtered* subset — use [_streakCount] for
  /// labels so a mode with no matches never reads as "no streaks".
  List<TeamStreak> get _listStreaks => sortStreaks(_allStreaks, _streakSortMode);
  List<Map<String, dynamic>> _todaysWorkouts = [];
  bool _hasCheckedInToday = false;
  /// Equipped `ring_color` shop item per team member (userId → color),
  /// covering every visible buddy plus the signed-in user. A member absent
  /// from this map falls back to `_memberColor`'s hashed identity color.
  Map<String, Color> _memberRingColors = {};
  bool _isLoading = true;
  bool _isCheckingIn = false;
  bool _isBreakDialogOpen = false;
  /// The weekly-plan check, per account: answered (not when it was unknown),
  /// read in flight, and whose answer the waiter holds. Static, so it outlives
  /// this State; an account signed in later in the same app run is asked again.
  static final WeeklyPlanCheck _planCheck = WeeklyPlanCheck();

  /// Polls (no network) for a free screen after a check said "later".
  late final WeeklyPlanWaiter _planWaiter = WeeklyPlanWaiter(
    isMounted: () => mounted,
    alreadyHandled: () => _planCheck.waiterDone(_supabase.auth.currentUser?.id),
    screenFree: () => weeklyPlanScreenIsFree(context),
    show: () {
      final uid = _planCheck.waitingFor;
      if (uid != null) _planCheck.markAnswered(uid);
      _showWeeklyPlanDialog();
    },
  );

  /// Whether the check-in banner setting has been read; false until a read
  /// answers, and then retried on a show.
  bool _bannerSettingKnown = false;


  // Header data (avatar, level, coins) — loaded separately from the streak
  // wheel via _loadHeaderData() so a slow query can't block it.
  LevelInfo? _levelInfo;
  int _coinBalance = 0;
  String? _myAvatarId;

  // Count-up motion for the header numbers. What it last showed lives in
  // HeaderMotion.session, so a new HomeScreen (after sign-in) starts from
  // the last shown numbers.
  late final HeaderMotion _motion;
  /// The header was seeded from the saved copy and no server answer has
  /// reached it yet (seededSyncMode, seedSettled).
  bool _seeded = false;
  /// _levelInfo and _coinBalance hold numbers the server answered (a load
  /// that answered both, or an EconomySync change), not only kept ones.
  bool _headerAnswered = false;
  final _coverGate = HeaderCoverGate();
  late final AppLifecycleListener _headerLifecycle;
  /// When the tab was last shown; the header waits [_tabSettle] after it.
  DateTime _shownAt = DateTime.now();

  // Refresh state for shouldRefresh: when the last load started, whether a
  // Realtime event or a finished check-in came in since, and when the app
  // last went to the background.
  DateTime? _lastLoaded;
  bool _dirty = false;
  DateTime? _hiddenAt;
  /// The user's profile timezone (user_profiles.timezone, read with the sort
  /// preferences), which decides when a new day starts; null until read or
  /// when unset, and then the device's calendar is used.
  tz.Location? _myZone;
  Timer? _headerGate;
  bool _reduceMotion = false;
  ModalRoute<dynamic>? _route;

  late ConfettiController _confettiController;
  late ConfettiController _confettiControllerRight;
  int _lastCelebratedStreak = 0;
  
  int _currentCarouselIndex = 0;
  late PageController _carouselController;

  late AnimationController _carouselEntranceController;
  late Animation<double> _carouselEntranceAnimation;
  bool _hasAnimatedEntrance = false;

  List<String> _customStreakOrder = [];
  List<TeamStreak> _customSelection = [];

  /// The sort on screen and the sort saved (see StreakSortController).
  late final StreakSortController _sortCtl = StreakSortController(write: _writeSort);
  StreakSortMode get _streakSortMode => _sortCtl.shown;

  /// The sort the wheel was last drawn for. A sort that gives the same order
  /// leaves the wheel as it is, so this can differ from the sort shown.
  StreakSortMode _wheelSort = StreakSortMode.highestCurrent;


  late List<int> _trayOrder;
  int _trayIndex = 0;
  late PageController _trayController;
  Timer? _countdownTimer;

  /// The minute tick. Nothing at page level listens to it: only the
  /// ClockParts do, so a tick rebuilds the time values and not the page.
  final _minute = ValueNotifier<int>(0);

  // Live check-in feed for the streak rings. RLS on
  // daily_team_checkins already scopes each subscriber to their own teams
  // and accepted friends, so no extra client-side filter is needed here.
  RealtimeChannel? _checkinChannel;

  // Live check-in banner — same trigger as the ring fill above, gated by the
  // live_checkin_banner setting (cached once on load).
  TeamMember? _bannerBuddy;
  int _bannerRequestId = 0;
  bool _bannerViewerCheckedIn = false;


  @override
  void initState() {
    super.initState();
    
    // ✅ Set initial index ONCE
    _currentCarouselIndex = 0;
    
    // ✅ Create controller ONCE
    // 10080 is divisible by every wheel size (1–9), so the wheel always
    // opens focused on item 0 and can swipe both directions infinitely
    _carouselController = PageController(
      viewportFraction: 0.35,
      initialPage: 10080,
    );

    // Workout/coach-tip only — the week card and team-status card are fixed,
    // unshuffled leading pages (see _buildInfoTray).
    _trayOrder = [0, 1]..shuffle();
    _trayController = PageController();

    _sortCtl.addListener(_onSortChanged);
    _subscribeToCheckIns();
    _loadLiveCheckinBannerSetting();

    // ✅ ENTRANCE ANIMATION SETUP
    _carouselEntranceController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    
    _carouselEntranceAnimation = CurvedAnimation(
      parent: _carouselEntranceController,
      curve: Curves.easeOutBack,
    );
    
    _initializeHomePage();
    // The saved header (seeded before Home built), only for its own user.
    final seed = claimHeaderSeed(_supabase.auth.currentUser?.id);
    _myAvatarId = seed?.avatar;
    _seeded = seed?.numbers ?? false;
    _loadHeaderData();
    _motion = HeaderMotion(this, onSettled: _announceHeader);
    // Resuming from the background updates the numbers silently.
    _refreshOsPermission();
    _headerLifecycle = AppLifecycleListener(
      onHide: () {
        _hiddenAt = DateTime.now();
        CoachTipRotation.session.onHidden();
      },
      onResume: () {
        // More than 5 minutes away: stale, refetched now if the tab is
        // showing, else on its next show. A shorter trip refetches nothing.
        final hiddenAt = _hiddenAt;
        _hiddenAt = null;
        if (hiddenAt != null &&
            shouldRefresh(
                lastLoaded: _lastLoaded,
                now: DateTime.now(),
                dirty: _dirty,
                resumed: hiddenAt,
                zone: _myZone)) {
          _lastLoaded = null;
          _refreshIfStale();
        }
        _refreshOsPermission();
        final level = _levelInfo;
        if (mounted && level != null) {
          _motion.sync(level, _coinBalance, HeaderSyncMode.snap);
        }
        // Back from the background: a fresh coach tip, and time values that
        // do not wait for the next minute.
        CoachTipRotation.session.onResumed();
        _minute.value++;
      },
    );
    EconomySync.instance.numbers.addListener(_onEconomyChanged);
    HeaderHold.instance.addListener(_onHeaderHold);
    _countdownTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      _minute.value++;
      _refreshIfNewDay();
    });
    _confettiController = ConfettiController(duration: const Duration(seconds: 3));
    _confettiControllerRight = ConfettiController(duration: const Duration(seconds: 3));
  }

  /// The one first load. It starts at once, beside the cleanup (it reads
  /// workouts, never active_checkin_sessions) and the weekly-plan check.
  Future<void> _initializeHomePage() async {
    await Future.wait([
      _loadStreakData(),
      _workoutService.cleanupOrphanedSessions(),
      _checkWeeklyPlan(),
    ]);

    // Reset broken streaks in background AFTER UI is shown
    _teamStreakService.checkAndResetBrokenStreaks();
  }

  /// Avatar, level and coin balance for the new header row — kept off
  /// _initializeHomePage's await chain so a slow query here can't delay the
  /// streak wheel.
  ///
  /// Each read stands alone: one that failed keeps what the header shows
  /// (the saved copy or an earlier load) and saves nothing; a real 0 is
  /// shown and saved as 0.
  Future<void> _loadHeaderData() async {
    final uid = _supabase.auth.currentUser?.id;
    if (uid == null) return;
    final (avatar, level, coins) = await (
      _readAvatar(uid),
      LevelService().getLevelInfo(),
      CoinService().getBalanceOrNull(),
    ).wait;
    if (!mounted) return;
    final shown = headerAfterLoad(
      level: level,
      coins: coins,
      shownLevel: _levelInfo ?? _motion.target,
      shownCoins: _levelInfo != null ? _coinBalance : (_motion.ready ? _motion.coinTarget : null),
    );
    setState(() {
      if (avatar != null) _myAvatarId = avatar.id;
      if (shown != null) {
        _levelInfo = shown.level;
        _coinBalance = shown.coins;
      }
      if (level != null && coins != null) _headerAnswered = true;
    });
    _syncHeader();
    // Only what the server answered in this load, never what is shown.
    unawaited(saveHeaderAnswers(uid, level: level, coins: coins, avatar: avatar));
  }

  /// The avatar id, or null when the read failed (an id of null is an
  /// account that never picked one).
  Future<({String? id})?> _readAvatar(String uid) async {
    try {
      final row = await _supabase
          .from('user_profiles')
          .select('avatar_id')
          .eq('id', uid)
          .single();
      return (id: row['avatar_id'] as String?);
    } catch (e) {
      if (kDebugMode) debugLog('❌ _loadHeaderData avatar: $e');
      return null;
    }
  }

  /// The server's coins, xp and level changed (EconomySync). Same path as
  /// the header reload: write the numbers, then compare and animate.
  void _onEconomyChanged() {
    // A coin row (Realtime) or a finished check-in anywhere lands here.
    _dirty = true;
    final n = EconomySync.instance.numbers.value;
    if (n == null) return;
    // A server answer: saved as the header's confirmed numbers.
    unawaited(saveHeaderAnswers(_supabase.auth.currentUser?.id, level: n.level, coins: n.coins));
    if (!mounted) return;
    setState(() {
      _levelInfo = n.level;
      _coinBalance = n.coins;
      _headerAnswered = true;
    });
    _syncHeader();
  }

  /// A flow that pays coins finished with its popups: try the header again.
  void _onHeaderHold() {
    if (!HeaderHold.instance.active) _syncHeader();
  }

  /// The one compare-and-animate path for the header numbers. Background and
  /// reduced motion snap; a header covered by a pushed page, a dialog, a sheet
  /// or the workout celebration, or a tab that is still sliding in, waits and
  /// is retried when it is clear.
  void _syncHeader() {
    _headerGate?.cancel();
    final level = _levelInfo;
    if (!mounted || level == null) return;
    final life = WidgetsBinding.instance.lifecycleState;
    final pageCovered = !(_route?.secondaryAnimation?.isDismissed ?? true);
    // Anything above the home route that is not a sliding page (a dialog, a
    // bottom sheet, the celebration overlay), or a flow that is still paying.
    final overlay =
        _route?.isCurrent == false ||
        WorkoutCelebration.isShowing ||
        HeaderHold.instance.active;
    final covered = _coverGate.covered(
      page: pageCovered,
      overlay: overlay,
      now: DateTime.now(),
    );
    final slidIn = DateTime.now().difference(_shownAt) >= _tabSettle;
    var mode = headerSyncMode(
      foreground: life == null || life == AppLifecycleState.resumed,
      reduceMotion: _reduceMotion,
      covered: covered,
      tabReady: LiveEventToast.dashboardTabActive && slidIn,
    );
    // Seeded from the saved copy: lower snaps rather than counting down from
    // the saved numbers, until a server answer is applied or found equal.
    final seededFrom = _motion.target;
    if (_seeded && seededFrom != null) {
      mode = seededSyncMode(mode,
          shown: seededFrom, shownCoins: _motion.coinTarget, level: level, coins: _coinBalance);
      _seeded = !seedSettled(
          answered: _headerAnswered, mode: mode, matches: _motion.matches(level, _coinBalance));
    }
    _motion.sync(level, _coinBalance, mode);
    // A hidden tab does not poll: _onTabShown retries when it comes back.
    if (mode == HeaderSyncMode.hold &&
        !pageCovered &&
        LiveEventToast.dashboardTabActive &&
        !_motion.matches(level, _coinBalance)) {
      _headerGate = Timer(_tabSettle, _syncHeader); // the route listener covers the rest
    }
  }

  static const _tabSettle = Duration(milliseconds: 350);

  /// The shell switched to this tab (a tap, a swipe, or a tap that crosses
  /// it on the way to another tab). Restarts the slide-in gate so the header
  /// waits for the slide as it did when the tab was rebuilt on every visit.
  void _onTabShown() {
    _shownAt = DateTime.now();
    _syncHeader();
    // After the slide, so a tap that only passes this tab (0 to 4) fetches
    // nothing: by then the shell has moved dashboardTabActive on.
    Future.delayed(_tabSettle, () {
      if (mounted) _refreshIfStale();
    });
  }

  /// Refetches when shouldRefresh says so, and only while the tab is
  /// showing: a hidden dashboard waits for its next show, so a load's
  /// snackbar never lands on another tab. The dashboard's own actions call
  /// _loadStreakData directly.
  void _refreshIfStale() {
    if (!LiveEventToast.dashboardTabActive) return;
    // Reads that were unknown at start-up (offline) are asked again.
    if (!_planCheck.answered(_supabase.auth.currentUser?.id)) unawaited(_checkWeeklyPlan());
    if (!_bannerSettingKnown) unawaited(_loadLiveCheckinBannerSetting());
    // A write made elsewhere, or a wheel left empty by a failed load (every
    // account has Coach Max's team), means the data is stale.
    if (dashboardStale || (_allStreaks.isEmpty && !_isLoading)) _lastLoaded = null;
    if (!shouldRefresh(
        lastLoaded: _lastLoaded, now: DateTime.now(), dirty: _dirty, zone: _myZone)) {
      return;
    }
    _loadStreakData(showLoading: false);
    _loadHeaderData(); // the avatar can change on the Profile tab
  }

  /// Local midnight (profile timezone) passed since the last load, so the
  /// "today" state is out of date. Run by the minute tick; it loads nothing
  /// on the same day, and a hidden tab waits for its next show.
  void _refreshIfNewDay() {
    final loaded = _lastLoaded;
    if (loaded != null && dayChanged(loaded, DateTime.now(), zone: _myZone)) {
      _refreshIfStale();
    }
  }

  void _onRouteCover(AnimationStatus status) {
    if (status == AnimationStatus.dismissed) _syncHeader();
  }

  void _announceHeader() {
    final level = _levelInfo;
    if (!mounted || level == null) return;
    SemanticsService.sendAnnouncement(
      View.of(context),
      headerSemanticLabel(_coinBalance, level),
      Directionality.of(context),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.disableAnimationsOf(context);
    final route = ModalRoute.of(context);
    if (route != _route) {
      _route?.secondaryAnimation?.removeStatusListener(_onRouteCover);
      _route = route;
      route?.secondaryAnimation?.addStatusListener(_onRouteCover);
    }
  }

  /// Feeds the bell's dot (NotificationService.osPermission). A failed check
  /// leaves it as it was.
  Future<void> _refreshOsPermission() async {
    try {
      await NotificationService().checkOsPermission();
    } catch (_) {}
  }

  /// Always the Notifications page. Held by _once until it closes.
  Future<void> _onBellTap() => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const NotificationsPage()),
      );

  @override
  void dispose() {
    _once.dispose();
    _trayOnce.dispose();
    _sortCustomLatch.dispose();
    _carouselController.dispose();
    _confettiController.dispose();
    _confettiControllerRight.dispose();
    _carouselEntranceController.dispose();
    EconomySync.instance.numbers.removeListener(_onEconomyChanged);
    HeaderHold.instance.removeListener(_onHeaderHold);
    _headerGate?.cancel();
    _route?.secondaryAnimation?.removeStatusListener(_onRouteCover);
    _headerLifecycle.dispose();
    _motion.dispose();
    _trayController.dispose();
    _countdownTimer?.cancel();
    _planWaiter.cancel();
    _planCheck.reset(); // sign-out: the next account is asked again
    _sortCtl.removeListener(_onSortChanged);
    _sortCtl.dispose();
    _minute.dispose();
    if (_checkinChannel != null) {
      _supabase.removeChannel(_checkinChannel!);
    }
    super.dispose();
  }

  /// Live feed for the streak rings: a buddy's check-in lands here as a
  /// daily_team_checkins INSERT and gets folded into _allStreaks so the
  /// ring fills in without a manual refresh. Table is insert-only in
  /// practice (verified — every write path in this codebase is `.insert`),
  /// so INSERT is the only event this subscribes to.
  void _subscribeToCheckIns() {
    final channel = _supabase
        .channel('dashboard_checkins',
            opts: const RealtimeChannelConfig(private: true))
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'daily_team_checkins',
          callback: (payload) {
            if (kDebugMode) {
              debugLog('📡 Realtime check-in event: ${payload.newRecord}');
            }
            _handleRealtimeCheckIn(payload.newRecord);
          },
        );
    // Coins credited by someone else's action or by the database must reach
    // the open dashboard, so a new coin row re-reads the header numbers.
    final uid = _supabase.auth.currentUser?.id;
    if (uid != null) {
      channel.onPostgresChanges(
        event: PostgresChangeEvent.insert,
        schema: 'public',
        table: 'coin_transactions',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'user_id',
          value: uid,
        ),
        callback: (_) {
          if (mounted) unawaited(EconomySync.instance.refresh());
        },
      );
    }
    _checkinChannel = channel.subscribe();
  }

  /// Read once on load into LiveEventToast.dashboardCheckInBannerEnabled,
  /// which the settings page also writes on save, so the kept-alive dashboard
  /// sees a toggle without a refetch per event.
  Future<void> _loadLiveCheckinBannerSetting() async {
    final settings = await NotificationService().getSettingsOrNull();
    if (settings == null) return; // unknown: the value stays, retried on a show
    _bannerSettingKnown = true;
    if (mounted) {
      // With the banner off the dashboard shows nothing for a check-in, so the
      // generic push toast should take over rather than also staying silent.
      LiveEventToast.dashboardCheckInBannerEnabled =
          settings['live_checkin_banner'] ?? true;
    }
  }

  void _handleRealtimeCheckIn(Map<String, dynamic> row) {
    _dirty = true;
    // Friends lists who checked in today; Profile's streak numbers may move.
    markStale({AppTab.friends});
    markDirty({AppTab.profile});
    final teamStreakId = row['team_streak_id'] as String?;
    final userId = row['user_id'] as String?;
    final checkInDateRaw = row['check_in_date'] as String?;
    final checkInTimeRaw = row['check_in_time'] as String?;
    if (teamStreakId == null || userId == null || checkInDateRaw == null) {
      return;
    }

    DateTime checkInDate;
    try {
      checkInDate = DateTime.parse(checkInDateRaw);
    } catch (_) {
      return;
    }
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    if (!DateTime(checkInDate.year, checkInDate.month, checkInDate.day)
        .isAtSameMomentAs(today)) {
      return; // Not today's check-in (or a differently-dated row) — ignore.
    }

    final streakIndex = _allStreaks.indexWhere((s) => s.id == teamStreakId);
    if (streakIndex == -1) return; // Not one of the viewer's own streaks.

    final streak = _allStreaks[streakIndex];
    if (streak.todayCheckIns.any((ci) => ci.userId == userId)) {
      return; // Already reflected (e.g. own check-in via the normal flow).
    }

    final member = streak.members.firstWhere(
      (m) => m.userId == userId,
      orElse: () =>
          TeamMember(userId: userId, displayName: 'Unknown', isCoachMax: false),
    );
    final checkInTime = checkInTimeRaw != null
        ? DateTime.tryParse(checkInTimeRaw) ?? now
        : now;

    final updatedCheckIns = [
      ...streak.todayCheckIns,
      CheckInStatus(
        userId: userId,
        displayName: member.displayName,
        checkInTime: checkInTime,
        order: streak.todayCheckIns.length + 1,
      ),
    ];

    final updatedStreak = TeamStreak(
      id: streak.id,
      teamId: streak.teamId,
      teamName: streak.teamName,
      teamEmoji: streak.teamEmoji,
      currentStreak: streak.currentStreak,
      longestStreak: streak.longestStreak,
      totalWorkouts: streak.totalWorkouts,
      bestStreak: streak.bestStreak,
      lastWorkoutDate: streak.lastWorkoutDate,
      lastInteractionAt: streak.lastInteractionAt,
      isCoachMaxTeam: streak.isCoachMaxTeam,
      members: streak.members,
      todayCheckIns: updatedCheckIns,
      isFavorite: streak.isFavorite,
    );

    if (!mounted) return;
    final viewerId = _supabase.auth.currentUser?.id;
    final viewerCheckedIn = updatedCheckIns.any((ci) => ci.userId == viewerId);
    setState(() {
      _allStreaks = [..._allStreaks]..[streakIndex] = updatedStreak;
      _teamFeeds.remove(teamStreakId);  // feed reloads with the new check-in
      // Banner is only ever for a buddy's check-in, never the viewer's own
      // (that path already has its own on-screen feedback), and only when
      // the live_checkin_banner setting allows it and this tab is showing
      // (off the tab the push toast shows it). The ring update above
      // always applies.
      if (userId != _supabase.auth.currentUser?.id &&
          LiveEventToast.dashboardOwnsCheckIns) {
        _bannerBuddy = member;
        _bannerRequestId++;
        _bannerViewerCheckedIn = viewerCheckedIn;
      }
    });
  }


  /// The wheel's slots: top 4 friends by the active sort + Coach Max.
  List<dynamic> _wheelItems() {
    _wheelSort = _streakSortMode;
    // Coach Max always has a slot: he's the automatic buddy.
    final coachMaxStreak = _allStreaks.firstWhere(
      (s) => s.isCoachMaxTeam,
      orElse: () => _allStreaks.first,
    );

    // Friends ordered by the selected sort mode (custom keeps stored order)
    final friendStreaks = _streakSortMode == StreakSortMode.custom
      ? _allStreaks.where((s) => !s.isCoachMaxTeam).toList()  // Just filter, don't sort
      : sortStreaks(_allStreaks, _streakSortMode);

    // Top 4 earn a wheel slot — the rest live in the full streak list
    final displayItems = <dynamic>[
      ...friendStreaks.take(kWheelFriendSlots),
      coachMaxStreak,
    ];

    // Pad with "Add a buddy" placeholders so the wheel always has 3+ visuals
    while (displayItems.length < 3) {
      displayItems.add(null);
    }
    return displayItems;
  }

  /// Focused wheel slot, clamped — a sort change can leave the stored index
  /// pointing past the end of a shorter list.
  dynamic _focusedOf(List<dynamic> items) =>
      items[_currentCarouselIndex.clamp(0, items.length - 1)];

  Widget _buildDashboardBody() {
    if (_allStreaks.isEmpty) return _buildNoStreaksCard();
    final displayItems = _wheelItems();

    // ✅ Debug output
    debugLog('📊 WHEEL ITEMS (${displayItems.length}):');
    for (var i = 0; i < displayItems.length; i++) {
      final it = displayItems[i];
      debugLog('  [$i] ${it is TeamStreak ? it.teamName : 'Add Buddy'}');
    }
    debugLog('  Current index: $_currentCarouselIndex');

    // On nearly every phone the persistent week card would push the tray
    // off-screen, so it folds into the tray's own swipe instead — see
    // _buildInfoTray.
    final compact = _isCompactHeight(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildStreakListEntry(),
        _buildBuddyWheel(displayItems),
        _buildSwipeHint(),
        _buildCheckInCard(displayItems),
        // Fills the room the "Take a break day" link vacates once you've
        // checked in. Follows the focused wheel slot, same as the streak
        // count and the "on break today" line above it.
        if (_hasCheckedInToday) ...[
          const SizedBox(height: 8),
          _buildMilestoneCard(displayItems),
        ],
        const SizedBox(height: 8),
        // The tip, the folded week card and the status slot take their value
        // from the clock but change rarely: a tick rebuilds the tray only when
        // one of them has changed.
        ClockPart(
          tick: _minute,
          clock: widget.clock,
          select: (now) => _trayClockValues(displayItems, now),
          builder: (_, now) => _buildInfoTray(displayItems, now),
        ),
        if (!compact) ...[
          const SizedBox(height: 8),
          ClockPart(
            tick: _minute,
            clock: widget.clock,
            select: _dayOf,
            builder: (_, now) => _buildWeekCard(now),
          ),
        ],
        const SizedBox(height: 2),
      ],
    );
  }

  /// True for nearly every phone (a Pixel 7a is ~919dp) — the tray and a
  /// separate persistent week card don't both fit, so the week card folds
  /// into the tray instead. See _buildDashboardBody/_buildInfoTray.
  bool _isCompactHeight(BuildContext context) =>
      MediaQuery.of(context).size.height < 1000;

  /// Mirrors [AppColors.actionGradient]'s formula for the non-orange tokens, so
  /// every clay gradient is derived from one role colour, never a second hex.
  List<Color> _grad(Color base) => [Color.lerp(base, Colors.white, 0.15)!, base];

  /// The raised clay pill/disc treatment, shared by every round control.
  Widget _clayCircleButton({
    required double size,
    required Widget child,
    VoidCallback? onTap,
    String? tooltip,
  }) {
    final c = AppColors.of(context);
    final button = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          colors: [c.claySurfaceLight, c.claySurface],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: c.clayShadow(),
      ),
      child: Center(child: child),
    );
    return GestureDetector(
      onTap: onTap,
      child: tooltip == null ? button : Tooltip(message: tooltip, child: button),
    );
  }

  /// Avatar · coins, spacer, sort · bell — then, once level info has loaded,
  /// a thin XP bar with the LV progress row underneath.
  Widget _buildDashboardHeader() {
    final c = AppColors.of(context);
    final accentPalette = context.watch<AccentThemeProvider>().palette;
    // The header sits directly on the Scaffold body, not a clay slab, so
    // ink is measured against the true background, not the clay step.
    final ink = c.readableForeground(accentPalette.background);
    final levelInfo = _levelInfo;

    // What the header shows and announces: the newest numbers when loaded,
    // else what the session record last showed.
    final shownLevel = levelInfo ?? _motion.target;
    final shownCoins = levelInfo != null ? _coinBalance : _motion.coinTarget;

    void openCoinHistory() => _once.run(() async {
          final goShop = await Navigator.push<bool>(
            context,
            MaterialPageRoute(
                builder: (_) => CoinHistoryPage(initialBalance: shownCoins)),
          );
          if (goShop != true || !mounted) return;
          final homeState = context.findAncestorStateOfType<_HomeScreenState>();
          homeState?._onTabChanged(3);
        });

    return RepaintBoundary(
      child: Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              _clayCircleButton(
                size: 38,
                tooltip: 'Wardrobe',
                onTap: () => _once.run(() async {
                  final saved = await Navigator.push<bool>(
                    context,
                    MaterialPageRoute(builder: (_) => const WardrobePage()),
                  );
                  if (saved == true) _loadHeaderData();
                }),
                child: ClipOval(
                  child: UserAvatar(avatarId: _myAvatarId ?? 'lion', size: 32),
                ),
              ),
              const SizedBox(width: 10),
              Semantics(
                button: true,
                label: 'Coins $shownCoins. Opens coin history',
                excludeSemantics: true,
                onTap: openCoinHistory,
                child: GestureDetector(
                  onTap: openCoinHistory,
                  behavior: HitTestBehavior.opaque,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [c.claySurfaceLight, c.claySurface],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(999),
                          boxShadow: c.clayShadow(),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            HeaderCoinFlip(
                              motion: _motion,
                              child: CoinGlyph(size: 16),
                            ),
                            const SizedBox(width: 7),
                            HeaderCoinCount(
                              motion: _motion,
                              fallback: _coinBalance,
                              style: TextStyle(
                                color: ink,
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                      // Credit pulse: a 2 px outline just outside the pill.
                      Positioned(
                        left: -2,
                        top: -2,
                        right: -2,
                        bottom: -2,
                        child: HeaderCoinRing(
                          motion: _motion,
                          color: accentPalette.accentIcon,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const Spacer(),
              // Sort/filter lived in the old carousel header, which this
              // replaces; it keeps its own control so the modes stay reachable.
              StreakSortButton(
                controller: _sortCtl,
                onTap: () => _once.run(_showSortBottomSheet),
              ),
              const SizedBox(width: 10),
              ValueListenableBuilder<bool?>(
                valueListenable: NotificationService.osPermission,
                builder: (context, permission, _) {
                  final off = bellDotVisible(permission);
                  return _clayCircleButton(
                    size: 46,
                    tooltip: off ? 'Notifications, turned off' : 'Notifications',
                    onTap: () => _once.run(_onBellTap),
                    child: SizedBox(
                      width: 46,
                      height: 46,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          Icon(Icons.notifications_none_rounded,
                              color: ink, size: 22),
                          if (off)
                            // 11 px gold dot, 9 px from the top and 10 from
                            // the right, with a 2 px ring in the button's fill.
                            Positioned(
                              top: 7,
                              right: 8,
                              child: ExcludeSemantics(
                                child: Container(
                                  width: 15,
                                  height: 15,
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: Color.lerp(
                                        c.claySurfaceLight, c.claySurface, 0.5),
                                  ),
                                  child: Container(
                                    width: 11,
                                    height: 11,
                                    decoration: BoxDecoration(
                                        shape: BoxShape.circle, color: c.warn),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
          if (_motion.ready && shownLevel != null) ...[
            const SizedBox(height: 10),
            HeaderXpRow(
              motion: _motion,
              semanticLabel: headerSemanticLabel(shownCoins, shownLevel),
              track: c.claySurface,
              fill: c.streakOrange,
              textColor: c.inkMuted,
              popColor: c.warn, // gold stand-in
            ),
          ],
        ],
      ),
      ),
    );
  }

  /// A member's identifying colour for the check-in ring. Picked from the
  /// accent's own identity roles by a stable hash of the user id, so a person
  /// keeps the same colour across rebuilds and every skin stays on-palette.
  Color _memberColor(String userId, AccentPalette p) {
    final roles = [
      p.avatarRing,
      p.secondaryAccent,
      p.statusInfo,
      p.statusSuccess,
      p.statusWarning,
    ];
    var h = 0;
    for (final unit in userId.codeUnits) {
      h = (h * 31 + unit) & 0x7fffffff;
    }
    return roles[h % roles.length];
  }

  /// The "Your Active Streaks (N)" entry point. The old header pill is gone, so
  /// it takes over the section label directly above the wheel — same position,
  /// same tap target.
  Widget _buildStreakListEntry() {
    final c = AppColors.of(context);
    return GestureDetector(
      onTap: () => _once.run(_showAllStreaks),
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 2),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Flexible(
              child: Text(
                'YOUR ACTIVE STREAKS',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: c.inkMuted,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.5,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 4),
            Icon(Icons.chevron_right_rounded, size: 16, color: c.inkMuted),
          ],
        ),
      ),
    );
  }

  /// ✅ INFINITE CAROUSEL - Wraps around in a circle.
  /// Centre slot focused, neighbours peeking; the 10080 % N wrap is unchanged.
  Widget _buildBuddyWheel(List<dynamic> displayItems) {
    return SizedBox(
      height: 170,
      child: AnimatedBuilder(
        animation: _carouselEntranceAnimation,
        builder: (context, child) {
          return Transform.translate(
            offset: Offset(
              0,
              (1 - _carouselEntranceAnimation.value) * 100,
            ),
            child: Opacity(
              opacity: _carouselEntranceAnimation.value.clamp(0.0, 1.0),
              child: child,
            ),
          );
        },
        child: PageView.builder(
          controller: _carouselController,
          onPageChanged: (index) {
            final newIndex = index % displayItems.length;

            // ✅ ONLY update index - preset stays locked
            setState(() {
              _currentCarouselIndex = newIndex;
            });
          },
          itemCount: null,
          itemBuilder: (context, index) {
            final displayIndex = index % displayItems.length;
            final item = displayItems[displayIndex];

            return AnimatedBuilder(
              animation: _carouselController,
              builder: (context, child) {
                // 0.0 = centred/focused, 1.0 = fully peeked at the edge.
                double d;
                if (_carouselController.position.haveDimensions &&
                    _carouselEntranceAnimation.value >= 1.0) {
                  final page = _carouselController.page ?? index.toDouble();
                  d = (page - index).abs().clamp(0.0, 1.0);
                } else {
                  d = displayIndex == _currentCarouselIndex ? 0.0 : 1.0;
                }

                return Center(
                  child: GestureDetector(
                    onTap: () {
                      _carouselController.animateToPage(
                        index,
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeInOut,
                      );
                    },
                    child: item != null
                        ? _buildCarouselAvatar(item as TeamStreak, d)
                        : _buildAddFriendPlaceholder(d),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }

  Widget _buildSwipeHint() {
    final c = AppColors.of(context);
    return Opacity(
      opacity: 0.6,
      child: Padding(
        padding: const EdgeInsets.only(top: 0, bottom: 2),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.chevron_left_rounded, size: 18, color: c.inkMuted),
            const SizedBox(width: 6),
            Text(
              'swipe to pick a buddy',
              style: TextStyle(color: c.inkMuted, fontSize: 12),
            ),
            const SizedBox(width: 6),
            Icon(Icons.chevron_right_rounded, size: 18, color: c.inkMuted),
          ],
        ),
      ),
    );
  }

  // Whether the focused carousel item's buddy is on break in THEIR local
  // today (server-resolved). Coach Max never takes breaks.
  bool _isBuddyOnBreak(dynamic item) {
    if (item is! TeamStreak || item.isCoachMaxTeam) return false;
    final buddy = _buddyOf(item);
    return buddy != null && _buddyOnBreakToday[buddy.userId] == true;
  }

  static DateTime _dayOf(DateTime now) => DateTime(now.year, now.month, now.day);

  /// What the info tray takes from the clock: the day (folded week card), the
  /// coach tip, and whether the focused buddy is inside the danger window
  /// (which card the status slot shows, and so the tray's page count).
  Object _trayClockValues(List<dynamic> displayItems, DateTime now) {
    final focused = _focusedOf(displayItems);
    final buddy =
        _hasCheckedInToday && focused is TeamStreak && !focused.isCoachMaxTeam
            ? _buddyOf(focused)
            : null;
    return (
      _dayOf(now),
      CoachTipRotation.session.indexAt(now, coachTips.length),
      buddy != null && _dangerRemaining(buddy, now) != null,
    );
  }

  /// [displayItems] is the wheel's items, needed to resolve the leading
  /// team-status card exactly the way the old standalone slab did.
  Widget _buildInfoTray(List<dynamic> displayItems, DateTime now) {
    final c = AppColors.of(context);
    final tip =
        coachTips[CoachTipRotation.session.indexAt(now, coachTips.length)];
    // Same condition/result the old standalone "Team Activity" slab used —
    // just relocated here as the tray's leading, unshuffled page.
    final teamStatusCard =
        _hasCheckedInToday ? _buildTeamStatusCard(displayItems, now) : null;
    final rotating = [_buildTrayWorkout(), _buildTrayCoachTip(tip)];
    final orderedRotating = _trayOrder.map((i) => rotating[i]).toList();

    final cards = <Widget>[
      // Compact-height phones fold the persistent week card into the tray
      // itself instead of also rendering it below — see _buildDashboardBody.
      if (_isCompactHeight(context)) _buildWeekCard(now, inTray: true),
      if (teamStatusCard != null) teamStatusCard,
      ...orderedRotating,
    ];

    return SizedBox(
      // Sized to the tallest real card (the 3-line coach tip) with its
      // trimmed padding — not a clamp: nothing is cut at this height.
      height: 128,
      child: Stack(
        children: [
          PageView(
            controller: _trayController,
            onPageChanged: (i) => setState(() => _trayIndex = i),
            children: cards,
          ),
          if (cards.length > 1)
            Positioned(
              bottom: 8,
              left: 0,
              right: 0,
              child: IgnorePointer(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(cards.length, (i) {
                    final active = i == _trayIndex.clamp(0, cards.length - 1);
                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 250),
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      width: active ? 22 : 9,
                      height: 9,
                      decoration: BoxDecoration(
                        color: active ? c.info : c.claySurfaceLight,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    );
                  }),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// Extra bottom padding for a card centered inside the tray's fixed 128px
  /// box, so its content never reaches into the dots overlay (Positioned
  /// bottom:8, ~17px tall) at the bottom of that box.
  static const _kTrayCardPaddingWithDots = EdgeInsets.fromLTRB(16, 12, 16, 24);

  /// The clay slab every tray card sits on. One shell, so the three card types
  /// can't drift apart in radius, shadow or padding.
  Widget _clayTraySlab({
    required Widget child,
    EdgeInsets? padding,
    Color? color,
  }) {
    final c = AppColors.of(context);
    return Container(
      // 26 (not 20) so clayShadow()'s ~20px reach (offset 6 + blur 14 on the
      // dark side) doesn't bleed all the way to the screen edge — more
      // visible now the Scaffold sits on the true accent background instead
      // of the closer-toned clayBg.
      margin: const EdgeInsets.symmetric(horizontal: 26),
      padding: padding ?? const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: BoxDecoration(
        color: color ?? c.claySurface,
        borderRadius: BorderRadius.circular(26),
        boxShadow: c.clayShadow(),
      ),
      child: child,
    );
  }

  /// Shared [icon] · [label]/[title] · optional [trailing] row used by every
  /// state of the workout tray card. [inTray] centers the content vertically
  /// and reserves room at the bottom for the dots overlay — see
  /// _kTrayCardPaddingWithDots — since only the workout tray states sit
  /// inside that fixed 128px PageView box; _buildMilestoneCard's calls sit
  /// in the normal scrolling column and don't pass it.
  Widget _trayRow({
    required Widget leading,
    required String label,
    required String title,
    Color? labelColor,
    Color? titleColor,
    String? subtitle,
    Widget? trailing,
    Color? color,
    Widget? below,
    bool inTray = false,
  }) {
    final c = AppColors.of(context);
    return _clayTraySlab(
      color: color,
      padding: inTray ? _kTrayCardPaddingWithDots : null,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: inTray ? MainAxisAlignment.center : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              leading,
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 10,
                        color: labelColor ?? c.inkMuted,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.8,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: titleColor ?? c.readableForeground(c.claySurface),
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (subtitle != null)
                      Text(
                        subtitle,
                        style: TextStyle(fontSize: 11, color: c.inkMuted),
                      ),
                  ],
                ),
              ),
              if (trailing != null) ...[const SizedBox(width: 10), trailing],
            ],
          ),
          if (below != null) below,
        ],
      ),
    );
  }

  /// A round clay disc holding an emoji or icon, tinted by [role].
  Widget _trayGlyph(String glyph, {Color? role}) {
    final c = AppColors.of(context);
    return Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          colors: role != null
              ? _grad(role)
              : [c.claySurfaceLight, c.claySurface],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: c.clayShadow(),
      ),
      child: Center(child: Text(glyph, style: const TextStyle(fontSize: 17))),
    );
  }

  /// Vector-icon counterpart to [_trayGlyph] — same round clay disc, an
  /// [Icon] instead of an emoji [Text]. New cards move off emoji per the
  /// approved mockup; existing emoji cards are untouched.
  Widget _trayIconGlyph(IconData icon, {Color? role}) {
    final c = AppColors.of(context);
    return Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          colors: role != null
              ? _grad(role)
              : [c.claySurfaceLight, c.claySurface],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: c.clayShadow(),
      ),
      child: Center(
        child: Icon(
          icon,
          size: 18,
          color: c.readableForeground(role ?? c.claySurface),
        ),
      ),
    );
  }

  /// A small raised clay action pill.
  Widget _trayAction(String text, Color role, FutureOr<void> Function() onTap) {
    final c = AppColors.of(context);
    return GestureDetector(
      onTap: () => _trayOnce.run(onTap),
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 9),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: _grad(role),
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(14),
          boxShadow: c.clayShadow(),
        ),
        child: Text(
          text,
          style: TextStyle(
            color: c.readableForeground(role),
            fontWeight: FontWeight.w700,
            fontSize: 13,
          ),
        ),
      ),
    );
  }

  Widget _trayIconAction(IconData icon, Color role, FutureOr<void> Function() onTap) {
    final c = AppColors.of(context);
    return GestureDetector(
      onTap: () => _trayOnce.run(onTap),
      child: Container(
        padding: const EdgeInsets.all(9),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
            colors: _grad(role),
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          boxShadow: c.clayShadow(),
        ),
        child: Icon(icon, color: c.readableForeground(role), size: 16),
      ),
    );
  }

  Widget _buildTrayWorkout() {
    final c = AppColors.of(context);
    // Only site on the dashboard needing "danger"; AppColors carries no such
    // token, so read it off the palette rather than adding a field for one use.
    final danger = context.watch<AccentThemeProvider>().palette.statusDanger;
    final currentUserId = _supabase.auth.currentUser?.id;

    // ── Priority 1: Active workout (in_progress) ──
    final activeWorkout = _todaysWorkouts.firstWhere(
      // Skip a workout whose MY side is cancelled (same rule as get_workout_card).
      (w) => w['status'] == 'in_progress' &&
          !((w['user_id'] == currentUserId ? w['creator_cancelled'] : w['buddy_cancelled']) ?? false),
      orElse: () => {},
    );
    if (activeWorkout.isNotEmpty) {
      return _trayRow(
        leading: _trayGlyph('🏋️', role: c.streakOrange),
        label: 'ACTIVE WORKOUT',
        title: activeWorkout['workout_type'] ?? 'Workout',
        titleColor: c.streakOrange,
        trailing: _trayAction('Continue', c.streakOrange, () => _checkIn()),
        inTray: true,
      );
    }

    // ── Priority 2: Pending invite ──
    final pendingInvite = _todaysWorkouts.firstWhere(
      (w) => w['buddy_id'] == currentUserId && w['buddy_status'] == 'pending',
      orElse: () => {},
    );
    if (pendingInvite.isNotEmpty) {
      final creator = pendingInvite['creator'];
      final creatorName = creator?['display_name'] ?? 'Someone';
      return _trayRow(
        leading: _trayGlyph('📨', role: c.info),
        label: 'WORKOUT INVITE',
        title: '$creatorName invited you!',
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _trayIconAction(Icons.check, c.success,
                () => _answerInviteDash(pendingInvite['id'], accept: true)),
            const SizedBox(width: 8),
            _trayIconAction(Icons.close, danger,
                () => _answerInviteDash(pendingInvite['id'], accept: false)),
          ],
        ),
        inTray: true,
      );
    }

    // ── Priority 4: Scheduled workout ──
    final scheduled = _todaysWorkouts.firstWhere(
      (w) => w['status'] == 'scheduled',
      orElse: () => {},
    );
    if (scheduled.isNotEmpty) {
      return _buildTodayWorkoutCard(
        title: scheduled['workout_type'] ?? 'Workout',
        subtitle: scheduled['workout_time'],
        trailing: _trayAction('View', c.info, () {
          final homeState = context.findAncestorStateOfType<_HomeScreenState>();
          homeState?._onTabChanged(0);
        }),
      );
    }

    // ── Priority 5: Nothing ──
    return _buildTodayWorkoutCard(
      title: 'No workout scheduled',
      trailing: _trayAction('+ Add', c.info, _showQuickCreateWorkoutDialog),
    );
  }

  /// Vector-icon, vertically-centered variant of the "TODAY'S WORKOUT" tray
  /// card. Bespoke rather than a _trayRow(inTray: true) call: this one
  /// always needs the centering/dots-clearance treatment, so it's baked in
  /// directly rather than threading the flag through.
  Widget _buildTodayWorkoutCard({
    required String title,
    String? subtitle,
    required Widget trailing,
  }) {
    final c = AppColors.of(context);
    return _clayTraySlab(
      padding: _kTrayCardPaddingWithDots,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            children: [
              _trayIconGlyph(Icons.calendar_today_rounded),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "TODAY'S WORKOUT",
                      style: TextStyle(
                        fontSize: 10,
                        color: c.inkMuted,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.8,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: c.readableForeground(c.claySurface),
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (subtitle != null)
                      Text(
                        subtitle,
                        style: TextStyle(fontSize: 11, color: c.inkMuted),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              trailing,
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTrayCoachTip(Map<String, dynamic> tip) {
    final c = AppColors.of(context);
    return _clayTraySlab(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      // Matches the Coach Max wheel avatar — brand identity,
                      // deliberately not an accent token.
                      gradient: const LinearGradient(
                        colors: _kBrandGradient,
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      boxShadow: c.clayShadow(),
                    ),
                    child: const Center(
                      child: Text('🤖', style: TextStyle(fontSize: 16)),
                    ),
                  ),
                  // 🤖 AI disclosure on the avatar, alongside the category pill.
                  const Positioned(
                    bottom: -2,
                    right: -8,
                    child: AiCornerBadge(scale: 0.85),
                  ),
                ],
              ),
              const SizedBox(width: 14),
              Text(
                'Coach Max',
                style: TextStyle(
                  color: c.readableForeground(c.claySurface),
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 10),
              Flexible(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: _grad(c.info),
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(999),
                    boxShadow: c.clayShadow(),
                  ),
                  child: Text(
                    tip['category'],
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: c.readableForeground(c.info),
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Flexible(
            child: Text(
              tip['tip'],
              style: TextStyle(color: c.inkMuted, fontSize: 12.5, height: 1.32),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  /// Persistent (non-swipeable) 7-day week card — see _buildDashboardBody
  /// and _buildInfoTray for where it's placed depending on screen height.
  /// [inTray] is true only for the latter: it centers the content and
  /// reserves room for the dots overlay in that fixed 128px box; the
  /// standalone persistent placement sizes to its own content as before.
  Widget _buildWeekCard(DateTime today, {bool inTray = false}) {
    final c = AppColors.of(context);
    final danger = context.watch<AccentThemeProvider>().palette.statusDanger;
    final monday = today.subtract(Duration(days: today.weekday - 1));
    final week = List.generate(7, (i) => monday.add(Duration(days: i)));
    final checkedCount =
        week.where((d) => !d.isAfter(today) && _isDateCheckedIn(d)).length;

    return _clayTraySlab(
      padding: inTray ? _kTrayCardPaddingWithDots : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: inTray ? MainAxisAlignment.center : MainAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'THIS WEEK',
                style: TextStyle(
                  fontSize: 10,
                  color: c.inkMuted,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                ),
              ),
              Text(
                '$checkedCount/7 days',
                style: TextStyle(
                  fontSize: 11,
                  color: c.success,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children:
                week.map((date) => _buildWeekDay(date, today, danger)).toList(),
          ),
        ],
      ),
    );
  }

  /// One day's circle for [_buildWeekCard]. "Missed" = a past day that's
  /// neither checked in nor a logged break — a day still in progress today
  /// never counts (see isPast).
  Widget _buildWeekDay(DateTime date, DateTime today, Color danger) {
    final c = AppColors.of(context);
    // Straight row lookup for every column, today included — the
    // _hasCheckedInToday special-case caused the boundary-hour double-🔥
    // (see _isDateCheckedIn).
    final isFuture = date.isAfter(today);
    final isToday = _isSameDay(date, today);
    final isPast = !isFuture && !isToday;
    final checked = !isFuture && _isDateCheckedIn(date);
    // Checked-in wins over break: a real workout is the stronger signal.
    final onBreak = !checked && !isFuture && _isDateOnBreak(date);
    final missed = isPast && !checked && !onBreak;

    Widget circle;
    if (checked) {
      circle = Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
            colors: _grad(c.streakOrange),
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          boxShadow: c.clayShadow(),
        ),
        child: const Center(child: Text('🔥', style: TextStyle(fontSize: 14))),
      );
    } else if (onBreak) {
      circle = Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: c.info.withValues(alpha: 0.16),
          border: Border.all(color: c.info, width: 1.5),
        ),
        child: Center(child: Icon(Icons.shield, size: 13, color: c.info)),
      );
    } else if (missed) {
      circle = Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: danger.withValues(alpha: 0.14),
          border: Border.all(color: danger, width: 1.5),
        ),
        child: Center(child: Icon(Icons.close_rounded, size: 13, color: danger)),
      );
    } else {
      // Future.
      circle = Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
            colors: [c.claySurfaceLight, c.claySurface],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          boxShadow: c.clayShadow(inset: true),
        ),
        child: Center(
          child: Text(
            '${date.day}',
            style: TextStyle(fontSize: 10, color: c.inkMuted.withValues(alpha: 0.45)),
          ),
        ),
      );
    }

    // Today keeps its own state's fill/icon and just gains an outer ring, so
    // e.g. a missed Monday that happens to be today still reads as missed.
    if (isToday) {
      circle = Container(
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: c.streakOrange, width: 2),
        ),
        child: circle,
      );
    }

    return Column(
      children: [
        circle,
        const SizedBox(height: 4),
        Text(
          _getDayInitial(date),
          style: TextStyle(
            fontSize: 9,
            color: isToday ? c.streakOrange : c.inkMuted,
            fontWeight: isToday ? FontWeight.w700 : FontWeight.normal,
          ),
        ),
      ],
    );
  }

  /// Clay avatar for one wheel slot. [d] is 0.0 focused → 1.0 fully peeked.
  Widget _buildCarouselAvatar(TeamStreak streak, double d) {
    final c = AppColors.of(context);
    final accentPalette = context.watch<AccentThemeProvider>().palette;
    final size = 108.0 - 32.0 * d;      // 108 focused → 76 peeked
    final focused = d < 0.5;

    // Get the friend's info
    final friendMember = streak.isCoachMaxTeam ? null : _buddyOf(streak);

    // Viewer-relative order for the check-in ring: with the painter's
    // clockwise-from-top layout, the first member lands on the RIGHT arc
    // and the last on the LEFT — so put the signed-in user last, resolved
    // fresh every build rather than trusting streak.members' fetch order.
    final myId = Supabase.instance.client.auth.currentUser?.id;
    final orderedMembers = [
      ...streak.members.where((m) => m.userId != myId),
      ...streak.members.where((m) => m.userId == myId),
    ];

    return Opacity(
      opacity: 1.0 - 0.4 * d,            // 1.0 focused → 0.6 peeked
      child: GestureDetector(
        onTap: focused && !streak.isCoachMaxTeam && friendMember != null
            ? () => _once.run(() => _showBuddyProfile(streak, friendMember))
            : null,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: size + 26,
              height: size + 26,
              child: Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.center,
                children: [
                  Container(
                    width: size,
                    height: size,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        colors: streak.isCoachMaxTeam
                            ? _kBrandGradient
                            : [c.claySurfaceLight, c.claySurface],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      boxShadow: c.clayShadow(),
                    ),
                    child: Center(
                      child: streak.isCoachMaxTeam
                          ? Text('🤖', style: TextStyle(fontSize: size * 0.4))
                          : ClipOval(
                              child: UserAvatar(
                                avatarId: friendMember?.avatarId ?? 'avatar_1',
                                size: size * 0.82,
                                animated: focused,
                              ),
                            ),
                    ),
                  ),

                  // Check-in ring: one arc per team member, filled once they
                  // have checked in today. Reads the same members/todayCheckIns
                  // the old floating chip did — no extra query. Focused slot
                  // only; it fades out as the avatar peeks away.
                  if (focused)
                    IgnorePointer(
                      child: Opacity(
                        opacity: (1 - d * 2).clamp(0.0, 1.0),
                        child: _AnimatedCheckInRing(
                          key: ValueKey('checkin_ring_${streak.id}'),
                          size: size + 14,
                          segmentColors: [
                            for (final m in orderedMembers)
                              _memberRingColors[m.userId] ??
                                  _memberColor(m.userId, accentPalette),
                          ],
                          checkedIn: [
                            for (final m in orderedMembers)
                              streak.todayCheckIns
                                  .any((ci) => ci.userId == m.userId),
                          ],
                          track: c.claySurfaceLight,
                        ),
                      ),
                    ),

                  // 🤖 AI disclosure — Coach Max shares this wheel with real
                  // buddies, so the tag has to ride on the avatar itself.
                  if (streak.isCoachMaxTeam)
                    const Positioned(bottom: 0, child: AiCornerBadge()),

                  // ⭐ Favorite toggle (non-Coach Max, focused slot only)
                  if (!streak.isCoachMaxTeam && focused)
                    Positioned(top: 0, right: 0, child: _starBadge(streak)),

                  // ✓ Team completed today
                  if (!streak.isCoachMaxTeam && streak.isCompleteToday)
                    Positioned(bottom: 0, right: 0, child: _doneBadge()),

                  // 🛡 On-break status dot — human buddies only. Server-resolved
                  // for THEIR local today.
                  if (friendMember != null &&
                      _buddyOnBreakToday[friendMember.userId] == true)
                    Positioned(bottom: 0, left: 0, child: _onBreakBadge()),
                ],
              ),
            ),
            const SizedBox(height: 10),
            // A peeked page is centred ~85% across the screen, so its label has
            // only ~2x(width-centre) before the edge slices it. Sizing to the
            // avatar keeps long names ellipsised rather than cut.
            SizedBox(
              width: size + 30,
              child: Text(
                _getDisplayName(streak),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: c.readableForeground(accentPalette.background),
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _starBadge(TeamStreak streak) {
    final c = AppColors.of(context);
    final on = streak.isFavorite;
    return GestureDetector(
      onTap: () => _once.run(() => _toggleFavorite(streak)),
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
            colors: on ? _grad(c.warn) : [c.claySurfaceLight, c.claySurface],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          boxShadow: c.clayShadow(inset: on),
        ),
        child: Icon(
          on ? Icons.star_rounded : Icons.star_border_rounded,
          size: 18,
          color: on ? c.readableForeground(c.warn) : c.inkMuted,
        ),
      ),
    );
  }

  Widget _doneBadge() {
    final c = AppColors.of(context);
    return Container(
      width: 30,
      height: 30,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          colors: _grad(c.success),
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: c.clayShadow(),
      ),
      child: Icon(Icons.check_rounded,
          size: 17, color: c.readableForeground(c.success)),
    );
  }

  Widget _onBreakBadge() {
    final c = AppColors.of(context);
    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          colors: _grad(c.info),
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: c.clayShadow(),
      ),
      child: Icon(Icons.shield, size: 14, color: c.readableForeground(c.info)),
    );
  }

  /// The other member of a two-person team, or null if the viewer is the only
  /// member. `get_user_streaks` filters solo teams out (migration
  /// 20260821224035), so null should be unreachable from the RPC path — but
  /// the old `orElse: members.first` failed by handing back the *viewer*, i.e. showing
  /// you to yourself as your own buddy. Failing visibly beats failing silently.
  TeamMember? _buddyOf(TeamStreak streak) {
    final currentUserId = Supabase.instance.client.auth.currentUser?.id;
    for (final m in streak.members) {
      if (m.userId != currentUserId) return m;
    }
    return null;
  }

  // ✅ HELPER METHOD: Get display name
  String _getDisplayName(dynamic item) {
    if (item == null) {
      return 'Add a Workout Buddy!';
    }
    
    final streak = item as TeamStreak;
    if (streak.isCoachMaxTeam) {
      return streak.teamName;  // "Coach Max"
    }
    
    // Get friend info
    final friendMember = _buddyOf(streak);
    if (friendMember == null) return 'Add a Workout Buddy!';

    // Check for nickname first!
    final nickname = _nicknames[friendMember.userId];
    if (nickname != null && nickname.isNotEmpty) {
      return nickname;  // Show nickname
    }
    
    return friendMember.displayName;  // Fall back to display name
  }

  Widget _buildAddFriendPlaceholder(double d) {
    final c = AppColors.of(context);
    final size = 108.0 - 32.0 * d;
    return Opacity(
      opacity: 1.0 - 0.4 * d,
      child: GestureDetector(
        onTap: () {
          // Navigate to Buddies tab. Was only mutating _selectedIndex
          // directly, which re-highlights the bottom nav bar but never
          // moves the PageView -- _onTabChanged() is the method that
          // actually does both (confirmed via _GymBuddyNavBar's own
          // onTabSelected wiring).
          HapticFeedback.selectionClick();
          final homeState = context.findAncestorStateOfType<_HomeScreenState>();
          homeState?._onTabChanged(1); // Switch to Buddies tab
        },
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: size + 18,
              height: size + 18,
              child: Center(
                child: Container(
                  width: size,
                  height: size,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: [c.claySurfaceLight, c.claySurface],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    boxShadow: c.clayShadow(inset: true),
                  ),
                  child: Icon(Icons.person_add_rounded,
                      size: size * 0.34, color: c.inkMuted),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'Add Buddy',
              style: TextStyle(
                color: c.inkMuted,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Social nudge built from the focused streak's own check-ins. Presentation
  /// only — [CheckInStatus] already carries name, time and order.
  String? _nudgeCopy(TeamStreak streak) {
    if (_hasCheckedInToday) return null;
    final currentUserId = Supabase.instance.client.auth.currentUser?.id;
    final others = streak.todayCheckIns
        .where((c) => c.userId != currentUserId)
        .toList()
      ..sort((a, b) => a.order.compareTo(b.order));
    if (others.isEmpty) return null;

    final first = _nicknames[others.first.userId] ?? others.first.displayName;
    if (others.length == 1) return '$first already checked in, keep pace';
    return '$first +${others.length - 1} already checked in, keep pace';
  }

  /// ✅ The clay check-in slab: focused streak's name and count, the nudge,
  /// the CTA, and the Take a Break escape hatch.
  Widget _buildCheckInCard(List<dynamic> displayItems) {
    final c = AppColors.of(context);
    final ink = c.readableForeground(c.claySurface);
    final focused = _focusedOf(displayItems);
    final streak = focused is TeamStreak ? focused : null;
    final nudge = streak == null ? null : _nudgeCopy(streak);

    return Container(
      // 26, matching _clayTraySlab — keeps clayShadow()'s ~20px reach clear
      // of the screen edge now that the Scaffold sits on the true accent
      // background (see _clayTraySlab's margin comment).
      margin: const EdgeInsets.symmetric(horizontal: 26),
      padding: const EdgeInsets.fromLTRB(22, 16, 22, 14),
      decoration: BoxDecoration(
        color: c.claySurface,
        borderRadius: BorderRadius.circular(26),
        boxShadow: c.clayShadow(),
      ),
      child: Column(
        children: [
          // The wheel already names and pictures whoever is focused, so the
          // card leads with the number instead of repeating the name.
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              streak != null
                  ? '${streak.currentStreak} DAY STREAK'
                  : '— DAY STREAK',
              maxLines: 1,
              style: TextStyle(
                color: streak != null ? ink : c.inkMuted,
                fontSize: 36,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.5,
              ),
            ),
          ),
          if (_isBuddyOnBreak(focused)) ...[
            const SizedBox(height: 6),
            Text(
              'on break today',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: c.info,
              ),
            ),
          ],
          if (nudge != null) ...[
            const SizedBox(height: 10),
            Text(
              nudge,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: c.streakOrange, // actionGradient's base stop
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          const SizedBox(height: 16),
          _buildCheckInCta(),
          if (_isOnBreakToday) ...[
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.shield, size: 13, color: c.info),
                const SizedBox(width: 5),
                Text(
                  'Your streak is protected today.',
                  style: TextStyle(fontSize: 12, color: c.inkMuted),
                ),
              ],
            ),
          ],
          // Take a Break — subtle text link
          if (!_hasCheckedInToday) ...[
            const SizedBox(height: 12),
            GestureDetector(
              onTap: _showTakeBreakDialog,
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text(
                  'Take a break day',
                  style: TextStyle(
                    color: c.inkMuted,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCheckInCta() {
    final c = AppColors.of(context);
    final done = _hasCheckedInToday;
    // Done reads as a status, not an action, so it drops the action gradient.
    final fill = done ? _grad(c.success) : c.actionGradient;
    final label = c.readableForeground(fill.last);

    return PressScale(
      onTap: done || _isCheckingIn ? null : _checkIn,
      child: Container(
        width: double.infinity,
        height: 58,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: fill,
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(19),
          boxShadow: c.clayShadow(inset: done),
        ),
        child: Center(
          child: _isCheckingIn
              ? SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 3, color: label),
                )
              : Text(
                  done ? 'Checked In' : 'Check In',
                  style: TextStyle(
                    color: label,
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                  ),
                ),
        ),
      ),
    );
  }

  // ── Post-check-in cards ─────────────────────────────────────────────────
  // Two slabs that only exist once you've checked in, filling the space the
  // "Take a break day" link leaves behind. Both read the focused wheel slot,
  // so a swipe re-renders them with no extra plumbing.

  /// Streak danger opens at 18:00 in the BUDDY's own zone — the same cutoff
  /// coach-max-cron's PART 3 now fires on, so the card and the push agree.
  static const int _kDangerHour = 18;

  /// What safe_user_tz() falls back to for a missing or null timezone. Kept
  /// identical to the DB helper and to coach-max-cron's FALLBACK_TZ.
  static const String _kFallbackTz = 'Europe/Dublin';

  static bool _timeZonesLoaded = false;

  /// The buddy's zone, resolved the way safe_user_tz would: their stored IANA
  /// name, else the shared fallback. An unrecognised name falls back too
  /// rather than throwing mid-build.
  tz.Location _zoneOf(String userId) {
    _loadTimeZones();
    try {
      return tz.getLocation(_buddyTimezones[userId] ?? _kFallbackTz);
    } catch (_) {
      return tz.getLocation(_kFallbackTz);
    }
  }

  static void _loadTimeZones() {
    if (!_timeZonesLoaded) {
      tzdata.initializeTimeZones();
      _timeZonesLoaded = true;
    }
  }

  /// The signed-in user's own zone, as the server's safe_user_tz reads it.
  /// Unset or unrecognised: null, so the day follows the device calendar
  /// (the localTodayString frame) rather than the server's fallback zone.
  tz.Location? _profileZone(String? name) {
    if (name == null) return null;
    _loadTimeZones();
    try {
      return tz.getLocation(name);
    } catch (_) {
      return null;
    }
  }

  String _displayName(String userId, String fallback) =>
      _nicknames[userId] ?? fallback;

  /// Time left before the streak breaks for [buddy], or null while it isn't
  /// yet their evening — resolved entirely in the buddy's own zone.
  Duration? _dangerRemaining(TeamMember buddy, DateTime now) =>
      dangerRemainingAt(
        tz.TZDateTime.from(now, _zoneOf(buddy.userId)),
        cutoffHour: _kDangerHour,
      );

  String _feedAge(DateTime now, DateTime at) {
    final d = now.difference(at);
    if (d.inMinutes < 1) return 'just now';
    if (d.inMinutes < 60) return '${d.inMinutes}m ago';
    if (d.inHours < 24) return '${d.inHours}h ago';
    return '${d.inDays}d ago';
  }

  /// CARD 1 — one slot, two rendered states: the danger countdown or the
  /// activity feed. "Secured" is still a real resolved state out of
  /// [resolveStatusSlot] (its own regression coverage in
  /// test/status_slot_test.dart depends on that), it just has no card of its
  /// own anymore — the slot renders nothing for it, and the caller omits the
  /// slot's spacing too so no gap is left behind.
  ///
  /// The danger window owns the slot: inside it the card reports where the
  /// team's streak stands, and outside it the feed has the slot to itself.
  Widget? _buildTeamStatusCard(List<dynamic> displayItems, DateTime now) {
    final focused = _focusedOf(displayItems);
    if (focused is! TeamStreak) return const SizedBox.shrink();

    // Coach Max never reaches either status variant — there's no real buddy
    // whose check-in the streak is waiting on. His team falls through to the
    // feed, which still has his daily check-ins and yours to show.
    final buddy = focused.isCoachMaxTeam ? null : _buddyOf(focused);
    final remaining = buddy == null ? null : _dangerRemaining(buddy, now);
    switch (resolveStatusSlot(
      hasBuddy: buddy != null,
      buddyCheckedIn: buddy != null &&
          focused.todayCheckIns.any((ci) => ci.userId == buddy.userId),
      inDangerWindow: remaining != null,
    )) {
      case StatusSlot.danger:
        // The countdown text and the bar move every minute. The window closing
        // is the tray's business (_trayClockValues), so a tick that lands on
        // the deadline shows zero until the tray swaps the card.
        return ClockPart(
          tick: _minute,
          clock: widget.clock,
          builder: (_, now) => _buildStreakDangerCard(
            buddy!,
            _dangerRemaining(buddy, now) ?? Duration.zero,
          ),
        );
      case StatusSlot.secured:
        return null;
      case StatusSlot.feed:
        return _buildTeamFeedCard(focused);
    }
  }

  /// Progress-bar colour at low urgency (just entered the danger window).
  static const _kDangerBarStart = Color(0xFFFFB199);

  /// Progress-bar colour at high urgency (deadline imminent).
  static const _kDangerBarEnd = Color(0xFFFF3B30);

  Widget _buildStreakDangerCard(TeamMember buddy, Duration remaining) {
    final c = AppColors.of(context);
    final danger = context.read<AccentThemeProvider>().palette.statusDanger;
    final surface = c.tint(danger, surface: c.claySurface);
    // Fills up (and deepens in colour) toward the deadline — the inverse of
    // `remaining`, off the same window/value the "Xh Ym" text reads, so it
    // recomputes on that text's 1-minute tick (the card sits in a ClockPart)
    // with no rebuild trigger of its own.
    final totalWindowMinutes =
        const Duration(hours: 24 - _kDangerHour).inMinutes;
    final elapsed =
        (1 - remaining.inMinutes / totalWindowMinutes).clamp(0.0, 1.0);
    final barColor = Color.lerp(_kDangerBarStart, _kDangerBarEnd, elapsed)!;

    // Bespoke layout, not _trayRow: the nudge button needs its own full-width
    // row, which _trayRow's single Row-with-trailing shape can't express
    // without changing every other card built on it.
    return _clayTraySlab(
      color: surface,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _trayIconGlyph(Icons.hourglass_bottom_rounded, role: danger),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'STREAK AT RISK',
                      style: TextStyle(
                        fontSize: 10,
                        color: danger,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.8,
                      ),
                    ),
                    const SizedBox(height: 3),
                    // The focused buddy wheel above already identifies who —
                    // no name here.
                    Text(
                      "Hasn't checked in yet",
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: c.readableForeground(surface),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Streak breaks in ${remaining.inHours}h ${remaining.inMinutes % 60}m',
                      style: TextStyle(fontSize: 11, color: c.inkMuted),
                    ),
                  ],
                ),
              ),
            ],
          ),
          _thinTrack(elapsed, barColor),
          const SizedBox(height: 10),
          _fullWidthTrayButton('Nudge →', danger, () => _nudgeBuddy(buddy)),
        ],
      ),
    );
  }

  /// Full-width counterpart to [_trayAction], for a card whose button gets
  /// its own row instead of sitting beside the title.
  Widget _fullWidthTrayButton(String text, Color role, FutureOr<void> Function() onTap) {
    final c = AppColors.of(context);
    return GestureDetector(
      onTap: () => _trayOnce.run(onTap),
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: double.infinity,
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(vertical: 11),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: _grad(role),
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(14),
          boxShadow: c.clayShadow(),
        ),
        child: Text(
          text,
          style: TextStyle(
            color: c.readableForeground(role),
            fontWeight: FontWeight.w700,
            fontSize: 13,
          ),
        ),
      ),
    );
  }

  Widget _buildTeamFeedCard(TeamStreak streak) {
    final c = AppColors.of(context);
    return FutureBuilder<List<_FeedEvent>>(
      future: _teamFeeds.putIfAbsent(streak.id, () => _loadTeamFeed(streak)),
      builder: (context, snapshot) {
        final events = snapshot.data ?? const <_FeedEvent>[];
        // Still loading, or a team with nothing to say yet — an empty slab
        // reads as a bug, so the card simply isn't there.
        if (events.isEmpty) return const SizedBox.shrink();
        return _clayTraySlab(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'TEAM ACTIVITY',
                style: TextStyle(
                  fontSize: 10,
                  color: c.inkMuted,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                ),
              ),
              const SizedBox(height: 6),
              for (final e in events) _buildFeedRow(e),
            ],
          ),
        );
      },
    );
  }

  Widget _buildFeedRow(_FeedEvent e) {
    final c = AppColors.of(context);
    final palette = context.read<AccentThemeProvider>().palette;
    final (icon, role) = switch (e.kind) {
      _FeedKind.checkIn => (Icons.local_fire_department_rounded, c.streakOrange),
      _FeedKind.milestone => (Icons.emoji_events_rounded, palette.statusWarning),
      _FeedKind.breakDay => (Icons.nightlight_round, c.info),
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 15, color: role),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              e.text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: c.readableForeground(c.claySurface),
              ),
            ),
          ),
          const SizedBox(width: 8),
          ClockPart(
            tick: _minute,
            clock: widget.clock,
            builder: (_, now) => Text(
              _feedAge(now, e.at),
              style: TextStyle(fontSize: 11, color: c.inkMuted),
            ),
          ),
        ],
      ),
    );
  }

  /// CARD 2 — the focused team's next streak milestone.
  Widget _buildMilestoneCard(List<dynamic> displayItems) {
    final focused = _focusedOf(displayItems);
    if (focused is! TeamStreak) return const SizedBox.shrink();

    final role = context.read<AccentThemeProvider>().palette.statusWarning;
    final current = focused.currentStreak;
    final next = getNextMilestone(current);

    if (next == null) {
      return _trayRow(
        leading: _trayGlyph('👑', role: role),
        label: 'MILESTONES',
        labelColor: role,
        title: 'Every milestone cleared',
        subtitle: '$current days and counting',
      );
    }

    return _trayRow(
      leading: _trayGlyph('🏆', role: role),
      label: 'NEXT MILESTONE',
      labelColor: role,
      title: '${next.name} · ${next.target} days',
      subtitle: next.toGo == 1 ? '1 day to go' : '${next.toGo} days to go',
      below: _thinTrack(next.progress, role),
    );
  }

  Widget _thinTrack(double value, Color role) {
    final c = AppColors.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: LinearProgressIndicator(
          value: value,
          minHeight: 6,
          backgroundColor: c.claySurfaceLight,
          color: role,
        ),
      ),
    );
  }

  Future<void> _nudgeBuddy(TeamMember buddy) async {
    final name = _displayName(buddy.userId, buddy.displayName);
    final result = await _nudgeService.sendNudge(
      targetUserId: buddy.userId,
      targetDisplayName: name,
    );
    if (!mounted) return;

    final c = AppColors.of(context);
    final palette = context.read<AccentThemeProvider>().palette;
    final (message, background) = switch (result) {
      NudgeResult.sent => ('Nudge sent to $name.', c.success),
      NudgeResult.alreadySent => ('Already nudged $name today', c.inkMuted),
      NudgeResult.tooEarly =>
        ('Too early to nudge — try after 10am', palette.statusWarning),
      NudgeResult.error => ('Couldn\'t send that nudge', palette.statusDanger),
    };
    if (result == NudgeResult.sent) HapticFeedback.mediumImpact();

    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message),
      backgroundColor: background,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));
  }

  /// The focused team's last few events, built entirely from tables that
  /// already record them: daily_team_checkins for check-ins, break_day_usage
  /// for break days (both are teammate-readable under existing RLS). No events
  /// table and no new RPC — milestones aren't stored anywhere, so they're
  /// derived in [_deriveMilestones].
  Future<List<_FeedEvent>> _loadTeamFeed(TeamStreak streak) async {
    final me = _supabase.auth.currentUser?.id;
    final memberIds = streak.members.map((m) => m.userId).toList();

    String who(String id) {
      if (id == me) return 'You';
      final member = streak.members.firstWhere(
        (m) => m.userId == id,
        orElse: () =>
            TeamMember(userId: id, displayName: 'Buddy', isCoachMax: false),
      );
      return _displayName(id, member.displayName);
    }

    try {
      final (checkIns, breaks) = await (
        _supabase
            .from('daily_team_checkins')
            .select('user_id, check_in_date, check_in_time')
            .eq('team_streak_id', streak.id)
            .order('check_in_time', ascending: false)
            .limit(40),
        _supabase
            .from('break_day_usage')
            .select('user_id, break_date')
            .inFilter('user_id', memberIds)
            .isFilter('cancelled_at', null)
            .order('break_date', ascending: false)
            .limit(6),
      ).wait;

      final events = <_FeedEvent>[];

      for (final row in checkIns) {
        final raw = (row['check_in_time'] ?? row['check_in_date']) as String?;
        final at = raw == null ? null : DateTime.tryParse(raw);
        final userId = row['user_id'] as String?;
        if (at == null || userId == null) continue;
        events.add(_FeedEvent(
          _FeedKind.checkIn,
          '${who(userId)} checked in',
          at.toLocal(),
        ));
      }

      for (final row in breaks) {
        final at = DateTime.tryParse(row['break_date'] as String? ?? '');
        final userId = row['user_id'] as String?;
        if (at == null || userId == null) continue;
        events.add(_FeedEvent(
          _FeedKind.breakDay,
          '${who(userId)} took a break day',
          at,
        ));
      }

      events.addAll(_deriveMilestones(streak, checkIns));
      events.sort((a, b) => b.at.compareTo(a.at));
      return events.take(4).toList();
    } catch (e) {
      if (kDebugMode) debugLog('❌ Team feed load failed: $e');
      return [];
    }
  }

  /// Milestones live in no table, so they're reconstructed: one complete day
  /// (every member checked in) is one streak day, so the Nth-newest complete
  /// day sat at `currentStreak - N`. Walks back only while the dates stay
  /// consecutive — a gap means that run had already ended.
  // ponytail: only sees the fetched window (~40 rows). If milestones ever need
  // to survive further back than that, that's when an events table earns its
  // keep.
  List<_FeedEvent> _deriveMilestones(
      TeamStreak streak, List<Map<String, dynamic>> checkIns) {
    if (streak.currentStreak <= 0 || streak.members.isEmpty) return [];

    final byDate = <String, Set<String>>{};
    for (final row in checkIns) {
      final date = row['check_in_date'] as String?;
      final userId = row['user_id'] as String?;
      if (date == null || userId == null) continue;
      byDate.putIfAbsent(date, () => <String>{}).add(userId);
    }

    final complete = byDate.entries
        .where((e) => e.value.length >= streak.members.length)
        .map((e) => DateTime.tryParse(e.key))
        .whereType<DateTime>()
        .toList()
      ..sort((a, b) => b.compareTo(a));

    final events = <_FeedEvent>[];
    for (var i = 0; i < complete.length; i++) {
      if (i > 0 && complete[i - 1].difference(complete[i]).inDays != 1) break;
      final name = kStreakMilestones[streak.currentStreak - i];
      if (name != null) {
        events.add(_FeedEvent(
          _FeedKind.milestone,
          '$name — ${streak.currentStreak - i}-day streak',
          complete[i],
        ));
      }
    }
    return events;
  }

  Future<void> _showTakeBreakDialog() async {
    // Guard against a second tap re-entering this method while a dialog from
    // a prior call is still open or its pre-checks are still in flight —
    // without it, rapid double-tap stacks two Dialogs and Cancel only closes
    // the top one.
    if (_isBreakDialogOpen) return;
    _isBreakDialogOpen = true;
    try {
      await _showTakeBreakDialogBody();
    } finally {
      _isBreakDialogOpen = false;
    }
  }

  Future<void> _showTakeBreakDialogBody() async {
    // ✅ NEW: Can't take break if already checked in
    if (_hasCheckedInToday) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('You already checked in today! Can\'t use a break day.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final currentUserId = Supabase.instance.client.auth.currentUser?.id;
    if (currentUserId == null) return;

    // The user's own local date key for the break_date write — matches
    // break_day_service and safe_user_tz() server-side.
    final today = localTodayString();

    // Local week boundary (via getWeekStart), same frame as the now-local
    // break_date keys.
    final startOfWeekStr = _breakDayService
        .getWeekStart(DateTime.now())
        .toIso8601String()
        .split('T')[0];

    // All three queries depend only on currentUserId + these locally-computed
    // dates, not on each other's results, so they can fire concurrently
    // instead of round-tripping one at a time.
    final (existingBreak, userProfile, breaksThisWeek) = await (
      // Already took break today (uncancelled — a cancelled break can be
      // legitimately re-declared through the capped RPC)
      Supabase.instance.client
          .from('break_day_usage')  // ✅ FIXED: Changed from 'break_days'
          .select()
          .eq('user_id', currentUserId)
          .eq('break_date', today)
          .isFilter('cancelled_at', null)
          .maybeSingle(),
      // Weekly plan, to know the goal breaks are counted against
      Supabase.instance.client
          .rpc('get_my_profile')
          .select('current_weekly_goal')
          .single(),
      // Breaks already taken this week
      Supabase.instance.client
          .from('break_day_usage')  // ✅ FIXED: Changed from 'break_days'
          .select()
          .eq('user_id', currentUserId)
          .gte('break_date', startOfWeekStr),
    ).wait;

    if (existingBreak != null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('You already took a break today!'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final weeklyBreakGoal = userProfile['current_weekly_goal'] ?? 2;
    final breakDaysLeft = weeklyBreakGoal - breaksThisWeek.length;

    if (!mounted) return;

    // Show dialog
    final c = AppColors.of(context);
    final accentPalette = context.read<AccentThemeProvider>().palette;
    final hasBreaks = breakDaysLeft > 0;
    final role = hasBreaks ? accentPalette.statusInfo : accentPalette.statusDanger;
    final roleTint = c.tint(role, surface: c.claySurface);
    final onCard = c.readableForeground(c.claySurface);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: c.claySurface,
            borderRadius: BorderRadius.circular(28),
            boxShadow: c.clayShadow(),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: roleTint,
                      borderRadius: BorderRadius.circular(18),
                      boxShadow: c.clayShadow(inset: true),
                    ),
                    child: Icon(Icons.bedtime, color: role, size: 26),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Take a Break Day?',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: onCard,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: roleTint,
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: c.clayShadow(inset: true),
                ),
                child: Row(
                  children: [
                    Text(
                      '$breakDaysLeft',
                      style: TextStyle(
                        fontSize: 48,
                        fontWeight: FontWeight.bold,
                        color: role,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Text(
                        'break day${breakDaysLeft == 1 ? '' : 's'} left\nuntil next week',
                        style: TextStyle(
                          fontSize: 14,
                          color: role,
                          fontWeight: FontWeight.w600,
                          height: 1.3,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Text(
                hasBreaks
                    ? 'Taking a break counts as your workout for today without breaking your streak.'
                    : 'You\'ve used all your break days this week. Check back Monday!',
                style: TextStyle(
                  fontSize: 14,
                  height: 1.5,
                  color: c.subtleText,
                ),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: Text('Cancel', style: TextStyle(color: c.subtleText)),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: hasBreaks ? c.clayShadow() : null,
                    ),
                    child: ElevatedButton(
                      onPressed: hasBreaks
                          ? () => Navigator.pop(context, true)
                          : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: accentPalette.statusInfo,
                        foregroundColor: c.readableForeground(accentPalette.statusInfo),
                        disabledBackgroundColor: c.sectionBackground,
                        disabledForegroundColor: c.subtleText,
                        elevation: 0,
                        shadowColor: Colors.transparent,
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: const Text('Yes, Take Break'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    if (confirmed == true) {
      // Server-authoritative: the declare_break_day RPC enforces the weekly
      // cap and the today-only rule (direct inserts are closed by RLS).
      final declared = await _breakDayService.declareBreakDay();

      if (!mounted) return;

      if (declared) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Row(
              children: [
                Icon(Icons.bedtime, color: Colors.white),
                SizedBox(width: 12),
                Expanded(
                  child: Text('Break day taken. Your streak is safe.'),
                ),
              ],
            ),
            backgroundColor: Colors.blue[700],
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Couldn\'t take a break day — you may have used this week\'s allowance.'),
            backgroundColor: Colors.orange,
          ),
        );
      }

      _loadStreakData();
    }
  }

  void _showCustomModeSelector() async {
    // Get all friend streaks (excluding Coach Max)
    final allFriends = _allStreaks.where((s) => !s.isCoachMaxTeam).toList();
    
    if (allFriends.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add some workout buddies first!')),
      );
      return;
    }
    
    // Show full-screen custom selector
    final result = await Navigator.push<List<TeamStreak>>(
      context,
      MaterialPageRoute(
        builder: (context) => CustomStreakSelector(
          availableStreaks: allFriends,
          currentSelection: _customSelection.isEmpty ? null : _customSelection,
        ),
      ),
    );
    
    // ✅ User pressed SAVE with 3 buddies selected
    if (result != null && result.isNotEmpty) {
      debugLog('💾 Custom selection received: ${result.map((s) => s.teamName).join(", ")}');
      
      // ✅ 1. Update state (the sort shows at once)
      setState(() {
        _customSelection = result;
        _currentCarouselIndex = 0;  // Reset to top item
      });
      if (_carouselController.hasClients) {
        _carouselController.jumpToPage(10080);
      }

      // ✅ 2. Save both the mode AND the order, through the one save path
      final saved = await _sortCtl.choose(StreakSortMode.custom,
          customOrder: result.map((s) => s.teamId).toList());
      debugLog('💾 Custom mode with order ${saved ? 'saved' : 'not saved'}: ${result.map((s) => s.teamId).join(", ")}');

      // ✅ 3. Tell the user either way
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          customOrderSnackBar(saved: saved, colors: AppColors.of(context)),
        );
      }

      // ✅ 4. Reload data to apply the new order
      await _loadStreakData();
      
      // ✅ 5. Jump carousel to center after a brief delay
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_carouselController.hasClients && mounted) {
          _carouselController.jumpToPage(1000);
          debugLog('🎯 Jumped to center after custom selection');
        }
      });
    } else {
      // User cancelled or didn't fill all 3 slots
      debugLog('❌ Custom selection cancelled or incomplete');
    }
  }

  Future<void> _loadStreakData({bool showLoading = true}) async {
    // Any load answers every refresh trigger raised before it started.
    _lastLoaded = DateTime.now();
    _dirty = false;
    dashboardStale = false;
    try {
      await _fetchStreakData(showLoading);
    } catch (e) {
      _lastLoaded = null; // a load that threw (offline) is retried on the next show
      if (!isNetworkError(e)) rethrow;
      // The network was unavailable: unknown, not an error. What is on
      // screen stays (a skeleton over a wheel is lifted).
      if (mounted && _isLoading && _allStreaks.isNotEmpty) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _fetchStreakData(bool showLoading) async {
    // ── STEP 1: First paint from the saved copy ─────────────
    // Only the first load. It runs beside the requests below: a read of
    // local storage ends long before the first answer. A background refresh
    // (showLoading false) keeps the current wheel on screen.
    if (showLoading) {
      if (!_restoreTried) {
        _restoreTried = true;
        unawaited(_restoreSaved());
      }
      if (mounted) setState(() => _isLoading = true);
    }

    // Each read below that fails answers null: the screen keeps that part
    // (dropping a "today" part kept from an earlier day) and the save writes
    // nothing for it. Offline, the next show retries.
    var offline = false;
    Future<T?> known<T>(String label, Future<T> read) =>
        read.then<T?>((v) => v, onError: (Object e, StackTrace st) {
          if (isNetworkError(e)) offline = true;
          debugLog('⚠️ Dashboard read failed, kept as shown: $e');
          reportNonFatal(e, st, label);
          return null;
        });

    // ── STEP 2: Load preferences (fast, single query) ───────
    final userId = Supabase.instance.client.auth.currentUser?.id;
    ({String sort, List<String> customOrder, String? zone})? prefsAnswer;
    if (userId != null) {
      try {
        final prefs = await Supabase.instance.client
            .rpc('get_my_profile')
            .select('preferred_streak_sort, custom_streak_order, timezone')
            .single();
  
        _myZone = _profileZone(prefs['timezone'] as String?);
        profileZone = _myZone; // the other kept-alive tabs judge the day by it
        // One of the four, else Highest Streak. Never written back.
        _sortCtl.loaded(prefs['preferred_streak_sort']);
  
        if (_streakSortMode == StreakSortMode.custom &&
            prefs['custom_streak_order'] != null) {
          _customStreakOrder = List<String>.from(prefs['custom_streak_order']);
          debugLog('📥 Loaded custom order: ${_customStreakOrder.length} team IDs');
        } else {
          _customStreakOrder = [];
        }
        debugLog('📥 Loaded sort mode: ${_streakSortMode.displayName}');
        prefsAnswer = (
          sort: _streakSortMode.name,
          customOrder: _customStreakOrder,
          zone: _myZone?.name,
        );
      } catch (e, st) {
        // Unknown: the sort, order and zone on screen stay.
        if (isNetworkError(e)) offline = true;
        debugLog('⚠️ Could not load preferences: $e');
        reportNonFatal(e, st, 'dashboard_prefs');
      }
    }

    // ── STEP 3: Sync + fetch streaks ────────────────────────
    _syncTeamCheckIns(); // fire and forget - don't await
    final allStreaks = await _teamStreakService.getAllUserStreaks();
    final nicknames  = await known('dashboard_nicknames', nicknameService.getAllNicknames(strict: true));

    // Every account has Coach Max's team, so no streaks at all is a failed
    // read. A wheel already on screen (the saved copy, or the last load)
    // stays, and the next show retries.
    if (allStreaks.isEmpty && _allStreaks.isNotEmpty) {
      _lastLoaded = null;
      if (mounted && _isLoading) setState(() => _isLoading = false);
      return;
    }
  
    debugLog('🔥 Raw streaks count: ${allStreaks.length}');
    for (var s in allStreaks) {
      debugLog('  - ${s.teamName} (${s.teamId}) - CoachMax: ${s.isCoachMaxTeam}');
    }
  
    // Deduplicate
    final Map<String, TeamStreak> uniqueStreaksMap = {};
    for (final s in allStreaks) {
      uniqueStreaksMap[s.teamId] = s;
    }
    final uniqueStreaks = uniqueStreaksMap.values.toList();
  
    // Apply custom order
    if (_streakSortMode == StreakSortMode.custom && _customStreakOrder.isNotEmpty) {
      debugLog('🎯 Applying custom order to ${uniqueStreaks.length} streaks');
      final streakMap = {for (var s in uniqueStreaks) s.teamId: s};
      final orderedStreaks = <TeamStreak>[];
      for (final teamId in _customStreakOrder) {
        if (streakMap.containsKey(teamId)) {
          orderedStreaks.add(streakMap[teamId]!);
          streakMap.remove(teamId);
        }
      }
      orderedStreaks.addAll(streakMap.values);
      uniqueStreaks.clear();
      uniqueStreaks.addAll(orderedStreaks);
      debugLog('✅ Custom order applied: ${orderedStreaks.length} streaks ordered');
    }
  
    // ── STEP 4: ALL remaining calls IN PARALLEL ──────────────
    final currentUserId = Supabase.instance.client.auth.currentUser?.id;
  
    // Local frame: check_in_date labels are the user's own local dates now,
    // so the heatmap's 7-day lower bound must be local too (was .toUtc()).
    final sevenDaysAgoStr = DateTime.now()
        .subtract(const Duration(days: 7))
        .toIso8601String()
        .split('T')[0];

    final (hasCheckedIn, todaysWorkouts, myCheckInDates, breakRows) = await (
      // has checked in today
      known('dashboard_has_checked_in', _teamStreakService.hasCheckedInToday(strict: true)),
      // today's workouts
      known('dashboard_todays_workouts', _workoutService.getTodaysWorkouts(strict: true)),
      // real check-in dates for the heatmap (last 7 days, this user)
      // — fixes the bug where days were painted as "done" purely from
      // arithmetic on current_streak rather than real check-in history.
      known('dashboard_checkin_dates', CheckInHistoryService().myCheckInDatesSince(sevenDaysAgoStr)),
      // own uncancelled break days — heatmap third state + today badge
      currentUserId == null
          ? Future<List<Map<String, dynamic>>?>.value(<Map<String, dynamic>>[])
          : known<List<Map<String, dynamic>>>('dashboard_break_days', Supabase.instance.client
              .from('break_day_usage')
              .select('break_date')
              .eq('user_id', currentUserId)
              .gte('break_date', sevenDaysAgoStr)
              .isFilter('cancelled_at', null)),
    ).wait;
    final myBreakDates =
        breakRows?.map((r) => r['break_date'] as String).toSet();

    // Buddy break badges: a buddy's break is dated in THEIR own local today
    // (per-user tz), so resolution happens server-side via are_on_break_today
    // (safe_user_tz) — never with the viewer's local date. Failures degrade
    // to no badge.
    final buddyIds = uniqueStreaks
        .where((s) => !s.isCoachMaxTeam)
        .expand((s) => s.members)
        .map((m) => m.userId)
        .where((id) => id != currentUserId)
        .toSet();
    final onBreakIds =
        await known('dashboard_buddy_on_break', _breakDayService.usersOnBreakToday(buddyIds, strict: true));
    final buddyOnBreak = onBreakIds == null
        ? null
        : <String, bool>{for (final id in buddyIds) id: onBreakIds.contains(id)};

    // Buddy zones for the danger countdown: the deadline is the BUDDY's local
    // midnight — theirs is the miss that breaks the streak (reconcile_stale_
    // streaks judges each member in their own tz). Same column safe_user_tz
    // reads, same fallback, so client and server frame the day identically.
    Map<String, String>? buddyZones = {};
    if (buddyIds.isNotEmpty) {
      try {
        final rows = await Supabase.instance.client.rpc(
            'get_teammate_timezones',
            params: {'p_user_ids': buddyIds.toList()});
        buddyZones = {
          for (final row in rows as List)
            row['user_id'] as String: (row['timezone'] as String?) ?? _kFallbackTz,
        };
      } catch (e, st) {
        // Unknown: the zones on screen stay (each lookup still falls back to
        // _kFallbackTz on its own) and none are saved.
        if (isNetworkError(e)) offline = true;
        reportNonFatal(e, st, 'dashboard_buddy_zones');
        buddyZones = null;
      }
    }

    // Equipped ring colors for every visible member (buddies + self), one
    // batched query rather than one per carousel slot. Members with nothing
    // equipped are simply absent from the map — _buildCarouselAvatar falls
    // back to _memberColor's hash for those.
    final allMemberIds = uniqueStreaks
        .where((s) => !s.isCoachMaxTeam)
        .expand((s) => s.members)
        .map((m) => m.userId)
        .toSet();
    final ringColorHexById = await known('dashboard_ring_colors',
        CoinService().getEquippedColorHexForUsers(allMemberIds.toList(), strict: true));

    // Highest streak (already sorted, just pick first)
    final highestStreak = uniqueStreaks.isEmpty
        ? null
        : uniqueStreaks.reduce((a, b) =>
            a.currentStreak > b.currentStreak ? a : b);
  
    if (offline) _lastLoaded = null; // the next show asks again
    if (!mounted) return;

    // A failed "today" part keeps what is shown only while that is still
    // today's; across midnight it falls back to empty, as before.
    final now = DateTime.now();
    final shownAt = _todayShownAt;
    final keepToday = shownAt != null && !dayChanged(shownAt, now, zone: _myZone);
    T today<T>(T? answer, T shown, T empty) => answer ?? (keepToday ? shown : empty);

    setState(() {
      _allStreaks            = uniqueStreaks;
      _nicknames             = nicknames ?? _nicknames;
      _highestStreak         = highestStreak;
      _myCheckInDates        = today(myCheckInDates, _myCheckInDates, <String>{});
      _myBreakDates          = today(myBreakDates, _myBreakDates, <String>{});
      _isOnBreakToday        = _myBreakDates.contains(localTodayString());
      _buddyOnBreakToday     = today(buddyOnBreak, _buddyOnBreakToday, <String, bool>{});
      _buddyTimezones        = buddyZones ?? _buddyTimezones;
      if (ringColorHexById != null) {
        _memberRingColors = {
          for (final e in ringColorHexById.entries) e.key: hexToColor(e.value),
        };
      }
      _hasCheckedInToday     = today(hasCheckedIn, _hasCheckedInToday, false);
      _teamFeeds.clear();
      _todaysWorkouts        = today(todaysWorkouts, _todaysWorkouts, <Map<String, dynamic>>[]);
      _isLoading             = false;
      _loadedFresh           = true;
      _todayShownAt          = now;
    });
  
    if (_allStreaks.isNotEmpty && mounted) {
      _currentCarouselIndex = 0;
    }
  
    if (!_hasAnimatedEntrance && _allStreaks.isNotEmpty) {
      Future.delayed(const Duration(milliseconds: 100), () {
        if (mounted) {
          _carouselEntranceController.forward();
          _hasAnimatedEntrance = true;
        }
      });
    }
  
    // ── STEP 5: Save what the server answered ───────────────
    // Over the same-day entry already saved, so a failed part keeps its
    // saved value. Off the load's await chain.
    final zone = _myZone;
    unawaited(() async {
      final uid = SavedCopy.uid;
      final saved = await SavedCopy.read<Map<String, dynamic>>(uid, 'dashboard',
          maxAge: kSavedMaxAgeDashboard,
          sameDay: true,
          parse: (d) => Map<String, dynamic>.from(d as Map));
      final payload = dashboardSavedPayload(
        saved: saved,
        streaks: uniqueStreaks,
        prefs: prefsAnswer,
        nicknames: nicknames,
        checkIns: myCheckInDates,
        breakDates: myBreakDates,
        buddyOnBreak: buddyOnBreak,
        buddyZones: buddyZones,
        ringHex: ringColorHexById,
        hasCheckedIn: hasCheckedIn,
        workouts: todaysWorkouts,
      );
      if (payload != null) await SavedCopy.write(uid, 'dashboard', payload, zone: zone);
    }());
  }

  /// Whether the first load already tried the saved copy, and whether fresh
  /// data landed (which a saved copy that is still being read must not undo).
  bool _restoreTried = false;
  bool _loadedFresh = false;

  /// When the "today" parts on screen (check-ins, breaks, workouts) were
  /// last set from the server or a same-day saved copy.
  DateTime? _todayShownAt;

  /// First paint from the saved copy (same local day only: it carries streak
  /// numbers and today's check-in state), in place of the skeleton.
  Future<void> _restoreSaved() async {
    final saved = await SavedCopy.read<SavedDashboard>(
      SavedCopy.uid,
      'dashboard',
      maxAge: kSavedMaxAgeDashboard,
      sameDay: true,
      parse: dashboardFromSaved,
    );
    if (saved == null || !mounted || !_isLoading || _loadedFresh) return;
    // A part missing from the saved copy (its read had never answered) stays
    // as it starts out, as the load would leave it.
    final streaks = saved.streaks;
    if (saved.sort != null) _sortCtl.paint(saved.sort);
    setState(() {
      _myZone = _profileZone(saved.zone);
      profileZone = _myZone;
      _allStreaks = streaks;
      _nicknames = saved.nicknames ?? _nicknames;
      _highestStreak = streaks.reduce((a, b) => a.currentStreak > b.currentStreak ? a : b);
      _myCheckInDates = saved.checkIns ?? _myCheckInDates;
      _myBreakDates = saved.breakDates ?? _myBreakDates;
      _isOnBreakToday = _myBreakDates.contains(localTodayString());
      _buddyOnBreakToday = saved.buddyOnBreak ?? _buddyOnBreakToday;
      _buddyTimezones = saved.buddyZones ?? _buddyTimezones;
      final ringHex = saved.ringHex;
      if (ringHex != null) {
        _memberRingColors = {for (final e in ringHex.entries) e.key: hexToColor(e.value)};
      }
      _hasCheckedInToday = saved.hasCheckedIn ?? _hasCheckedInToday;
      _todaysWorkouts = saved.workouts ?? _todaysWorkouts;
      _customStreakOrder = saved.customOrder ?? _customStreakOrder;
      _todayShownAt = DateTime.now(); // read with sameDay: today's
      _isLoading = false;
    });
    _currentCarouselIndex = 0;
    if (!_hasAnimatedEntrance) {
      Future.delayed(const Duration(milliseconds: 100), () {
        if (mounted) {
          _carouselEntranceController.forward();
          _hasAnimatedEntrance = true;
        }
      });
    }
  }

  Future<void> _checkWeeklyPlan() => runWeeklyPlanCheck(
        check: _planCheck,
        waiter: _planWaiter,
        currentUser: () => _supabase.auth.currentUser?.id,
        read: _breakDayService.needsToSetWeeklyPlan,
        mounted: () => mounted,
        screenFree: () => weeklyPlanScreenIsFree(context),
      );

  Future<void> _showWeeklyPlanDialog() async {
    // The dialog saves the plan itself and returns the saved break days only
    // after the save worked; it cannot be closed any other way.
    final result =
        await showWeeklyPlanDialog(context, save: _breakDayService.setWeeklyBreakPlan);

    if (result != null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(weeklyPlanSnackBar(result));
      setState(() {}); // Refresh UI
      await _loadStreakData();
    }
  }

  

  Future<void> _checkIn() async {
      if (_hasCheckedInToday) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('You already checked in today.'),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 2),
          ),
        );
        return;
      }

      setState(() => _isCheckingIn = true);
      try {
      // ✅ NEW: Check if there's an active workout session first
      final existingSession = await WorkoutCheckInSheet.getActiveSession();

      // A shared workout can be live without this device holding a session —
      // setBuddyReady only creates one for whoever tapped Start Together.
      // Adopt it so this button resumes the shared timer instead of falling
      // through to a detached solo workout.
      final activeSession =
          existingSession ?? await _adoptLiveBuddyWorkoutSession();

      if (activeSession != null && activeSession['started_at'] != null) {
        // ✅ Active workout exists - go directly to timer with saved details
        if (!mounted) return;

        // A workout tied to a workouts row runs on its own workout page. This
        // only happens when the user taps Continue or the check-in button;
        // nothing opens it automatically.
        if (runsOnScheduleCard(activeSession)) {
          await Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => WorkoutPage(workoutId: activeSession['workout_id'] as String)));
          return;
        }

        final completed = await WorkoutCheckInSheet.show(
          context,
          workoutType: activeSession['workout_type'] ?? 'Workout',
          workoutEmoji: activeSession['workout_emoji'] ?? '💪',
          plannedDuration: activeSession['planned_duration'] ?? 30,
          onCheckInComplete: () async {
            final result = await _teamStreakService.checkInAllTeams(
              workoutName: activeSession['workout_type'] ?? 'Workout',
              workoutEmoji: activeSession['workout_emoji'] ?? '💪',
              durationMinutes: activeSession['planned_duration'] ?? 30,
            );

            if (result['success'] == true) {
              HapticFeedback.heavyImpact();
              if (!mounted) return false;
              // Refresh first so the confirmation shows the new streak.
              await _loadStreakData();
              if (!mounted) return false;
              await _showCheckInConfirmation(
                  result['message'] ?? 'Check-in successful!');

              // 🏆 Show workout achievement toasts.
              if ((result['teams_updated'] as int? ?? 0) > 0) {
                final workoutAchievements = await AchievementService().checkWorkoutAchievements(
                  durationMinutes: activeSession['planned_duration'] ?? 30,
                  workoutType: activeSession['workout_type'] ?? 'Workout',
                );
                if (workoutAchievements.isNotEmpty && mounted) {
                  AchievementToast.show(context, workoutAchievements);
                }
              }

              await _loadStreakData();
              return result['partner_bonus_earned'] == true;
            }
            if (result['noop'] == true && mounted) {
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(result['message'] as String)));
            }
            return false;
          },
        );

        if (completed == true && mounted) {
          _loadStreakData();
        }
        return; // ← Important: Don't show selection modal
      }

      // ✅ No active workout - show selection modal (existing flow)
      await _handleCheckIn();
      } finally {
        if (mounted) setState(() => _isCheckingIn = false);
      }
    }

  /// A live buddy workout involving this user may have no local session
  /// (setBuddyReady only creates one for the tapper). Create one anchored
  /// to the workout's real start time so the dashboard resumes it.
  Future<Map<String, dynamic>?> _adoptLiveBuddyWorkoutSession() async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return null;
    try {
      final workout = await Supabase.instance.client
          .from('workouts')
          .select(
              'id, user_id, workout_type, planned_duration_minutes, workout_started_at, creator_cancelled, buddy_cancelled')
          .eq('status', 'in_progress')
          .or('user_id.eq.$userId,buddy_id.eq.$userId')
          .not('workout_started_at', 'is', null)
          .order('workout_started_at', ascending: false)
          .limit(1)
          .maybeSingle();
      if (workout == null) return null;

      // A participant who cancelled their part must not be pulled back in.
      final cancelledOwnPart = workout['user_id'] == userId
          ? (workout['creator_cancelled'] ?? false)
          : (workout['buddy_cancelled'] ?? false);
      if (cancelledOwnPart == true) return null;

      final session = {
        'user_id': userId,
        'started_at': workout['workout_started_at'],
        'planned_duration': workout['planned_duration_minutes'] ?? 30,
        'workout_type': workout['workout_type'] ?? 'Workout',
        'workout_emoji': '💪',
        'workout_id': workout['id'],
      };
      await Supabase.instance.client
          .from('active_checkin_sessions')
          .upsert(session, onConflict: 'user_id');
      return session;
    } catch (e) {
      debugLog('⚠️ Could not adopt live buddy workout session: $e');
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // AutomaticKeepAliveClientMixin
    return Stack(
      children: [
        Scaffold(
          backgroundColor: context.watch<AccentThemeProvider>().palette.background,
          body: _isLoading
              ? _buildLoadingSkeleton()
              : SafeArea(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildDashboardHeader(),
                      const NoticeHomeCard(),
                      Expanded(
                        child: SingleChildScrollView(
                          // Explicit rather than relying on the platform
                          // default: no iOS-style rubber-band when content
                          // already fits (checked — nothing overrides
                          // MaterialApp's own ClampingScrollPhysics here,
                          // this just makes it not implicit).
                          physics: const ClampingScrollPhysics(),
                          // The nav bar floats over the body (extendBody), so
                          // reserve its height or the last card hides under it.
                          padding: EdgeInsets.only(
                            bottom: 62 + MediaQuery.paddingOf(context).bottom,
                          ),
                          child: _buildDashboardBody(),
                        ),
                      ),
                    ],
                  ),
                ),
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: ConfettiWidget(
            confettiController: _confettiController,
            blastDirection: 0,
            emissionFrequency: 0.05,
            numberOfParticles: 30,
            maxBlastForce: 100,
            minBlastForce: 80,
            gravity: 0.3,
            colors: const [
              Colors.green, Colors.blue, Colors.pink,
              Colors.orange, Colors.purple, Colors.yellow,
            ],
          ),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: ConfettiWidget(
            confettiController: _confettiControllerRight,
            blastDirection: 3.14,
            emissionFrequency: 0.05,
            numberOfParticles: 30,
            maxBlastForce: 100,
            minBlastForce: 80,
            gravity: 0.3,
            colors: const [
              Colors.green, Colors.blue, Colors.pink,
              Colors.orange, Colors.purple, Colors.yellow,
            ],
          ),
        ),
        if (_bannerBuddy != null)
          LiveEventToastCard(
            key: ValueKey(_bannerRequestId),
            leading: ClipOval(
              child: UserAvatar(
                avatarId: _bannerBuddy!.avatarId ?? 'avatar_1',
                size: 40,
              ),
            ),
            accentPrefix: _nicknames[_bannerBuddy!.userId]?.isNotEmpty == true
                ? _nicknames[_bannerBuddy!.userId]!
                : _bannerBuddy!.displayName,
            title: ' just checked in',
            subtitle: checkInBannerSubtitle(
                viewerCheckedIn: _bannerViewerCheckedIn),
            onDismissed: () {
              if (mounted) setState(() => _bannerBuddy = null);
            },
          ),
      ],
    );
  }

  // No streaks card
  Widget _buildNoStreaksCard() {
    final c = AppColors.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 40, 20, 20),
      child: _clayTraySlab(
        padding: const EdgeInsets.all(36),
        child: Column(
          children: [
            _trayGlyph('🔥'),
            const SizedBox(height: 18),
            Text(
              'No active streaks yet',
              style: TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.w800,
                color: c.readableForeground(c.claySurface),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Check in to start your streak!',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: c.inkMuted),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSkeletonCard() {
    final c = AppColors.of(context);
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: c.claySurface,
        borderRadius: BorderRadius.circular(26),
        boxShadow: c.clayShadow(),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Section label
          const Center(child: SkeletonBox(width: 180, height: 12, radius: 6)),
          const SizedBox(height: 24),
          // Wheel: focused centre, two peeking
          const Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              SkeletonBox.circle(size: 76),
              SkeletonBox.circle(size: 108),
              SkeletonBox.circle(size: 76),
            ],
          ),
          const SizedBox(height: 26),
          // Name + streak count
          const Center(child: SkeletonBox(width: 120, height: 14, radius: 7)),
          const SizedBox(height: 10),
          const Center(child: SkeletonBox(width: 190, height: 30, radius: 8)),
          const SizedBox(height: 22),
          // CTA
          const SkeletonBox(width: double.infinity, height: 58, radius: 19),
        ],
      ),
    );
  }

  Widget _buildLoadingSkeleton() {
    final c = AppColors.of(context);
    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 14),
            child: Row(
              children: [
                const SkeletonBox(width: 180, height: 26, radius: 8),
                const Spacer(),
                const SkeletonBox.circle(size: 44),
                const SizedBox(width: 10),
                const SkeletonBox.circle(size: 46),
              ],
            ),
          ),
          Container(height: 1, color: c.clayShadowLight),
          const SizedBox(height: 34),
          _buildSkeletonCard(),
        ],
      ),
    );
  }
  
  Future<void> _showQuickCreateWorkoutDialog() {
    return ScheduleWorkoutSheet.show(
      context,
      onWorkoutScheduled: _loadStreakData,
    );
  }

  /// Accept/decline from the tray go through the same server RPCs as the
  /// Workout Schedule card. An overlap is decided there, not here.
  Future<void> _answerInviteDash(String workoutId, {required bool accept}) async {
    final svc = HandshakeService();
    final home = context.findAncestorStateOfType<_HomeScreenState>();
    String text;
    try {
      final r = accept ? await svc.accept(workoutId) : await svc.decline(workoutId);
      text = r['state'] == 'overlap'
          ? 'This overlaps with another workout. Open Workout Schedule to decide.'
          : accept ? 'Workout invitation accepted' : 'Workout invitation declined';
      if (r['state'] == 'overlap') {
        home?._onTabChanged(0);
      }
    } catch (e) {
      text = HandshakeError.from(e).message();
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
    _loadStreakData();
  }

  Future<void> _showAllStreaks() {
    return showDialog(
      context: context,
      builder: (context) => _AllStreaksDialog(streaks: _listStreaks),
    );
  }

  // Pure lookup against real server rows. No _hasCheckedInToday special-case:
  // that cached bool is keyed to the server's notion of "today" and painting
  // it onto whatever column the device thought was today double-marked the
  // boundary hour (one 🔥 from the real row + one fabricated). check_in_date
  // labels are the user's own local dates (per-user tz rework), so a local
  // date-string compare is exact.
  bool _isDateCheckedIn(DateTime date) {
    final dateStr = DateTime(date.year, date.month, date.day)
        .toIso8601String()
        .split('T')[0];
    return _myCheckInDates.contains(dateStr);
  }

  // Break-day lookup mirrors _isDateCheckedIn: break_date labels are the
  // user's own local dates, so a local date-string compare is exact.
  bool _isDateOnBreak(DateTime date) {
    final dateStr = DateTime(date.year, date.month, date.day)
        .toIso8601String()
        .split('T')[0];
    return _myBreakDates.contains(dateStr);
  }

  bool _isSameDay(DateTime date1, DateTime date2) {
    return date1.year == date2.year &&
           date1.month == date2.month &&
           date1.day == date2.day;
  }

  String _getDayInitial(DateTime date) {
    const days = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
    return days[date.weekday - 1];
  }

  /// Shown after every successful check-in: milestone copy on milestone
  /// days, a generic confirmation otherwise. Confetti stays milestone-only.
  Future<void> _showCheckInConfirmation(String checkInMessage) async {
    final currentStreak = _highestStreak?.currentStreak;
    final isMilestone = currentStreak != null &&
        kStreakMilestones.containsKey(currentStreak) &&
        currentStreak > _lastCelebratedStreak;
    if (isMilestone) _lastCelebratedStreak = currentStreak;

    await _showMilestoneDialog(currentStreak,
        isMilestone: isMilestone, fallbackMessage: checkInMessage);
    if (isMilestone && mounted) {
      _confettiController.play();
      _confettiControllerRight.play();
    }
  }

  Future<void> _showMilestoneDialog(
    int? streak, {
    required bool isMilestone,
    required String fallbackMessage,
  }) async {
    String title = 'Checked In!';
    String message = fallbackMessage;

    if (isMilestone) {
    switch (streak) {
      case 1:
        title = 'First Check-in!';
        message = 'Your journey begins!';
        break;
      case 3:
        title = 'Building Momentum!';
        message = 'Three days strong!';
        break;
      case 7:
        title = 'On Fire!';
        message = 'One week streak unlocked!';
        break;
      case 14:
        title = 'Two Weeks!';
        message = 'You\'re crushing it!';
        break;
      case 30:
        title = 'Diamond Status!';
        message = 'A full month! Legendary!';
        break;
      case 50:
        title = 'Unstoppable!';
        message = '50 days of dedication!';
        break;
      case 100:
        title = 'LEGEND!';
        message = '100 days! You\'re a champion!';
        break;
      case 365:
        title = 'IMMORTAL!';
        message = 'A FULL YEAR! Incredible!';
        break;
      default:
        title = 'Milestone Reached!';
        message = '$streak days strong!';
    }
    }
    
    final videoKey = GlobalKey<CheckinIgniteVideoState>();
    await showDialog(
      context: context,
      // Tap anywhere on the dialog skips the clip to its final frame; the
      // Awesome! button still wins its own taps.
      builder: (context) {
        final c = AppColors.of(context);
        final scheme = Theme.of(context).colorScheme;
        return GestureDetector(
          onTap: () => videoKey.currentState?.skip(),
          child: Dialog(
            backgroundColor: Colors.transparent,
            elevation: 0,
            child: Container(
              padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
              decoration: BoxDecoration(
                // Clay tokens rather than the mockup's #223A2F → #142420:
                // this dialog shows on every accent, and fixed dark greens
                // would break the light (signalBlue) skin.
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [c.claySurface, c.clayBg],
                ),
                borderRadius: BorderRadius.circular(20),
                boxShadow: c.clayShadow(),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // PLACEMENT PENDING SIGN-OFF: 120px circle-clipped clip in
                  // the old emoji/halo slot, lit by an avatarRing glow.
                  DecoratedBox(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: c.avatarRing.withValues(alpha: 0.45),
                          blurRadius: 26,
                        ),
                      ],
                    ),
                    child: CheckinIgniteVideo(key: videoKey, size: 120),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: scheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    message,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 18,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  if (streak != null) ...[
                    const SizedBox(height: 16),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Counts up from yesterday's number once the dialog has
                        // settled; milestone days add the burst + confetti.
                        StreakBadge(
                          streak: streak,
                          size: 60,
                          tickFrom: streak > 1 ? streak - 1 : null,
                          celebrate: isMilestone,
                          startDelay: const Duration(milliseconds: 450),
                        ),
                        const SizedBox(width: 14),
                        Text(
                          'Day Streak!',
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                            color: Colors.orange[700],
                            shadows: [
                              Shadow(
                                color: c.streakOrange.withValues(alpha: 0.35),
                                blurRadius: 22,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 24),
                  // actionGradient, not the mockup's #F97316: white on
                  // #F97316 is 2.8:1; this pair keeps the label ≥3.3:1 and
                  // follows the one-orange rule.
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: c.actionGradient.reversed.toList(),
                      ),
                      borderRadius: BorderRadius.circular(18),
                      boxShadow: [
                        BoxShadow(
                          color: c.streakOrange.withValues(alpha: 0.40),
                          offset: const Offset(0, 8),
                          blurRadius: 18,
                        ),
                      ],
                    ),
                    child: Material(
                      type: MaterialType.transparency,
                      child: Semantics(
                        button: true,
                        child: InkWell(
                        borderRadius: BorderRadius.circular(18),
                        onTap: () => Navigator.pop(context),
                        child: const SizedBox(
                          width: double.infinity,
                          height: 52,
                          child: Center(
                            child: Text(
                              'Awesome!',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 19,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ),
                      ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _syncTeamCheckIns() async {
    if (kDebugMode) debugLog('🔄 Dashboard: Starting team sync...');
    
    final result = await _teamSyncService.syncAllTeamsCheckIns();
    
    if (result['success'] == true && result['synced'] > 0) {
      if (kDebugMode) debugLog('✅ Dashboard: Synced ${result['synced']} teams');
      
      // Show a subtle notification if teams were synced
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.sync, color: Colors.white, size: 20),
                const SizedBox(width: 12),
                Text(result['message'] as String),
              ],
            ),
            backgroundColor: Colors.blue,
            duration: const Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.all(8),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        );
      }
    }
  }

  /// Writes the sort (and for Custom its order). Throws when it fails.
  Future<void> _writeSort(StreakSortMode mode, List<String>? customOrder) async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;
    await Supabase.instance.client.from('user_profiles').update({
      'preferred_streak_sort': mode.name,
      if (customOrder != null) 'custom_streak_order': customOrder,
    }).eq('id', userId);
    markStale({AppTab.profile}); // Profile's All Streaks follows the sort
  }

  /// The sort, or its save, changed. The wheel is redrawn only when the sort
  /// on screen gives a different order: a saving or status change, or a sort
  /// with the same order, leaves the dashboard behind the sheet alone.
  void _onSortChanged() {
    if (!mounted) return;
    if (!streakSortChangesOrder(_allStreaks, _wheelSort, _sortCtl.shown)) return;
    setState(() {});
  }

  /// A tap on a sort in the sheet: it shows at once, the save comes after.
  /// The wheel goes back to the first buddy only if the order really changes.
  void _pickSort(StreakSortMode mode) {
    final changesOrder = streakSortChangesOrder(_allStreaks, _streakSortMode, mode);
    if (changesOrder) setState(() => _currentCarouselIndex = 0);
    unawaited(_sortCtl.choose(mode)); // shown in the sheet, the button and the line either way
    if (!changesOrder) return;
    if (_carouselController.hasClients) {
      _carouselController.jumpToPage(10080);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_carouselController.hasClients && mounted) {
        _carouselController.jumpToPage(1000);
      }
    });
  }

  Future<void> _showSortBottomSheet() {
    HapticFeedback.mediumImpact();
    _sortCustomLatch.dispose();
    _sortCustomLatch = RunOnce();
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => StreakSortSheet(
        controller: _sortCtl,
        onPick: _pickSort,
        // Custom has its own picker, saved when that picker is saved.
        onCustom: () => _sortCustomLatch.latch(() {
          Navigator.pop(sheetContext);
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _showCustomModeSelector();
          });
        }),
      ),
    );
  }

  Future<void> _toggleFavorite(TeamStreak streak) async {
    try {
      HapticFeedback.mediumImpact();
      
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) return;
      
      // Toggle the favorite status
      final newFavoriteStatus = !streak.isFavorite;
      
      await Supabase.instance.client
          .from('team_streaks')
          .update({'is_favorite': newFavoriteStatus})
          .eq('id', streak.id);
      
      // Show feedback
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              newFavoriteStatus 
                  ? '${streak.teamName} added to favorites.' 
                  : '${streak.teamName} removed from favorites',
            ),
            duration: const Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
            backgroundColor: newFavoriteStatus ? Colors.orange[700] : Colors.grey[700],
          ),
        );
      }
      
      // Reload data to reflect changes
      await _loadStreakData();
      
    } catch (e) {
      debugLog('❌ Error toggling favorite: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to update favorite')),
        );
      }
    }
  }

  Future<void> _showBuddyProfile(TeamStreak streak, TeamMember buddy) {
    final nickname = _nicknames[buddy.userId];
    
    return BuddyProfileSheet.show(
      context,
      buddyDisplayName: buddy.displayName,
      buddyUsername: buddy.username ?? buddy.displayName.toLowerCase().replaceAll(' ', ''),
      buddyAvatarId: buddy.avatarId ?? 'avatar_1',
      buddyUserId: buddy.userId,
      currentStreak: streak.currentStreak,
      bestStreak: streak.longestStreak,
      totalWorkouts: streak.totalWorkouts,
      nickname: nickname,  // 🆕 Pass the nickname
      onNicknameChanged: () {
        // Refresh nicknames and reload
        nicknameService.refreshCache();
        _loadStreakData();
      },
    );
  }

  Future<void> _handleCheckIn() async {
      WorkoutTemplate? selectedTemplate;
      int? selectedDuration;
      String? selectedNotes;
      List<AchievementUnlockResult> pendingAchievements = [];

      await showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (modalContext) => WorkoutSelectionModal(
          onWorkoutSelected: (template, duration, notes, extraAchievements) {
            selectedTemplate = template;
            selectedDuration = duration;
            selectedNotes = notes;
            pendingAchievements = extraAchievements;
          },
        ),
      );

      if (selectedTemplate == null || !mounted) return;

      debugLog('🎲 Pending achievements count: ${pendingAchievements.length}');

      // 🏆 Show Feeling Lucky toast if randomiser was used
      if (pendingAchievements.isNotEmpty && mounted) {
        AchievementToast.show(context, pendingAchievements);
        pendingAchievements = [];
      }

    // ✅ NOW show the timer with workout details (after modal is fully closed)
    final completed = await WorkoutCheckInSheet.show(
      context,
      workoutType: selectedTemplate!.name,
      workoutEmoji: selectedTemplate!.emoji,
      plannedDuration: selectedDuration!,
      onCheckInComplete: () async {
        final result = await _teamStreakService.checkInAllTeams(
          selectedTemplateId: selectedTemplate!.id,
          workoutName: selectedTemplate!.name,
          workoutCategory: selectedTemplate!.category,
          workoutEmoji: selectedTemplate!.emoji,
          durationMinutes: selectedDuration!,
          notes: selectedNotes,
        );

        if (result['success'] == true) {
          HapticFeedback.heavyImpact();
          if (!mounted) return false;
          // Refresh first so the confirmation shows the new streak.
          await _loadStreakData();
          if (!mounted) return false;
          await _showCheckInConfirmation(
              result['message'] ?? 'Check-in successful!');

          // 🏆 Show workout achievement toasts — no linked workouts row on
          // this flow, so there's no completeWorkoutWithDuration to wait on.
          if ((result['teams_updated'] as int? ?? 0) > 0) {
            final workoutAchievements = await AchievementService().checkWorkoutAchievements(
              durationMinutes: selectedDuration!,
              workoutType: selectedTemplate!.name,
            );
            if (workoutAchievements.isNotEmpty && mounted) {
              AchievementToast.show(context, workoutAchievements);
            }
          }

          await _loadStreakData();
          return result['partner_bonus_earned'] == true;
        }
        if (result['noop'] == true && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(result['message'] as String)));
        }
        return false;
      },
    );

    // Reload data regardless of outcome
    if (completed != null && mounted) {
      await _loadStreakData();
    }
  }
}
