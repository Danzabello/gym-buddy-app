import 'dart:async';
import 'package:gym_buddy_app/login_screen.dart';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'services/friend_service.dart';
import 'services/workout_service.dart';
import 'services/team_streak_service.dart';
import 'widgets/coach_max_widget.dart';
import 'widgets/ai_disclosure_tag.dart';
import 'package:confetti/confetti.dart';
import 'package:flutter/services.dart';
import 'widgets/user_avatar.dart';
import 'services/team_sync_service.dart';
import 'package:flutter/foundation.dart';
import 'widgets/break_day_section.dart';
import 'services/break_day_service.dart';
import 'widgets/friends_page_modern.dart';
import 'widgets/workout_invites_card.dart';
import 'widgets/completed_workouts_section.dart';
import 'widgets/workout_celebration.dart';
import 'widgets/custom_streak_selector.dart';
import 'widgets/buddy_profile_sheet.dart';
import 'services/nickname_service.dart';
import 'widgets/workout_card.dart';
import 'widgets/schedule_workout_sheet.dart';
import 'widgets/workout_checkin_sheet.dart';
import 'services/workout_history_service.dart';
import 'widgets/workout_selection_modal.dart';
import 'widgets/workout_join_checker.dart';
import 'pages/notification_settings_page.dart';
import 'pages/shop_page.dart';
import 'pages/workout_history_page.dart';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'widgets/xp_progress_bar.dart';
import 'widgets/avatar_picker_screen.dart';
import 'services/level_service.dart';
import 'pages/achievements_page.dart' as achievements_page;
import 'widgets/achievement_toast.dart';
import 'services/achievement_service.dart';
import 'package:provider/provider.dart';
import 'theme/app_theme.dart';
import 'theme/accent_theme_provider.dart';
import 'data/coach_tips.dart';
import 'services/presence_service.dart';
import 'services/notification_service.dart';
import 'package:gym_buddy_app/utils/debug_logger.dart';
import 'package:gym_buddy_app/utils/app_dates.dart';





class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedIndex = 2; // Start on Streaks (centre)

  late PageController _tabPageController;
  final GlobalKey<_DashboardPageState> _dashboardKey = GlobalKey<_DashboardPageState>();

  late List<Widget> _pages;

  @override
  void initState() {
    super.initState();
    _tabPageController = PageController(initialPage: 2);
    _pages = [
      const SchedulePage(),
      const FriendsPageModern(),
      DashboardPage(key: _dashboardKey),
      const ShopPage(),
      const ProfilePage(),
    ];
  }

  @override
  void dispose() {
    _tabPageController.dispose();
    super.dispose();
  }

  void _onTabChanged(int index) {
    final previousIndex = _selectedIndex;

    setState(() {
      _selectedIndex = index;
    });

    // Animate tab PageView if not already on the right page
    if (_tabPageController.hasClients &&
        _tabPageController.page?.round() != index) {
      _tabPageController.animateToPage(
        index,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }

    // Refresh dashboard when returning from friends page
    if (index == 2 && previousIndex == 1) {
      _dashboardKey.currentState?._syncTeamCheckIns();
      _dashboardKey.currentState?._loadStreakData();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.of(context).clayBg,
      extendBody: true,
      body: PageView(
        controller: _tabPageController,
        physics: const PageScrollPhysics(),
        onPageChanged: (index) {
          if (index != _selectedIndex) {
            setState(() => _selectedIndex = index);
            if (index == 2 && _selectedIndex == 1) {
              _dashboardKey.currentState?._syncTeamCheckIns();
              _dashboardKey.currentState?._loadStreakData();
            }
            if (index == 0) {
              setState(() {
                _pages[0] = SchedulePage(
                    key: ValueKey(
                        'schedule_${DateTime.now().millisecondsSinceEpoch}'));
              });
            }
          }
        },
        children: _pages,
      ),
      bottomNavigationBar: _GymBuddyNavBar(
        selectedIndex: _selectedIndex,
        onTabSelected: _onTabChanged,
      ),
    );
  }
}


// Dashboard/Home Page with Real Streak Data
class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

enum StreakSortMode {
  highestCurrent,    // ⚡ Highest active streak (default)
  mostWorkouts,      // 💪 Most workouts together
  bestAllTime,       // 🏆 Longest streak ever
  mostRecent,        // 🕐 Most recent workout
  favorites,         // ⭐ User favorites (future)
  custom,  // ✅ NEW!
  mostUrgent,        // ⚠️ At-risk streaks first
  alphabetical,      // 🔤 By team/buddy name
}

/// Order the sort grid renders in — deliberately NOT the enum's declaration
/// order. `custom` is a manual-reorder mode rather than an automatic sort, so
/// it sits last. The enum order itself is load-bearing (persisted by `.name`,
/// switch statements) and must not be changed to achieve this.
///
/// Every StreakSortMode must appear here or it silently vanishes from the UI;
/// the assert in _showSortBottomSheet catches that in debug.
const List<StreakSortMode> _sortModeDisplayOrder = [
  StreakSortMode.highestCurrent,
  StreakSortMode.mostWorkouts,
  StreakSortMode.bestAllTime,
  StreakSortMode.mostRecent,
  StreakSortMode.favorites,
  StreakSortMode.mostUrgent,
  StreakSortMode.alphabetical,
  StreakSortMode.custom,
];

// ✅ ADD EXTENSION HERE - OUTSIDE THE CLASS!
extension StreakSortModeExtension on StreakSortMode {
  String get displayName {
    switch (this) {
      case StreakSortMode.highestCurrent:
        return 'Highest Streak';
      case StreakSortMode.mostWorkouts:
        return 'Most Workouts';
      case StreakSortMode.bestAllTime:
        return 'Best All-Time';
      case StreakSortMode.mostRecent:
        return 'Most Recent';
      case StreakSortMode.favorites:
        return 'Favorites';
      case StreakSortMode.custom: 
        return 'Custom';  // ✅ NEW!
      case StreakSortMode.mostUrgent:
        return 'At Risk First';
      case StreakSortMode.alphabetical:
        return 'A to Z';
    }
  }
  
  String get emoji {
    switch (this) {
      case StreakSortMode.highestCurrent:
        return '⚡';
      case StreakSortMode.mostWorkouts:
        return '💪';
      case StreakSortMode.bestAllTime:
        return '🏆';
      case StreakSortMode.mostRecent:
        return '🕐';
      case StreakSortMode.favorites:
        return '⭐';
      case StreakSortMode.custom: 
        return '👤';  // ✅ NEW!
      case StreakSortMode.mostUrgent:
        return '⚠️';
      case StreakSortMode.alphabetical:
        return '🔤';
    }
  }
  
  String get description {
    switch (this) {
      case StreakSortMode.highestCurrent: return 'View by current streak';
      case StreakSortMode.mostWorkouts: return 'Most active teammates';
      case StreakSortMode.bestAllTime: return 'All-time champions';
      case StreakSortMode.mostRecent: return 'Recently active';
      case StreakSortMode.favorites: return 'Your favorites';
      case StreakSortMode.custom: return 'Manual selection';  // ✅ NEW!
      case StreakSortMode.mostUrgent: return 'Nobody checked in yet';
      case StreakSortMode.alphabetical: return 'By name, A to Z';
    }
  }
}

/// Friends-only, ordered by [mode]. Coach Max is always excluded — it is an
/// AI buddy, not a rankable streak. Top-level so both the dashboard and the
/// profile page order the streak list identically.
List<TeamStreak> sortStreaks(List<TeamStreak> streaks, StreakSortMode mode) {
  debugLog('🔄 SORT: Mode = ${mode.displayName}');
  debugLog('🔄 SORT: Input streaks count = ${streaks.length}');
  
  // Filter out Coach Max
  final friendStreaks = streaks.where((s) => !s.isCoachMaxTeam).toList();
  debugLog('🔄 SORT: After filtering Coach Max = ${friendStreaks.length}');
  
  // Sort based on mode
  switch (mode) {
    case StreakSortMode.highestCurrent:
      friendStreaks.sort((a, b) => b.currentStreak.compareTo(a.currentStreak));
      debugLog('⚡ SORT: Highest Current - Order: ${friendStreaks.map((s) => '${s.teamName}(${s.currentStreak})').join(', ')}');
      break;
      
    case StreakSortMode.mostWorkouts:
      friendStreaks.sort((a, b) => b.totalWorkouts.compareTo(a.totalWorkouts)); 
      debugLog('💪 SORT: Most Workouts - Order: ${friendStreaks.map((s) => '${s.teamName}(${s.totalWorkouts})').join(', ')}');
      break;
      
    case StreakSortMode.bestAllTime:
      friendStreaks.sort((a, b) => b.bestStreak.compareTo(a.bestStreak));  // ✅ Use real data!
      debugLog('🏆 SORT: Best All-Time - Order: ${friendStreaks.map((s) => '${s.teamName}(${s.bestStreak})').join(', ')}');
      break;
      
    case StreakSortMode.mostRecent:
      friendStreaks.sort((a, b) {
        if (a.lastInteractionAt == null) return 1;  // ✅ Use real timestamps!
        if (b.lastInteractionAt == null) return -1;
        return b.lastInteractionAt!.compareTo(a.lastInteractionAt!);  // Most recent first
      });
      debugLog('🕐 SORT: Most Recent - Order: ${friendStreaks.map((s) => '${s.teamName}(${s.lastInteractionAt})').join(', ')}');
      break;
      
    case StreakSortMode.favorites:
      // ✨ Filter to only favorites
      final favorites = friendStreaks.where((s) => s.isFavorite).toList();
      favorites.sort((a, b) => b.currentStreak.compareTo(a.currentStreak));
      debugLog('⭐ SORT: Favorites - Found ${favorites.length} favorite(s)');
      return favorites; // ✅ Return empty list if no favorites
      
    case StreakSortMode.mostUrgent:
      // At-risk first (nobody checked in today), longest streak as tiebreaker
      // so the most valuable streak at risk sits at the top.
      friendStreaks.sort((a, b) {
        if (a.isAtRisk != b.isAtRisk) return a.isAtRisk ? -1 : 1;
        return b.currentStreak.compareTo(a.currentStreak);
      });
      debugLog('⚠️ SORT: At Risk First - Order: ${friendStreaks.map((s) => '${s.teamName}(risk:${s.isAtRisk},${s.currentStreak})').join(', ')}');
      break;

    case StreakSortMode.alphabetical:
      friendStreaks.sort((a, b) =>
          a.teamName.toLowerCase().compareTo(b.teamName.toLowerCase()));
      debugLog('🔤 SORT: A to Z - Order: ${friendStreaks.map((s) => s.teamName).join(', ')}');
      break;

    case StreakSortMode.custom:
      // Don't need any code here for now
      break;
  }
  
  debugLog('✅ SORT: Returning ${friendStreaks.length} sorted streaks');
  return friendStreaks;
}

/// Splits a ring into one arc per team member: solid in that member's colour
/// once they have checked in today, a faint track if not. Recon confirmed teams
/// are pairs (42 two-member, 2 one-member, never more), but this draws N arcs so
/// a larger team degrades gracefully rather than silently mis-rendering.
class _CheckInRingPainter extends CustomPainter {
  final List<Color> segmentColors;
  final List<bool> checkedIn;
  final Color track;

  static const stroke = 5.0;

  const _CheckInRingPainter({
    required this.segmentColors,
    required this.checkedIn,
    required this.track,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final n = segmentColors.length;
    if (n == 0) return;

    final rect = Rect.fromLTWH(
        stroke / 2, stroke / 2, size.width - stroke, size.height - stroke);
    // A single-member team has no seam to show, so it draws as one closed ring.
    final gap = n == 1 ? 0.0 : 0.14;
    final sweep = (2 * math.pi / n) - gap;

    for (var i = 0; i < n; i++) {
      final start = -math.pi / 2 + i * (2 * math.pi / n) + gap / 2;
      final done = checkedIn[i];
      canvas.drawArc(
        rect,
        start,
        sweep,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = done ? stroke : stroke * 0.6
          ..color = done ? segmentColors[i] : track,
      );
    }
  }

  @override
  bool shouldRepaint(_CheckInRingPainter old) =>
      old.checkedIn.toString() != checkedIn.toString() ||
      old.segmentColors.toString() != segmentColors.toString() ||
      old.track != track;
}

/// Brand gradient, fixed per CLAUDE.md. Coach Max's identity depends on it, so
/// it is deliberately NOT an accent token — it must not shift with the skin.
const _kBrandGradient = [Color(0xFF1D4ED8), Color(0xFF7C3AED)];

class _DashboardPageState extends State<DashboardPage> with TickerProviderStateMixin {
  final SupabaseClient _supabase = Supabase.instance.client;
  final TeamStreakService _teamStreakService = TeamStreakService();
  final WorkoutService _workoutService = WorkoutService();
  final TeamSyncService _teamSyncService = TeamSyncService();
  final BreakDayService _breakDayService = BreakDayService();
  Map<String, bool> _streakCompletionStatus = {};
  Map<String, String> _nicknames = {};

  
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
  bool _isLoading = true;
  bool _isCheckingIn = false;
  bool _isRefreshing = false;
  static bool _weeklyPlanCheckedThisSession = false;


  String _timeUntilMidnight = '';
  int _pendingRequests = 0;
  int _totalWorkouts = 0;
  int _buddyCount = 0;
  int _achievementCount = 0;

  late ConfettiController _confettiController;
  late ConfettiController _confettiControllerRight;
  int _lastCelebratedStreak = 0;
  
  // NEW: For streak navigation
  int _currentStreakIndex = 0;
  final PageController _pageController = PageController();

  int _currentCarouselIndex = 0;
  late PageController _carouselController;

  late AnimationController _carouselEntranceController;
  late Animation<double> _carouselEntranceAnimation;
  bool _hasAnimatedEntrance = false;

  AppLifecycleListener? _appLifecycleListener;
  List<String> _customStreakOrder = [];
  List<TeamStreak> _customSelection = [];
  StreakSortMode _streakSortMode = StreakSortMode.highestCurrent;


  late List<int> _trayOrder;
  int _trayIndex = 0;
  late PageController _trayController;
  Timer? _countdownTimer;

  final PresenceService _presenceService = PresenceService();
  Map<String, Map<String, dynamic>> _presenceState = {};
  List<String> _friendIds = [];


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

    _trayOrder = [0, 1, 2]..shuffle();
    _trayController = PageController();

    _presenceService.onPresenceChanged = (state) {
        if (mounted) setState(() => _presenceState = state);
    };
    _presenceService.join();
    
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
    _updateCountdown();
    _countdownTimer = Timer.periodic(const Duration(minutes: 1), (_) => _updateCountdown());
    _confettiController = ConfettiController(duration: const Duration(seconds: 3));
    _confettiControllerRight = ConfettiController(duration: const Duration(seconds: 3));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _setupAppLifecycleListener();

      if (mounted) {
        WorkoutJoinChecker.checkForPendingJoins(context);
      }
    });
  }

  // Add this new method
  Future<void> _initializeHomePage() async {
    await Future.wait([
      _workoutService.cleanupStaleWorkouts(),
      _workoutService.cleanupOrphanedSessions(),
      _checkWeeklyPlan(),
      _checkForActiveWorkout(),
    ]);
  
    await _loadStreakData();
  
    // Reset broken streaks in background AFTER UI is shown
    _teamStreakService.checkAndResetBrokenStreaks();
  }

  void _setupAppLifecycleListener() {
    _loadStreakData();
  }

  @override
  void dispose() {
    _carouselController.dispose();
    _confettiController.dispose();
    _confettiControllerRight.dispose();
    _carouselEntranceController.dispose();
    _appLifecycleListener?.dispose();
    _trayController.dispose();
    _countdownTimer?.cancel();
    _presenceService.leave();
    super.dispose();
  }


  /// The wheel's slots: top 4 friends by the active sort + Coach Max.
  /// Returns null when there is nothing to show a wheel for — the caller
  /// decides which empty-state card to render.
  List<dynamic>? _wheelItems() {
    // Coach Max always has a slot: he's the automatic buddy.
    final coachMaxStreak = _allStreaks.firstWhere(
      (s) => s.isCoachMaxTeam,
      orElse: () => _allStreaks.first,
    );

    // Friends ordered by the selected sort mode (custom keeps stored order)
    final friendStreaks = _streakSortMode == StreakSortMode.custom
      ? _allStreaks.where((s) => !s.isCoachMaxTeam).toList()  // Just filter, don't sort
      : sortStreaks(_allStreaks, _streakSortMode);

    if (_streakSortMode == StreakSortMode.favorites && friendStreaks.isEmpty) {
      return null;
    }

    // Top 4 earn a wheel slot — the rest live in the full streak list
    final displayItems = <dynamic>[
      ...friendStreaks.take(4),
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

  Widget _buildDashboardBody(List<dynamic>? displayItems) {
    if (_allStreaks.isEmpty) return _buildNoStreaksCard();
    if (displayItems == null) return _buildEmptyFavoritesCard();

    // ✅ Debug output
    debugLog('📊 WHEEL ITEMS (${displayItems.length}):');
    for (var i = 0; i < displayItems.length; i++) {
      final it = displayItems[i];
      debugLog('  [$i] ${it is TeamStreak ? it.teamName : 'Add Buddy'}');
    }
    debugLog('  Current index: $_currentCarouselIndex');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildStreakListEntry(),
        _buildBuddyWheel(displayItems),
        _buildSwipeHint(),
        _buildCheckInCard(displayItems),
        const SizedBox(height: 10),
        _buildInfoTray(),
        const SizedBox(height: 4),
      ],
    );
  }

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

  /// Greeting · sort · bell, a hairline rule, then the focused streak's
  /// check-in chip right-aligned under the bell.
  Widget _buildDashboardHeader() {
    final c = AppColors.of(context);
    // The clay slab is the surface here, so the greeting has to be measured
    // against it — a fixed white was invisible on light accents (1.12:1).
    final ink = c.readableForeground(c.clayBg);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 14),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  _getGreeting(),
                  style: TextStyle(
                    color: ink,
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 10),
              // Sort/filter lived in the old carousel header, which this
              // replaces; it keeps its own control so the modes stay reachable.
              _clayCircleButton(
                size: 44,
                tooltip: 'Sort streaks',
                onTap: _showSortBottomSheet,
                child: Icon(Icons.tune_rounded, color: c.inkMuted, size: 20),
              ),
              const SizedBox(width: 10),
              _clayCircleButton(
                size: 46,
                tooltip: 'Notifications',
                onTap: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('No new notifications'),
                      duration: Duration(seconds: 1),
                    ),
                  );
                },
                child: Icon(Icons.notifications_none_rounded, color: ink, size: 22),
              ),
            ],
          ),
        ),
        Container(height: 1, color: c.clayShadowLight),
      ],
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
      onTap: _showAllStreaks,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 6, 20, 4),
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
      height: 182,
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
        padding: const EdgeInsets.only(top: 2, bottom: 4),
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
    final currentUserId = Supabase.instance.client.auth.currentUser?.id;
    final buddy = item.members.firstWhere(
      (m) => m.userId != currentUserId,
      orElse: () => item.members.first,
    );
    return _buddyOnBreakToday[buddy.userId] == true;
  }

  Widget _buildInfoTray() {
    final c = AppColors.of(context);
    final tip = coachTips[DateTime.now().millisecondsSinceEpoch % coachTips.length];
    final cards = [
      _buildTrayWorkout(),
      _buildTrayCoachTip(tip),
      _buildTrayHeatmap(),
    ];
    final orderedCards = _trayOrder.map((i) => cards[i]).toList();
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          // Sized to the tallest real card (the 3-line coach tip) with its
          // trimmed padding — not a clamp: nothing is cut at this height.
          height: 128,
          child: PageView(
            controller: _trayController,
            onPageChanged: (i) => setState(() => _trayIndex = i),
            children: orderedCards,
          ),
        ),
        const SizedBox(height: 6),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(3, (i) {
            final active = i == _trayIndex;
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
      ],
    );
  }

  /// The clay slab every tray card sits on. One shell, so the three card types
  /// can't drift apart in radius, shadow or padding.
  Widget _clayTraySlab({required Widget child, EdgeInsets? padding}) {
    final c = AppColors.of(context);
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      padding: padding ?? const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: BoxDecoration(
        color: c.claySurface,
        borderRadius: BorderRadius.circular(26),
        boxShadow: c.clayShadow(),
      ),
      child: child,
    );
  }

  /// Shared [icon] · [label]/[title] · optional [trailing] row used by every
  /// state of the workout tray card.
  Widget _trayRow({
    required Widget leading,
    required String label,
    required String title,
    Color? labelColor,
    Color? titleColor,
    String? subtitle,
    Widget? trailing,
  }) {
    final c = AppColors.of(context);
    return _clayTraySlab(
      child: Row(
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

  /// A small raised clay action pill.
  Widget _trayAction(String text, Color role, VoidCallback onTap) {
    final c = AppColors.of(context);
    return GestureDetector(
      onTap: onTap,
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

  Widget _trayIconAction(IconData icon, Color role, VoidCallback onTap) {
    final c = AppColors.of(context);
    return GestureDetector(
      onTap: onTap,
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
      (w) => w['status'] == 'in_progress',
      orElse: () => {},
    );
    if (activeWorkout.isNotEmpty) {
      return _trayRow(
        leading: _trayGlyph('🏋️', role: c.streakOrange),
        label: 'ACTIVE WORKOUT',
        title: activeWorkout['workout_type'] ?? 'Workout',
        titleColor: c.streakOrange,
        trailing: _trayAction('Continue', c.streakOrange, () => _checkIn()),
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
                () => _acceptWorkoutInviteDash(pendingInvite['id'])),
            const SizedBox(width: 8),
            _trayIconAction(Icons.close, danger,
                () => _declineWorkoutInviteDash(pendingInvite['id'])),
          ],
        ),
      );
    }

    // ── Priority 3: Friend working out live ──
    final friendsWorkingOut = _presenceService.getFriendsWorkingOut(_friendIds);
    if (friendsWorkingOut.isNotEmpty) {
      final friend = friendsWorkingOut.first;
      final friendId = friend['user_id'] as String;
      final friendName = _nicknames[friendId] ??
          _allStreaks
              .expand((s) => s.members)
              .firstWhere((m) => m.userId == friendId,
                  orElse: () => _allStreaks.first.members.first)
              .displayName;

      return _trayRow(
        leading: _trayGlyph('👀', role: c.success),
        label: 'LIVE',
        labelColor: c.success,
        title: '$friendName is training right now 💪',
        trailing: Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: c.success, shape: BoxShape.circle),
        ),
      );
    }

    // ── Priority 4: Scheduled workout ──
    final scheduled = _todaysWorkouts.firstWhere(
      (w) => w['status'] == 'scheduled',
      orElse: () => {},
    );
    if (scheduled.isNotEmpty) {
      return _trayRow(
        leading: _trayGlyph('📅'),
        label: "TODAY'S WORKOUT",
        title: scheduled['workout_type'] ?? 'Workout',
        subtitle: scheduled['workout_time'],
        trailing: _trayAction('View', c.info, () {
          final homeState = context.findAncestorStateOfType<_HomeScreenState>();
          homeState?.setState(() => homeState._selectedIndex = 0);
        }),
      );
    }

    // ── Priority 5: Nothing ──
    return _trayRow(
      leading: _trayGlyph('📅'),
      label: "TODAY'S WORKOUT",
      title: 'No workout scheduled',
      trailing: _trayAction('+ Add', c.info, _showQuickCreateWorkoutDialog),
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

  Widget _buildTrayHeatmap() {
    final c = AppColors.of(context);
    final today = DateTime.now();
    final monday = today.subtract(Duration(days: today.weekday - 1));
    final week = List.generate(7, (i) => monday.add(Duration(days: i)));
    final checkedCount = week.where((d) => _isDateCheckedIn(d)).length;
    final ink = c.readableForeground(c.claySurface);

    return _clayTraySlab(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
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
            children: week.map((date) {
              // Straight row lookup for every column, today included — the
              // _hasCheckedInToday special-case caused the boundary-hour
              // double-🔥 (see _isDateCheckedIn).
              final checked = !date.isAfter(today) && _isDateCheckedIn(date);
              // Checked-in wins over break: a real workout is the stronger signal.
              final onBreak =
                  !checked && !date.isAfter(today) && _isDateOnBreak(date);
              final isToday = _isSameDay(date, today);
              final isFuture = date.isAfter(today);

              return Column(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: checked
                          ? LinearGradient(
                              colors: _grad(c.streakOrange),
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            )
                          : onBreak
                              ? LinearGradient(
                                  colors: _grad(c.info),
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                )
                              : LinearGradient(
                                  colors: [c.claySurfaceLight, c.claySurface],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                      border: isToday
                          ? Border.all(color: c.streakOrange, width: 2)
                          : null,
                      // Days not yet earned read as pressed-in, not raised.
                      boxShadow: c.clayShadow(inset: !checked && !onBreak),
                    ),
                    child: Center(
                      child: checked
                          ? const Text('🔥', style: TextStyle(fontSize: 14))
                          : onBreak
                              ? Icon(Icons.shield,
                                  size: 13, color: c.readableForeground(c.info))
                              : Text(
                                  '${date.day}',
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: isFuture
                                        ? c.inkMuted.withValues(alpha: 0.45)
                                        : isToday
                                            ? c.streakOrange
                                            : c.inkMuted,
                                    fontWeight: isToday
                                        ? FontWeight.bold
                                        : FontWeight.normal,
                                  ),
                                ),
                    ),
                  ),
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
            }).toList(),
          ),
        ],
      ),
    );
  }

  String _getFriendName(TeamStreak streak) {
    final currentUserId = Supabase.instance.client.auth.currentUser?.id;
    final friendMember = streak.members.firstWhere(
      (member) => member.userId != currentUserId,
      orElse: () => streak.members.first,
    );
    
    // Check for nickname first!
    final nickname = _nicknames[friendMember.userId];
    if (nickname != null && nickname.isNotEmpty) {
      return nickname;
    }
    
    return friendMember.displayName;
  }

  /// Clay avatar for one wheel slot. [d] is 0.0 focused → 1.0 fully peeked.
  Widget _buildCarouselAvatar(TeamStreak streak, double d) {
    final c = AppColors.of(context);
    final accentPalette = context.watch<AccentThemeProvider>().palette;
    final size = 108.0 - 32.0 * d;      // 108 focused → 76 peeked
    final focused = d < 0.5;

    // Get the friend's info
    final friendMember = streak.isCoachMaxTeam ? null : _buddyOf(streak);

    return Opacity(
      opacity: 1.0 - 0.4 * d,            // 1.0 focused → 0.6 peeked
      child: GestureDetector(
        onTap: focused && !streak.isCoachMaxTeam && friendMember != null
            ? () => _showBuddyProfile(streak, friendMember)
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
                        child: CustomPaint(
                          size: Size(size + 14, size + 14),
                          painter: _CheckInRingPainter(
                            segmentColors: [
                              for (final m in streak.members)
                                _memberColor(m.userId, accentPalette),
                            ],
                            checkedIn: [
                              for (final m in streak.members)
                                streak.todayCheckIns
                                    .any((ci) => ci.userId == m.userId),
                            ],
                            track: c.claySurfaceLight,
                          ),
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
                  color: c.readableForeground(c.clayBg),
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
      onTap: () => _toggleFavorite(streak),
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
  /// `_getTeamStreakData` builds TeamStreaks without that filter, and the old
  /// `orElse: members.first` failed by handing back the *viewer*, i.e. showing
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
    if (others.length == 1) return '🔥 $first already checked in — keep pace';
    return '🔥 $first +${others.length - 1} already checked in — keep pace';
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
      margin: const EdgeInsets.symmetric(horizontal: 20),
      padding: const EdgeInsets.fromLTRB(22, 20, 22, 16),
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
          const SizedBox(height: 20),
          _buildCheckInCta(),
          if (_isOnBreakToday) ...[
            const SizedBox(height: 14),
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
            const SizedBox(height: 16),
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

    return GestureDetector(
      onTap: done || _isCheckingIn ? null : _checkIn,
      behavior: HitTestBehavior.opaque,
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

  Future<void> _showTakeBreakDialog() async {
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

    // Check if already took break today (uncancelled — a cancelled break
    // can be legitimately re-declared through the capped RPC)
    final existingBreak = await Supabase.instance.client
        .from('break_day_usage')  // ✅ FIXED: Changed from 'break_days'
        .select()
        .eq('user_id', currentUserId)
        .eq('break_date', today)
        .isFilter('cancelled_at', null)
        .maybeSingle();

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

    // Get weekly plan and count breaks used this week
    final userProfile = await Supabase.instance.client
        .from('user_profiles')
        .select('current_weekly_goal')
        .eq('id', currentUserId)
        .single();

    final weeklyBreakGoal = userProfile['current_weekly_goal'] ?? 2;



    // Count breaks taken this week. Local week boundary (via getWeekStart),
    // same frame as the now-local break_date keys.
    final startOfWeekStr = _breakDayService
        .getWeekStart(DateTime.now())
        .toIso8601String()
        .split('T')[0];

    final breaksThisWeek = await Supabase.instance.client
        .from('break_day_usage')  // ✅ FIXED: Changed from 'break_days'
        .select()
        .eq('user_id', currentUserId)
        .gte('break_date', startOfWeekStr);

    final breakDaysLeft = weeklyBreakGoal - breaksThisWeek.length;

    if (!mounted) return;

    // Show dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.blue[100],
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.bedtime,
                color: Colors.blue[700],
                size: 28,
              ),
            ),
            const SizedBox(width: 12),
            const Text('Take a Break Day?'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: breakDaysLeft > 0 ? Colors.blue[50] : Colors.red[50],
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: breakDaysLeft > 0 ? Colors.blue[200]! : Colors.red[200]!,
                  width: 2,
                ),
              ),
              child: Row(
                children: [
                  Text(
                    '$breakDaysLeft',
                    style: TextStyle(
                      fontSize: 48,
                      fontWeight: FontWeight.bold,
                      color: breakDaysLeft > 0 ? Colors.blue[700] : Colors.red[700],
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Text(
                      'break day${breakDaysLeft == 1 ? '' : 's'} left\nuntil next week',
                      style: TextStyle(
                        fontSize: 14,
                        color: breakDaysLeft > 0 ? Colors.blue[900] : Colors.red[900],
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
              breakDaysLeft > 0
                  ? 'Taking a break counts as your workout for today without breaking your streak.'
                  : 'You\'ve used all your break days this week. Check back Monday!',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[700],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: breakDaysLeft > 0 
                ? () => Navigator.pop(context, true)
                : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue[700],
              disabledBackgroundColor: Colors.grey[300],
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
            child: const Text('Yes, Take Break'),
          ),
        ],
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
                  child: Text('Break day taken! Your streak is safe 💤'),
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

  void _updateCountdown() {
    if (!mounted) return;
    
    final now = DateTime.now();
    final midnight = DateTime(now.year, now.month, now.day + 1);
    final difference = midnight.difference(now);
    
    final hours = difference.inHours;
    final minutes = difference.inMinutes % 60;
    
    setState(() {
      _timeUntilMidnight = '${hours}h ${minutes}m';
    });
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
      
      // ✅ 1. Update state
      setState(() {
        _customSelection = result;
        _streakSortMode = StreakSortMode.custom;
        _currentCarouselIndex = 0;  // Reset to top item
      });
      if (_carouselController.hasClients) {
        _carouselController.jumpToPage(10080);
      }
      
      // ✅ 2. Save to database (both mode AND order)
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId != null) {
        try {
          await Supabase.instance.client.from('user_profiles').update({
            'preferred_streak_sort': 'custom',
            'custom_streak_order': result.map((s) => s.teamId).toList(),
          }).eq('id', userId);
          
          debugLog('💾 Saved custom mode with order: ${result.map((s) => s.teamId).join(", ")}');
          
          // ✅ 3. Show success message
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Row(
                  children: [
                    const Icon(Icons.check_circle, color: Colors.white),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Custom order saved!',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                backgroundColor: Colors.green[600],
                duration: const Duration(seconds: 3),
              ),
            );
          }
        } catch (e) {
          debugLog('❌ Error saving custom order: $e');
        }
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

  Future<bool> _isStreakCompleteToday(TeamStreak streak) async {
    final currentUserId = _supabase.auth.currentUser?.id;
    if (currentUserId == null) return false;

    // Check if current user checked in
    final userCheckedIn = streak.todayCheckIns.any((checkIn) => 
      checkIn.userId == currentUserId
    );

    // Get real members (excluding Coach Max)
    final realMembers = streak.members.where((m) => !m.isCoachMax).toList();
    final memberIds = realMembers.map((m) => m.userId).toList();
    
    // The user's own local date key — matches the break_date rows and check_in_date.
    final today = localTodayString();

    // Get break day status
    final breakDayStatus = await _breakDayService.getTeamBreakDayStatus(memberIds, today);

    if (streak.isCoachMaxTeam) {
      // ✅ COACH MAX TEAM
      // Complete if user checked in OR is on break (Coach Max covers)
      final userOnBreak = breakDayStatus[currentUserId] ?? false;
      return userCheckedIn || userOnBreak;
    } else {
      // ✅ FRIEND TEAM
      // Complete if all members checked in OR are on break
      for (var member in realMembers) {
        final checkedIn = streak.todayCheckIns.any((c) => c.userId == member.userId);
        final onBreak = breakDayStatus[member.userId] ?? false;
        
        if (!checkedIn && !onBreak) {
          return false; // Someone is missing
        }
      }
      return true;
    }
  }

  Future<void> _loadStreakData({bool showLoading = true}) async {
    // ── STEP 1: Show cached data instantly ──────────────────
    final cached = await _loadCachedDashboard();
    if (cached != null && mounted) {
      setState(() {
        _allStreaks           = [];
        _hasCheckedInToday   = cached['hasCheckedIn']   ?? false;
        _pendingRequests     = cached['pendingRequests'] ?? 0;
        _totalWorkouts       = cached['totalWorkouts']  ?? 0;
        _buddyCount          = cached['buddyCount']     ?? 0;
        _achievementCount    = cached['achievements']   ?? 0;
        _isLoading           = _allStreaks.isEmpty;
      });
      // Trigger entrance animation on first cached load
      if (!_hasAnimatedEntrance && _allStreaks.isNotEmpty) {
        _currentCarouselIndex = 0;
        Future.delayed(const Duration(milliseconds: 100), () {
          if (mounted) {
            _carouselEntranceController.forward();
            _hasAnimatedEntrance = true;
          }
        });
      }
    } else if (showLoading && mounted) {
      setState(() => _isLoading = true);
    }
  
    // ── STEP 2: Load preferences (fast, single query) ───────
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId != null) {
      try {
        final prefs = await Supabase.instance.client
            .from('user_profiles')
            .select('preferred_streak_sort, custom_streak_order')
            .eq('id', userId)
            .single();
  
        final savedMode = prefs['preferred_streak_sort'];
        if (savedMode != null && savedMode.toString().isNotEmpty) {
          _streakSortMode = StreakSortMode.values.firstWhere(
            (e) => e.name == savedMode,
            orElse: () => StreakSortMode.highestCurrent,
          );
        } else {
          _streakSortMode = StreakSortMode.highestCurrent;
        }
  
        if (_streakSortMode == StreakSortMode.custom &&
            prefs['custom_streak_order'] != null) {
          _customStreakOrder = List<String>.from(prefs['custom_streak_order']);
          debugLog('📥 Loaded custom order: ${_customStreakOrder.length} team IDs');
        } else {
          _customStreakOrder = [];
        }
        debugLog('📥 Loaded sort mode: ${_streakSortMode.displayName}');
      } catch (e) {
        debugLog('⚠️ Could not load preferences: $e');
        _customStreakOrder = [];
      }
    }
  
    // ── STEP 3: Sync + fetch streaks ────────────────────────
    _syncTeamCheckIns(); // fire and forget - don't await
    final allStreaks = await _teamStreakService.getAllUserStreaks();
    final nicknames  = await nicknameService.getAllNicknames();
  
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
  
    final today = DateTime.now();
    final todayStr = DateTime(today.year, today.month, today.day)
        .toIso8601String()
        .split('T')[0];
  
    // Local frame: check_in_date labels are the user's own local dates now,
    // so the heatmap's 7-day lower bound must be local too (was .toUtc()).
    final sevenDaysAgoStr = DateTime.now()
        .subtract(const Duration(days: 7))
        .toIso8601String()
        .split('T')[0];

    final results = await Future.wait([
      // [0] completion status for each streak
      Future.wait(uniqueStreaks.map((s) => _isStreakCompleteToday(s))),
      // [1] has checked in today
      _teamStreakService.hasCheckedInToday(),
      // [2] today's workouts
      _workoutService.getTodaysWorkouts(),
      // [3] pending friend requests
      FriendService().getPendingRequests(),
      // [4] friend list
      FriendService().getFriends(),
      // [5] all workouts (for completed count)
      _workoutService.getAllWorkouts(),
      // [6] real check-in dates for the heatmap (last 7 days, this user)
      // — fixes the bug where days were painted as "done" purely from
      // arithmetic on current_streak rather than real check-in history.
      currentUserId == null
          ? Future.value(<Map<String, dynamic>>[])
          : Supabase.instance.client
              .from('daily_team_checkins')
              .select('check_in_date')
              .eq('user_id', currentUserId)
              .gte('check_in_date', sevenDaysAgoStr),
      // [7] own uncancelled break days — heatmap third state + today badge
      currentUserId == null
          ? Future.value(<Map<String, dynamic>>[])
          : Supabase.instance.client
              .from('break_day_usage')
              .select('break_date')
              .eq('user_id', currentUserId)
              .gte('break_date', sevenDaysAgoStr)
              .isFilter('cancelled_at', null),
    ]);
  
    final completionList   = results[0] as List<bool>;
    final hasCheckedIn     = results[1] as bool;
    final todaysWorkouts   = results[2] as List<Map<String, dynamic>>;
    final pendingFriends   = results[3] as List;
    final friends          = results[4] as List;
    final allWorkouts      = results[5] as List<Map<String, dynamic>>;
    final checkInDateRows  = results[6] as List<Map<String, dynamic>>;
    final myCheckInDates   = checkInDateRows
        .map((r) => r['check_in_date'] as String)
        .toSet();
    final myBreakDates     = (results[7] as List<Map<String, dynamic>>)
        .map((r) => r['break_date'] as String)
        .toSet();

    // Buddy break badges: a buddy's break is dated in THEIR own local today
    // (per-user tz), so resolution happens server-side via is_on_break_today
    // (safe_user_tz) — never with the viewer's local date. Failures degrade
    // to no badge.
    final buddyIds = uniqueStreaks
        .where((s) => !s.isCoachMaxTeam)
        .expand((s) => s.members)
        .map((m) => m.userId)
        .where((id) => id != currentUserId)
        .toSet();
    final buddyOnBreak = <String, bool>{};
    await Future.wait(buddyIds.map((id) async {
      try {
        final res = await Supabase.instance.client
            .rpc('is_on_break_today', params: {'p_user_id': id});
        buddyOnBreak[id] = res == true;
      } catch (_) {
        buddyOnBreak[id] = false;
      }
    }));
  
    final completionStatus = <String, bool>{};
    for (int i = 0; i < uniqueStreaks.length; i++) {
      completionStatus[uniqueStreaks[i].id] = completionList[i];
    }
  
    // Highest streak (already sorted, just pick first)
    final highestStreak = uniqueStreaks.isEmpty
        ? null
        : uniqueStreaks.reduce((a, b) =>
            a.currentStreak > b.currentStreak ? a : b);
  
    final pendingWorkouts = todaysWorkouts.where((w) =>
        w['buddy_id'] == currentUserId &&
        w['buddy_status'] == 'pending').length;
  
    final completedWorkouts =
        allWorkouts.where((w) => w['status'] == 'completed').length;
  
    int achievements = 0;
    if (hasCheckedIn) achievements++;
    if ((highestStreak?.currentStreak ?? 0) >= 7) achievements++;
    if ((highestStreak?.currentStreak ?? 0) >= 30) achievements++;
    if (friends.length >= 3) achievements++;
  
    if (!mounted) return;
  
    setState(() {
      _allStreaks            = uniqueStreaks;
      _nicknames             = nicknames;
      _streakCompletionStatus = completionStatus;
      _highestStreak         = highestStreak;
      _myCheckInDates        = myCheckInDates;
      _myBreakDates          = myBreakDates;
      _isOnBreakToday        = myBreakDates.contains(localTodayString());
      _buddyOnBreakToday     = buddyOnBreak;
      _hasCheckedInToday     = hasCheckedIn;
      _todaysWorkouts        = todaysWorkouts;
      _pendingRequests       = pendingFriends.length + pendingWorkouts;
      _totalWorkouts         = completedWorkouts;
      _buddyCount            = friends.length;
      _friendIds = List<String>.from(friends.map((f) => f['id']));
      _achievementCount      = achievements;
      _isLoading             = false;
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
  
    // ── STEP 5: Save fresh data to cache ────────────────────
    await _saveCachedDashboard(
      streaks:         uniqueStreaks,
      hasCheckedIn:    hasCheckedIn,
      pendingRequests: pendingFriends.length + pendingWorkouts,
      totalWorkouts:   completedWorkouts,
      buddyCount:      friends.length,
      achievements:    achievements,
    );

  }


  Future<void> _checkWeeklyPlan() async {
    if (_weeklyPlanCheckedThisSession) return; // once per app open
    _weeklyPlanCheckedThisSession = true;       // set before await → no re-fire
    final needsPlan = await _breakDayService.needsToSetWeeklyPlan();
    if (!mounted) return;
    if (needsPlan) {
      _showWeeklyPlanDialog();
    }
  }

  Future<void> _showWeeklyPlanDialog() async {
    int selectedWorkoutDays = 5;

    final result = await showDialog<int>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _WeeklyPlanDialog(
        initialWorkoutDays: selectedWorkoutDays,
      ),
    );

    if (result != null) {
      await _breakDayService.setWeeklyBreakPlan(result);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Set $result break day${result == 1 ? '' : 's'} for this week! 🎉'),
          backgroundColor: Colors.green,
        ),
      );
      setState(() {}); // Refresh UI
      await _loadStreakData();
    }
  }

  

  Future<Map<String, dynamic>?> _loadUserProfile() async {
    try {
      final currentUserId = Supabase.instance.client.auth.currentUser?.id;
      if (currentUserId == null) return null;

      final response = await Supabase.instance.client
          .from('user_profiles')
          .select('avatar_id, display_name')
          .eq('id', currentUserId)
          .single();

      return response;
    } catch (e) {
      return null;
    }
  }

  Future<Map<String, dynamic>?> _loadCachedDashboard() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = prefs.getString('dashboard_cache');
      if (json == null) return null;
      return Map<String, dynamic>.from(jsonDecode(json) as Map);
    } catch (_) {
      return null;
    }
  }
  
  Future<void> _saveCachedDashboard({
    required List<TeamStreak> streaks,
    required bool hasCheckedIn,
    required int pendingRequests,
    required int totalWorkouts,
    required int buddyCount,
    required int achievements,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // We only cache simple stats, not full streak objects
      // (streak objects are rebuilt fresh each load)
      await prefs.setString('dashboard_cache', jsonEncode({
        'hasCheckedIn':    hasCheckedIn,
        'pendingRequests': pendingRequests,
        'totalWorkouts':   totalWorkouts,
        'buddyCount':      buddyCount,
        'achievements':    achievements,
        // Don't cache streaks — they're complex objects, just skip spinner
      }));
    } catch (_) {}
  }
  

  Future<void> _checkIn() async {
      if (_hasCheckedInToday) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('You already checked in today! 💪'),
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

        final linkedWorkoutId = activeSession['workout_id'] as String?;

        final completed = await WorkoutCheckInSheet.show(
          context,
          workoutType: activeSession['workout_type'] ?? 'Workout',
          workoutEmoji: activeSession['workout_emoji'] ?? '💪',
          plannedDuration: activeSession['planned_duration'] ?? 30,
          onCheckInComplete: () async {
            // A session linked to a workouts row must complete that row too —
            // otherwise it hangs in_progress until the 3-hour sweep, blocking
            // both users and losing the partner-completion credit.
            if (linkedWorkoutId != null) {
              await _workoutService.completeWorkoutWithDuration(linkedWorkoutId);
            }
            final result = await _teamStreakService.checkInAllTeams(
              workoutName: activeSession['workout_type'] ?? 'Workout',
              workoutEmoji: activeSession['workout_emoji'] ?? '💪',
              durationMinutes: activeSession['planned_duration'] ?? 30,
            );

            if (result['success'] == true) {
              HapticFeedback.heavyImpact();
              if (!mounted) return false;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Row(children: [
                    const Icon(Icons.check_circle, color: Colors.white),
                    const SizedBox(width: 12),
                    Expanded(child: Text(result['message'] ?? 'Check-in successful!')),
                  ]),
                  backgroundColor: Colors.green,
                  duration: const Duration(seconds: 3),
                ),
              );

              // 🏆 Show workout achievement toasts
              final workoutAchievements = result['workout_achievements'];
              if (workoutAchievements is List && workoutAchievements.isNotEmpty && mounted) {
                AchievementToast.show(
                  context,
                  List<AchievementUnlockResult>.from(workoutAchievements),
                );
              }

              await _loadStreakData();
              _checkForMilestone();
              return result['partner_bonus_earned'] == true;
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

  Future<void> _checkForActiveWorkout() async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;
    
    try {
      final existing = await Supabase.instance.client
          .from('active_checkin_sessions')
          .select()
          .eq('user_id', userId)
          .maybeSingle();
      
      if (existing != null && mounted) {
        // Active workout exists - just open the timer sheet directly
        // It will automatically show the correct elapsed time
        _checkIn();
      }
    } catch (e) {
      debugLog('Error checking for active workout: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final displayItems = _allStreaks.isEmpty ? null : _wheelItems();
    return Stack(
      children: [
        Scaffold(
          backgroundColor: c.clayBg,
          body: _isLoading
              ? _buildLoadingSkeleton()
              : SafeArea(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildDashboardHeader(),
                      Expanded(
                        child: SingleChildScrollView(
                          // The nav bar floats over the body (extendBody), so
                          // reserve its height or the last card hides under it.
                          padding: EdgeInsets.only(
                            bottom: 62 + MediaQuery.paddingOf(context).bottom,
                          ),
                          child: _buildDashboardBody(displayItems),
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
          Center(child: _skeletonBox(180, 12, radius: 6)),
          const SizedBox(height: 24),
          // Wheel: focused centre, two peeking
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _skeletonCircle(76),
              _skeletonCircle(108),
              _skeletonCircle(76),
            ],
          ),
          const SizedBox(height: 26),
          // Name + streak count
          Center(child: _skeletonBox(120, 14, radius: 7)),
          const SizedBox(height: 10),
          Center(child: _skeletonBox(190, 30, radius: 8)),
          const SizedBox(height: 22),
          // CTA
          _skeletonBox(double.infinity, 58, radius: 19),
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
                _skeletonBox(180, 26, radius: 8),
                const Spacer(),
                _skeletonCircle(44),
                const SizedBox(width: 10),
                _skeletonCircle(46),
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
  
  Widget _skeletonBox(double width, double height, {double radius = 8}) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.4, end: 0.9),
      duration: const Duration(milliseconds: 900),
      curve: Curves.easeInOut,
      builder: (_, value, __) => Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: AppColors.of(context).claySurfaceLight.withValues(alpha: value),
          borderRadius: BorderRadius.circular(radius),
        ),
      ),
    );
  }
  
  Widget _skeletonCircle(double size) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.4, end: 0.9),
      duration: const Duration(milliseconds: 900),
      curve: Curves.easeInOut,
      builder: (_, value, __) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: AppColors.of(context).claySurfaceLight.withValues(alpha: value),
        ),
      ),
    );
  }

  Widget _buildEmptyFavoritesCard() {
    final c = AppColors.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 40, 20, 20),
      child: _clayTraySlab(
        padding: const EdgeInsets.all(30),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _trayGlyph('⭐', role: c.warn),
            const SizedBox(height: 18),
            Text(
              'No Favorites Yet!',
              style: TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.w800,
                color: c.readableForeground(c.claySurface),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Star your workout buddies to add them here.\nTap the ⭐ on their avatar when viewing them.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: c.inkMuted, height: 1.5),
            ),
            const SizedBox(height: 22),
            _trayAction('View All Streaks', c.info, () {
              // Switch back to Highest Streak mode
              setState(() {
                _streakSortMode = StreakSortMode.highestCurrent;
              });
              // Save preference
              final userId = Supabase.instance.client.auth.currentUser?.id;
              if (userId != null) {
                Supabase.instance.client.from('user_profiles').update({
                  'preferred_streak_sort': 'highestCurrent',
                }).eq('id', userId);
              }
            }),
          ],
        ),
      ),
    );
  }

  void _showQuickCreateWorkoutDialog() {
    ScheduleWorkoutSheet.show(
      context,
      onWorkoutScheduled: _loadStreakData,
    );
  }

  Future<void> _acceptWorkoutInviteDash(String workoutId) async {
    final success = await _workoutService.acceptWorkoutInvitation(workoutId);
    
    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Workout invitation accepted! 🎉'),
          backgroundColor: Colors.green,
        ),
      );
      _loadStreakData();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to accept invitation'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _declineWorkoutInviteDash(String workoutId) async {
    final success = await _workoutService.declineWorkoutInvitation(workoutId);
    
    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Workout invitation declined'),
          backgroundColor: Colors.grey,
        ),
      );
      _loadStreakData();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to decline invitation'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  String _formatDurationDash(int? minutes) {
    if (minutes == null) return '';
    final hours = minutes ~/ 60;
    final mins = minutes % 60;
    if (hours > 0) {
      return mins > 0 ? '${hours}h ${mins}m' : '${hours}h';
    }
    return '${mins}m';
  }

  void _showAllStreaks() {
    showDialog(
      context: context,
      builder: (context) => _AllStreaksDialog(streaks: _listStreaks),
    );
  }

  String _getGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) {
      return 'Good Morning';
    } else if (hour < 17) {
      return 'Good Afternoon';
    } else if (hour < 21) {
      return 'Good Evening';
    } else {
      return 'Good Night';
    }
  }

  String _getCurrentDate() {
    final now = DateTime.now();
    final days = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
    final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    
    return '${days[now.weekday - 1]}, ${months[now.month - 1]} ${now.day}';
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

  void _checkForMilestone() {
    if (_highestStreak == null) return;
    
    final currentStreak = _highestStreak!.currentStreak;
    final milestones = [1, 3, 7, 14, 30, 50, 100, 365];
    
    if (milestones.contains(currentStreak) && currentStreak > _lastCelebratedStreak) {
      _lastCelebratedStreak = currentStreak;
      _showMilestoneDialog(currentStreak).then((_) {
        if (mounted) {
          _confettiController.play();
          _confettiControllerRight.play();
        }
      });
    }
  }

  Future<void> _showMilestoneDialog(int streak) async {

    String title = '';
    String emoji = '';
    String message = '';
    
    switch (streak) {
      case 1:
        title = 'First Check-in!';
        emoji = '🌱';
        message = 'Your journey begins!';
        break;
      case 3:
        title = 'Building Momentum!';
        emoji = '🔥';
        message = 'Three days strong!';
        break;
      case 7:
        title = 'On Fire!';
        emoji = '🔥🔥';
        message = 'One week streak unlocked!';
        break;
      case 14:
        title = 'Two Weeks!';
        emoji = '💪';
        message = 'You\'re crushing it!';
        break;
      case 30:
        title = 'Diamond Status!';
        emoji = '💎';
        message = 'A full month! Legendary!';
        break;
      case 50:
        title = 'Unstoppable!';
        emoji = '⚡';
        message = '50 days of dedication!';
        break;
      case 100:
        title = 'LEGEND!';
        emoji = '👑';
        message = '100 days! You\'re a champion!';
        break;
      case 365:
        title = 'IMMORTAL!';
        emoji = '🏆';
        message = 'A FULL YEAR! Incredible!';
        break;
      default:
        title = 'Milestone Reached!';
        emoji = '🎉';
        message = '$streak days strong!';
    }
    
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Column(
          children: [
            Text(
              emoji,
              style: const TextStyle(fontSize: 64),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 18),
            ),
            const SizedBox(height: 16),
            Text(
              '$streak Day Streak!',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.bold,
                color: Colors.orange[700],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Awesome!'),
          ),
        ],
      ),
    );
  }

  IconData _getWorkoutIcon(String? type) {
    switch (type?.toLowerCase()) {
      case 'cardio':
        return Icons.directions_run;
      case 'strength':
      case 'weights':
        return Icons.fitness_center;
      case 'upper body':
        return Icons.accessibility_new;
      case 'lower body':
      case 'legs':
      case 'leg day':
        return Icons.directions_walk;
      case 'full body':
        return Icons.sports_gymnastics;
      case 'hiit':
        return Icons.flash_on;
      case 'yoga':
        return Icons.self_improvement;
      default:
        return Icons.sports;
    }
  }

  Color _getWorkoutColorDash(String? type) {
    switch (type?.toLowerCase()) {
      case 'cardio':
        return Colors.red[700]!;
      case 'strength':
      case 'weights':
        return Colors.blue[700]!;
      case 'legs':
      case 'leg day':
      case 'lower body':
        return Colors.orange[700]!;
      case 'upper body':
        return Colors.purple[700]!;
      case 'full body':
        return Colors.indigo[700]!;
      case 'hiit':
        return Colors.deepOrange[700]!;
      case 'yoga':
        return Colors.teal[700]!;
      default:
        return Colors.green[700]!;
    }
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
                Text('Synced check-ins to ${result['synced']} team${result['synced'] == 1 ? "" : "s"}'),
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

  void _showSortBottomSheet() {
    assert(
      _sortModeDisplayOrder.length == StreakSortMode.values.length,
      'Every StreakSortMode must be listed in _sortModeDisplayOrder',
    );
    final appColors = AppColors.of(context);
    HapticFeedback.mediumImpact();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => Container(
        decoration: BoxDecoration(
          color: appColors.cardBackground,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: EdgeInsets.fromLTRB(
          24, 24, 24, MediaQuery.of(sheetContext).padding.bottom + 20,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Handle bar
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: appColors.divider,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              
              // Title with info hint
              Column(
                children: [
                  Text(
                    '📊 Sort Your Streaks',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '👆 Tap to select • ✋ Long-press for info',
                    style: TextStyle(
                      fontSize: 13,
                      color: appColors.subtleText,
                      fontStyle: FontStyle.italic,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
              const SizedBox(height: 20),
              
              // Grid with long-press handlers
              GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
                childAspectRatio: 2.0,
                physics: const NeverScrollableScrollPhysics(),
                children: _sortModeDisplayOrder.map((mode) {
                  final isSelected = mode == _streakSortMode;
                  
                  return GestureDetector(
                    onTap: () async {
                      HapticFeedback.selectionClick();
                      
                      if (mode == StreakSortMode.custom) {
                        Navigator.pop(context);
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          _showCustomModeSelector();
                        });
                        return;
                      }
                      
                      setState(() {
                        _streakSortMode = mode;
                        _currentCarouselIndex = 0;
                      });
                      if (_carouselController.hasClients) {
                        _carouselController.jumpToPage(10080);
                      }
                      
                      Navigator.pop(context);
                      
                      final userId = Supabase.instance.client.auth.currentUser?.id;
                      if (userId != null) {
                        await Supabase.instance.client.from('user_profiles').update({
                          'preferred_streak_sort': mode.name,
                        }).eq('id', userId);
                      }
                      
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (_carouselController.hasClients && mounted) {
                          _carouselController.jumpToPage(1000);
                        }
                      });
                    },
                    
                    onLongPress: () {
                      HapticFeedback.mediumImpact();
                      _showSortModeInfo(context, mode);
                    },
                    
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? appColors.avatarRing.withOpacity(0.12)
                            : appColors.sectionBackground,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isSelected ? appColors.avatarRing : appColors.cardBorder,
                          width: isSelected ? 2 : 1,
                        ),
                      ),
                      child: Row(
                        children: [
                          Text(mode.emoji, style: const TextStyle(fontSize: 24)),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  mode.displayName,
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                                    color: isSelected
                                        ? appColors.avatarRing
                                        : Theme.of(context).colorScheme.onSurface,
                                  ),
                                ),
                                Text(
                                  mode.description,
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: appColors.subtleText,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showSortModeInfo(BuildContext context, StreakSortMode mode) {
    final appColors = AppColors.of(context);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Text(mode.emoji, style: const TextStyle(fontSize: 28)),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                mode.displayName,
                style: TextStyle(
                  fontSize: 20,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _getSortModeDetailedDescription(mode),
              style: TextStyle(
                fontSize: 15,
                color: Theme.of(context).colorScheme.onSurface,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.blue.withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  Icon(Icons.lightbulb_outline, color: Colors.blue[400], size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _getSortModeExample(mode),
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.blue[400],
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Got it!'),
          ),
        ],
      ),
    );
  }

  String _getSortModeDetailedDescription(StreakSortMode mode) {
    switch (mode) {
      case StreakSortMode.highestCurrent:
        return 'Shows buddies with the longest active streak first. '
            'This highlights who you\'re currently working out with most consistently.';
      
      case StreakSortMode.mostWorkouts:
        return 'Ranks buddies by total number of workouts completed together. '
            'Perfect for seeing your most dedicated long-term partners.';
      
      case StreakSortMode.bestAllTime:
        return 'Displays buddies based on your all-time best streak together. '
            'Shows legendary partnerships even if the streak has broken.';
      
      case StreakSortMode.mostRecent:
        return 'Sorts by who you worked out with most recently. '
            'Great for keeping track of active partnerships.';
      
      case StreakSortMode.favorites:
        return 'Shows only buddies you\'ve starred as favorites. '
            'Use the ⭐ icon to mark your go-to workout partners!';
      
      case StreakSortMode.custom:
        return 'Manual selection mode. Scroll to view specific buddies in any order. '
            'Activates automatically when you browse away from preset center.';
      
      case StreakSortMode.mostUrgent:
        return 'Puts streaks nobody has checked into today at the top. '
            'Ties break by longest current streak, so you protect the biggest one first.';
      
      case StreakSortMode.alphabetical:
        return 'Orders buddies by name, A to Z. '
            'Handy when you know who you\'re looking for and just want to find them fast.';
    }
  }

  String _getSortModeExample(StreakSortMode mode) {
    switch (mode) {
      case StreakSortMode.highestCurrent:
        return 'Example: Sarah (15 days) appears before Mike (8 days)';
      
      case StreakSortMode.mostWorkouts:
        return 'Example: Mike (124 workouts) appears before Sarah (89 workouts)';
      
      case StreakSortMode.bestAllTime:
        return 'Example: Sarah (best: 45 days) appears before Mike (best: 32 days)';
      
      case StreakSortMode.mostRecent:
        return 'Example: Today\'s partners appear first, then yesterday\'s, etc.';
      
      case StreakSortMode.favorites:
        return 'Only your starred buddies appear. Star anyone with the ⭐ icon!';
      
      case StreakSortMode.custom:
        return 'Scroll freely! Swipe left/right to browse all your workout partners.';
      
      case StreakSortMode.mostUrgent:
        return 'Example: Sarah (12 days, nobody in yet) appears before Mike (30 days, done)';
      
      case StreakSortMode.alphabetical:
        return 'Example: Alex appears before Mike, Mike before Sarah';
    }
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
                  ? '⭐ ${streak.teamName} added to favorites!' 
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

  void _showBuddyProfile(TeamStreak streak, TeamMember buddy) {
    final nickname = _nicknames[buddy.userId];
    
    BuddyProfileSheet.show(
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
      List<AchievementUnlockResult> _pendingAchievements = [];

      await showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (modalContext) => WorkoutSelectionModal(
          onWorkoutSelected: (template, duration, notes, extraAchievements) {
            selectedTemplate = template;
            selectedDuration = duration;
            selectedNotes = notes;
            _pendingAchievements = extraAchievements;
          },
        ),
      );

      if (selectedTemplate == null || !mounted) return;

      debugLog('🎲 Pending achievements count: ${_pendingAchievements.length}');

      // 🏆 Show Feeling Lucky toast if randomiser was used
      if (_pendingAchievements.isNotEmpty && mounted) {
        AchievementToast.show(context, _pendingAchievements);
        _pendingAchievements = [];
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
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(children: [
                const Icon(Icons.check_circle, color: Colors.white),
                const SizedBox(width: 12),
                Expanded(child: Text(result['message'] ?? 'Check-in successful!')),
              ]),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 3),
            ),
          );

          // 🏆 Show workout achievement toasts
          final workoutAchievements = result['workout_achievements'];
          if (workoutAchievements is List && workoutAchievements.isNotEmpty && mounted) {
            AchievementToast.show(
              context,
              List<AchievementUnlockResult>.from(workoutAchievements),
            );
          }

          await _loadStreakData();
          _checkForMilestone();
          return result['partner_bonus_earned'] == true;
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

  // ── Home screen header delegate ───────────────────────────────
  class _HomeHeaderDelegate extends SliverPersistentHeaderDelegate {
    final String greeting;
    final int pendingRequests;
    final VoidCallback onNotificationTap;

    const _HomeHeaderDelegate({
      required this.greeting,
      required this.pendingRequests,
      required this.onNotificationTap,
    });

    @override
    double get minExtent => 80;
    @override
    double get maxExtent => 80;

    @override
    Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
      return Container(
        color: Colors.transparent,
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    greeting,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
                Stack(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.notifications_outlined, color: Colors.white),
                      onPressed: onNotificationTap,
                    ),
                    if (pendingRequests > 0)
                      Positioned(
                        right: 8,
                        top: 8,
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: const BoxDecoration(
                            color: Colors.red,
                            shape: BoxShape.circle,
                          ),
                          constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                          child: Text(
                            '$pendingRequests',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    }

    @override
    bool shouldRebuild(_HomeHeaderDelegate old) =>
        greeting != old.greeting || pendingRequests != old.pendingRequests;
  }


class _AllStreaksDialog extends StatefulWidget {
  final List<TeamStreak> streaks;
  const _AllStreaksDialog({required this.streaks});

  @override
  State<_AllStreaksDialog> createState() => _AllStreaksDialogState();
}

class _AllStreaksDialogState extends State<_AllStreaksDialog> {
  late List<TeamStreak> _streaks;

  @override
  void initState() {
    super.initState();
    _streaks = List.from(widget.streaks);
  }

  // ── Rename ──────────────────────────────────────────────
  Future<void> _showRenameDialog(TeamStreak streak) async {
    final appColors = AppColors.of(context);
    final cs = Theme.of(context).colorScheme;
    final controller =
        TextEditingController(text: streak.teamName);

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
            TextField(
              controller: controller,
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
              onSubmitted: (v) => Navigator.pop(context, v),
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
                Navigator.pop(context, controller.text),
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
          backgroundColor: const Color(0xFF10B981),
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
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Color(0xFFF97316),
                    Color(0xFFEA580C)
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
                    color: Colors.white.withOpacity(0.2),
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
            ? const Color(0xFFF97316).withOpacity(0.06)
            : appColors.sectionBackground,
        borderRadius: BorderRadius.circular(11),
        border: Border.all(
          color: isCoach
              ? const Color(0xFFF97316).withOpacity(0.2)
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
                            const Color(0xFFEA580C)
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
                        ? const Color(0xFF10B981)
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
              onTap: () => _showRenameDialog(streak),
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
                    ? const Color(0xFF10B981).withOpacity(0.12)
                    : appColors.sectionBackground,
                shape: BoxShape.circle,
              ),
              child: Icon(
                isComplete ? Icons.check : Icons.access_time,
                size: 15,
                color: isComplete
                    ? const Color(0xFF10B981)
                    : appColors.subtleText,
              ),
            ),
        ]),
      ),
    );
  }
}
class _StatItem extends StatelessWidget {
  final String label;
  final String value;

  const _StatItem(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          value,
          style: const TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: Colors.orange,
          ),
          overflow: TextOverflow.ellipsis,
          maxLines: 1,
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: AppColors.of(context).subtleText,
          ),
          textAlign: TextAlign.center,
          overflow: TextOverflow.ellipsis,
          maxLines: 2,
        ),
      ],
    );
  }
}

// Schedule Page with Real Functionality
class SchedulePage extends StatefulWidget {
  const SchedulePage({super.key});

  @override
  State<SchedulePage> createState() => _SchedulePageState();
}

class _SchedulePageState extends State<SchedulePage> {
  final WorkoutService _workoutService = WorkoutService();
  final FriendService _friendService = FriendService();

  int _refreshTrigger = 0;
  int _completedRefreshTrigger = 0;

  
  List<Map<String, dynamic>> _upcomingWorkouts = [];
  List<Map<String, dynamic>> _friends = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    loadData();
    _debugCheckInvites();
  }

  Future<void> _debugCheckInvites() async {
    final currentUserId = Supabase.instance.client.auth.currentUser?.id;
    
    final allInvites = await Supabase.instance.client
        .from('workout_invites')
        .select('*');
    
    debugLog('🔍 DEBUG: ALL invites in database: $allInvites');
    
    final myInvites = await Supabase.instance.client
        .from('workout_invites')
        .select('*')
        .eq('recipient_id', currentUserId!);
    
    debugLog('🔍 DEBUG: My invites as recipient: $myInvites');
  }

  Future<void> loadData() async {
    if (!mounted) return; // ✅ CHECK MOUNTED at start
    
    setState(() {
      _isLoading = true;
    });

    final workouts = await _workoutService.getUpcomingWorkouts();
    final friends = await _friendService.getFriends();

    if (!mounted) return; // ✅ CHECK MOUNTED before setState
    
    setState(() {
      _upcomingWorkouts = workouts.where((w) => 
        w['status'] != 'completed' && w['status'] != 'cancelled'
      ).toList();
      _friends = friends;
      _isLoading = false;
      _completedRefreshTrigger++;
    });
  }

  void _showCreateWorkoutDialog() {
    ScheduleWorkoutSheet.show(
      context,
      onWorkoutScheduled: loadData,
    );
  }

  Future<void> _startWorkout(String workoutId) async {
    // Get the workout details first
    final workout = _upcomingWorkouts.firstWhere(
      (w) => w['id'] == workoutId,
      orElse: () => {},
    );
    
    if (workout.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Workout not found'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // Check if buddy has accepted (if this is a buddy workout)
    if (workout['buddy_id'] != null && workout['buddy_status'] != 'accepted') {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Your buddy needs to accept the workout invitation first!'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    // Mark workout as in_progress in the database
    final started = await _workoutService.startWorkout(workoutId);
    if (!started) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to start workout'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // Get workout details for the timer
    final workoutType = workout['workout_type'] ?? 'Workout';
    final plannedDuration = workout['planned_duration_minutes'] ?? 30;
    
    // Map workout type to emoji
    String workoutEmoji = '💪';
    switch (workoutType.toLowerCase()) {
      case 'cardio':
        workoutEmoji = '🏃';
        break;
      case 'strength':
        workoutEmoji = '💪';
        break;
      case 'hiit':
        workoutEmoji = '⚡';
        break;
      case 'leg day':
      case 'lower body':
        workoutEmoji = '🦵';
        break;
      case 'upper body':
        workoutEmoji = '💪';
        break;
      case 'full body':
        workoutEmoji = '🏋️';
        break;
      case 'yoga':
        workoutEmoji = '🧘';
        break;
      default:
        workoutEmoji = '🏋️';
    }

    // Get buddy name for display
    final currentUserId = Supabase.instance.client.auth.currentUser?.id;
    final isCreator = workout['user_id'] == currentUserId;
    String? buddyName;
    if (isCreator && workout['buddy'] != null) {
      buddyName = workout['buddy']['display_name'];
    } else if (!isCreator && workout['creator'] != null) {
      buddyName = workout['creator']['display_name'];
    }

    // Link + anchor this user's session to the workout row before opening
    // the sheet: the timer then resumes the real clock (not zero), and the
    // sheet's cancel path takes the fair cancelWorkout logic instead of the
    // solo sweep.
    try {
      final fresh = await Supabase.instance.client
          .from('workouts')
          .select('workout_started_at')
          .eq('id', workoutId)
          .single();
      await Supabase.instance.client.from('active_checkin_sessions').upsert({
        'user_id': currentUserId,
        'started_at': fresh['workout_started_at'] ??
            DateTime.now().toUtc().toIso8601String(),
        'planned_duration': plannedDuration,
        'workout_type': workoutType,
        'workout_emoji': workoutEmoji,
        'workout_id': workoutId,
      }, onConflict: 'user_id');
    } catch (e) {
      debugLog('⚠️ Could not link session to workout: $e');
    }

    if (!mounted) return;

    // ✅ Open the WorkoutCheckInSheet timer!
    final completed = await WorkoutCheckInSheet.show(
      context,
      workoutType: buddyName != null ? '$workoutType with $buddyName' : workoutType,
      workoutEmoji: workoutEmoji,
      plannedDuration: plannedDuration,
      onCheckInComplete: () async {
        // Complete the scheduled workout
        await _workoutService.completeWorkoutWithDuration(workoutId);
        
        // Also check in to all team streaks (this makes the buddy workout count!)
        final teamStreakService = TeamStreakService();
        final result = await teamStreakService.checkInAllTeams(
          workoutName: workoutType,
          workoutEmoji: workoutEmoji,
          durationMinutes: plannedDuration,
        );

        if (result['success'] == true) {
          HapticFeedback.heavyImpact();
        }
        return result['partner_bonus_earned'] == true;
      },
    );

    // Refresh the list regardless of completion
    if (mounted) {
      loadData();
      
      if (completed == true) {
        // Show celebration for buddy workouts!
        final buddy = workout['buddy'];
        final creator = workout['creator'];
        String? celebrationBuddyName;
        
        if (isCreator && buddy != null) {
          celebrationBuddyName = buddy['display_name'];
        } else if (!isCreator && creator != null) {
          celebrationBuddyName = creator['display_name'];
        }
        
        WorkoutCelebration.show(
          context,
          workoutType: workoutType,
          duration: plannedDuration,
          buddyName: celebrationBuddyName,
        );
      }
    }
  }

  Future<void> _completeWorkout(String workoutId) async {
    final workout = _upcomingWorkouts.firstWhere(
      (w) => w['id'] == workoutId,
      orElse: () => <String, dynamic>{},
    );
    
    if (workout.isEmpty) {
      debugLog('❌ Workout not found in list');
      return;
    }
    
    final currentUserId = Supabase.instance.client.auth.currentUser?.id;
    
    // Check if this workout has a buddy and if they've accepted
    if (workout['buddy_id'] != null && workout['buddy_status'] != 'accepted') {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Your buddy needs to accept the workout invitation first!'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    
    // If workout is still scheduled (not started), use the timer flow
    if (workout['status'] == 'scheduled') {
      await _startWorkout(workoutId);
      return;
    }
    
    // If workout is in_progress, check if THIS user can complete
    if (workout['status'] == 'in_progress') {
      final isCreator = workout['user_id'] == currentUserId;
      final creatorCancelled = workout['creator_cancelled'] ?? false;
      final buddyCancelled = workout['buddy_cancelled'] ?? false;
      
      // Check if THIS user has cancelled - they can't complete!
      final thisUserCancelled = isCreator ? creatorCancelled : buddyCancelled;
      
      if (thisUserCancelled) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('You cancelled this workout - cannot complete'),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }
      
      // Open timer to continue the workout
      final workoutType = workout['workout_type'] ?? 'Workout';
      final plannedDuration = workout['planned_duration_minutes'] ?? 30;
      
      final startedAt = workout['workout_started_at'];
      if (startedAt != null) {
        await _startWorkout(workoutId);
        return;
      }
    }
    
    // Fallback: complete directly (for edge cases)
    await _doCompleteWorkout(workoutId, workout);
  }

  Future<void> _doCompleteWorkout(String workoutId, Map<String, dynamic> workout) async {
    final currentUserId = Supabase.instance.client.auth.currentUser?.id;
    if (currentUserId == null) return;
    
    // Get cancellation status
    final isCreator = workout['user_id'] == currentUserId;
    final creatorCancelled = workout['creator_cancelled'] ?? false;
    final buddyCancelled = workout['buddy_cancelled'] ?? false;
    
    // Complete the workout in database
    final success = await _workoutService.completeWorkoutWithDuration(workoutId);
    if (!success) {
      debugLog('❌ Failed to complete workout');
      return;
    }
    
    // Get workout details for celebration
    final workoutType = workout['workout_type'] ?? 'Workout';
    final startedAt = workout['workout_started_at'];
    int duration = 0;
    if (startedAt != null) {
      duration = DateTime.now().difference(DateTime.parse(startedAt)).inMinutes;
    }
    
    // Get buddy info
    String? buddyName;
    String? buddyId;
    final buddy = workout['buddy'];
    final creator = workout['creator'];
    
    if (isCreator) {
      buddyId = workout['buddy_id'];
      if (buddy != null) {
        buddyName = buddy['display_name'];
      }
    } else {
      buddyId = workout['user_id'];
      if (creator != null) {
        buddyName = creator['display_name'];
      }
    }
    
    if (!mounted) return;
    
    // Remove from local list for instant UI feedback
    setState(() {
      _upcomingWorkouts.removeWhere((w) => w['id'] == workoutId);
    });
    
    if (!mounted) return;
    
    // 🎉 Show celebration!
    WorkoutCelebration.show(
      context,
      workoutType: workoutType,
      duration: duration,
      buddyName: buddyName,
    );
    
    // ✅ FAIR CHECK-IN: Only check in users who DIDN'T cancel
    if (buddyId != null && workout['buddy_status'] == 'accepted') {
      try {
        final teamStreakService = TeamStreakService();
        final creatorId = workout['user_id'] as String?;
        final workoutBuddyId = workout['buddy_id'] as String?;
        
        // Check in CREATOR if they didn't cancel
        if (!creatorCancelled && creatorId != null) {
          if (creatorId == currentUserId) {
            final userResult = await teamStreakService.checkInAllTeams();
            debugLog('✅ Creator (current user) check-in: ${userResult['message']}');
          } else {
            final result = await teamStreakService.checkInAllTeamsForUser(creatorId, workoutId: workoutId);
            debugLog('✅ Creator check-in: Checked in to $result teams');
          }
        } else if (creatorCancelled) {
          debugLog('⚠️ Creator cancelled - NO streak credit');
        }
        
        // Check in BUDDY if they didn't cancel
        if (!buddyCancelled && workoutBuddyId != null) {
          final buddyActuallyCompleted = workout['buddy_completed_at'] != null;
          
          if (!buddyActuallyCompleted && workoutBuddyId != currentUserId) {
            debugLog('⚠️ Buddy accepted but never completed workout - NO streak credit');
          } else if (workoutBuddyId == currentUserId) {
            final userResult = await teamStreakService.checkInAllTeams();
            debugLog('✅ Buddy (current user) check-in: ${userResult['message']}');
          } else {
            final result = await teamStreakService.checkInAllTeamsForUser(workoutBuddyId, workoutId: workoutId);
            debugLog('✅ Buddy check-in: Checked in to $result teams');
          }
        } else if (buddyCancelled) {
          debugLog('⚠️ Buddy cancelled - NO streak credit');
        }
        
      } catch (e) {
        debugLog('❌ Auto check-in error: $e');
      }
    }
    
    if (!mounted) return;
    
    // Refresh UI
    await Future.delayed(const Duration(milliseconds: 300));
    
    if (!mounted) return;
    
    loadData();
  }

  Future<void> _cancelWorkout(String workoutId) async {
    if (!mounted) return; // ✅ CHECK MOUNTED
    
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancel Workout'),
        content: const Text('Are you sure you want to cancel this workout?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('No'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Yes, Cancel'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final success = await _workoutService.cancelWorkout(workoutId);
      if (success) {
        // Solo workout — force status to cancelled (no buddy to protect)
        final workout = _upcomingWorkouts.firstWhere(
          (w) => w['id'] == workoutId,
          orElse: () => <String, dynamic>{},
        );
        if (workout.isNotEmpty && workout['buddy_id'] == null) {
          await Supabase.instance.client
              .from('workouts')
              .update({'status': 'cancelled'})
              .eq('id', workoutId);
        }
        setState(() {
          _upcomingWorkouts.removeWhere((w) => w['id'] == workoutId);
        });
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Workout cancelled'),
            backgroundColor: Colors.grey,
          ),
        );
        loadData();
      }
    }
  }

  // ── Mutual ready check handlers ─────────────────────────────────────────

  Future<void> _setReady(String workoutId, bool ready) async {
    final err = await _workoutService.setCreatorReady(
        workoutId: workoutId, ready: ready);
    if (!mounted) return;
    if (err == null) {
      HapticFeedback.mediumImpact();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(ready
              ? "You're ready! Waiting for your buddy to confirm…"
              : 'Ready check cancelled'),
          backgroundColor: ready ? Colors.green : Colors.grey,
        ),
      );
      loadData();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $err'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _startTogether(String workoutId) async {
    final err = await _workoutService.setBuddyReady(workoutId: workoutId);
    if (!mounted) return;
    if (err == null) {
      HapticFeedback.heavyImpact();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Workout started — timers are live! 💪'),
          backgroundColor: Colors.green,
        ),
      );
      loadData();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $err'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _joinWorkout(String workoutId) async {
    final result = await _workoutService.creatorJoinWorkout(workoutId);
    if (!mounted) return;
    if (result['success'] == true) {
      HapticFeedback.heavyImpact();
      loadData();
      final completed = await WorkoutCheckInSheet.show(
        context,
        workoutType: result['workoutType'] ?? 'Workout',
        workoutEmoji: result['emoji'] ?? '💪',
        plannedDuration: result['remainingMinutes'] ?? 5,
        onCheckInComplete: () async {
          await _completeWorkout(workoutId);
          return true;
        },
      );
      if (completed == true) loadData();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result['error'] ?? 'Could not join'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _acceptInvitation(String workoutId) async {
    final success = await _workoutService.acceptWorkoutInvitation(workoutId);
    if (success) {
      if (!mounted) return; // ✅ CHECK MOUNTED
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Workout invitation accepted!'),
          backgroundColor: Colors.green,
        ),
      );
      loadData();
    }
  }

  Future<void> _declineInvitation(String workoutId) async {
    final success = await _workoutService.declineWorkoutInvitation(workoutId);
    if (success) {
      if (!mounted) return; // ✅ CHECK MOUNTED
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Workout invitation declined'),
          backgroundColor: Colors.grey,
        ),
      );
      loadData();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        // Inherits transparent bg + foreground from appBarTheme
        title: const Text(
          'Workout Schedule',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showCreateWorkoutDialog,
        icon: const Icon(Icons.add),
        label: const Text('New Workout'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: loadData,
              child: _buildWorkoutList(),
            ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.calendar_today,
              size: 64,
              color: AppColors.of(context).subtleText,
            ),
            const SizedBox(height: 16),
            Text(
              'No workouts scheduled',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Tap the + button to schedule your first workout',
              style: TextStyle(
                fontSize: 14,
                color: AppColors.of(context).subtleText,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWorkoutList() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // ✅ NEW: Redesigned invites card
        WorkoutInvitesCardRedesigned(
          onInviteAction: () {
            debugLog('📋 Schedule page: Invite action triggered, reloading data...');
            loadData();
          },
        ),
        const SizedBox(height: 16),

      if (_upcomingWorkouts.isEmpty)
        _buildEmptyWorkoutsCard()  // New method we'll create
      else
        
        // YOUR EXISTING WORKOUTS - Now using .map instead of ListView.builder
        ..._upcomingWorkouts.map((workout) {
          final creator = workout['creator'];
          final buddy = workout['buddy'];
          final currentUserId = Supabase.instance.client.auth.currentUser?.id;
          final isCreator = workout['user_id'] == currentUserId;
          final isBuddy = workout['buddy_id'] == currentUserId;
          final buddyStatus = workout['buddy_status'];
          final workoutStatus = workout['status'];

          // Get partner name
          String partnerName = 'Solo';
          if (buddy != null && isCreator) {
            partnerName = buddy['display_name'] ?? 'Unknown';
          } else if (creator != null && isBuddy) {
            partnerName = creator['display_name'] ?? 'Unknown';
          }

          return WorkoutCard(
            key: ValueKey(workout['id']),
            workout: workout,
            partnerName: partnerName,
            isCreator: isCreator,
            isBuddy: isBuddy,
            buddyStatus: buddyStatus,
            workoutStatus: workoutStatus,
            onStart: () => _startWorkout(workout['id']),
            onComplete: () => _completeWorkout(workout['id']),
            onOpenTimer: () => _completeWorkout(workout['id']),
            onCancel: () => _cancelWorkout(workout['id']),
            onAccept: () => _acceptInvitation(workout['id']),
            onDecline: () => _declineInvitation(workout['id']),
            onJoin: () => _joinWorkout(workout['id']),
            onReady: () => _setReady(workout['id'], true),
            onCancelReady: () => _setReady(workout['id'], false),
            onStartTogether: () => _startTogether(workout['id']),
          );
        }).toList(),
        CompletedWorkoutsSection(refreshTrigger: _completedRefreshTrigger),
      ],
    );
  }

  Color _getWorkoutColor(String? type) {
    switch (type?.toLowerCase()) {
      case 'cardio':
        return Colors.red[700]!;
      case 'strength':
      case 'weights':
        return Colors.blue[700]!;
      case 'legs':
      case 'leg day':
      case 'lower body':
        return Colors.orange[700]!;
      case 'upper body':
        return Colors.purple[700]!;
      case 'full body':
        return Colors.indigo[700]!;
      case 'hiit':
        return Colors.deepOrange[700]!;
      case 'yoga':
        return Colors.teal[700]!;
      default:
        return Colors.green[700]!;
    }
  }

  IconData _getWorkoutIcon(String? type) {
    switch (type?.toLowerCase()) {
      case 'cardio':
        return Icons.directions_run;
      case 'strength':
      case 'weights':
        return Icons.fitness_center;
      case 'upper body':
        return Icons.accessibility_new;
      case 'lower body':
      case 'legs':
      case 'leg day':
        return Icons.directions_walk;
      case 'full body':
        return Icons.sports_gymnastics;
      case 'hiit':
        return Icons.flash_on;
      case 'yoga':
        return Icons.self_improvement;
      default:
        return Icons.sports;
    }
  }

  String _getWorkoutStatusText(String? status) {
    switch (status?.toLowerCase()) {
      case 'scheduled':
        return 'Scheduled';
      case 'in_progress':
        return 'In Progress';
      case 'completed':
        return 'Completed';
      case 'cancelled':
        return 'Cancelled';
      default:
        return 'Unknown';
    }
  }

  IconData _getWorkoutStatusIcon(String? status) {
    switch (status?.toLowerCase()) {
      case 'scheduled':
        return Icons.schedule;
      case 'in_progress':
        return Icons.play_circle;
      case 'completed':
        return Icons.check_circle;
      case 'cancelled':
        return Icons.cancel;
      default:
        return Icons.help_outline;
    }
  }

  Color _getWorkoutStatusColor(String? status) {
    switch (status?.toLowerCase()) {
      case 'scheduled':
        return Colors.blue[700]!;
      case 'in_progress':
        return Colors.orange[700]!;
      case 'completed':
        return Colors.green[700]!;
      case 'cancelled':
        return Colors.red[700]!;
      default:
        return Colors.grey[700]!;
    }
  }

  Widget _buildEmptyWorkoutsCard() {
    final appColors = AppColors.of(context);
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          children: [
            Icon(Icons.calendar_today, size: 64, color: appColors.subtleText),
            const SizedBox(height: 16),
            Text(
              'No scheduled workouts',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Tap + to schedule a workout',
              style: TextStyle(fontSize: 14, color: appColors.subtleText),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusBadge(String? status) {
    final statusText = _getWorkoutStatusText(status);
    final statusIcon = _getWorkoutStatusIcon(status);
    final statusColor = _getWorkoutStatusColor(status);
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: statusColor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: statusColor.withOpacity(0.3),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            statusIcon,
            size: 14,
            color: statusColor,
          ),
          const SizedBox(width: 6),
          Text(
            statusText,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: statusColor,
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(String? dateStr) {
    if (dateStr == null) return 'Unknown';
    try {
      final date = DateTime.parse(dateStr);
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final workoutDate = DateTime(date.year, date.month, date.day);
      
      if (workoutDate == today) return 'Today';
      if (workoutDate == today.add(const Duration(days: 1))) return 'Tomorrow';
      
      final days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
      return '${days[date.weekday - 1]}, ${date.month}/${date.day}';
    } catch (e) {
      return dateStr;
    }
  }

  String _formatDuration(int? minutes) {
    if (minutes == null) return '';
    final hours = minutes ~/ 60;
    final mins = minutes % 60;
    if (hours > 0) {
      return mins > 0 ? '${hours}h ${mins}m' : '${hours}h';
    }
    return '${mins}m';
  }

  String _timeAgo(String? timestamp) {
    if (timestamp == null) return '';
    try {
      final time = DateTime.parse(timestamp);
      final diff = DateTime.now().difference(time);
      if (diff.inMinutes < 60) {
        return '${diff.inMinutes}m ago';
      } else {
        return '${diff.inHours}h ago';
      }
    } catch (e) {
      return '';
    }
  }

  Widget _buildEnhancedStatusBadge(String? status) {
    Color bgColor;
    Color textColor;
    IconData icon;
    String label;
    
    switch (status?.toLowerCase()) {
      case 'in_progress':
        bgColor = Colors.orange[100]!;
        textColor = Colors.orange[800]!;
        icon = Icons.play_circle;
        label = 'In Progress';
        break;
      case 'completed':
        bgColor = Colors.green[100]!;
        textColor = Colors.green[800]!;
        icon = Icons.check_circle;
        label = 'Completed';
        break;
      case 'cancelled':
        bgColor = Colors.red[100]!;
        textColor = Colors.red[800]!;
        icon = Icons.cancel;
        label = 'Cancelled';
        break;
      default: // scheduled
        bgColor = Colors.blue[100]!;
        textColor = Colors.blue[800]!;
        icon = Icons.schedule;
        label = 'Scheduled';
    }
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: textColor),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: textColor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoChip({
    required IconData icon,
    required String label,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}


// Profile Page
class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}
 
class _ProfilePageState extends State<ProfilePage>
    with TickerProviderStateMixin {
  Map<String, dynamic>? _profile;
  List<TeamStreak> _allStreaks = [];
  StreakSortMode _streakSortMode = StreakSortMode.highestCurrent;
  /// Mirrors the dashboard's list so both entry points agree.
  List<TeamStreak> get _listStreaks => sortStreaks(_allStreaks, _streakSortMode);
  /// Total sortable streaks (friends only), independent of sort/filter mode.
  int get _streakCount => _allStreaks.where((s) => !s.isCoachMaxTeam).length;
  LevelInfo? _levelInfo;
  int _totalWorkouts = 0;
  int _buddyCount = 0;
  bool _isLoading = true;

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
    _loadAll();
  }

  @override
  void dispose() {
    _fadeController.dispose();
    super.dispose();
  }
 
  // ── data loading ──────────────────────────────────────────────
  Future<void> _loadAll() async {
    try {
      final uid = Supabase.instance.client.auth.currentUser?.id;
      if (uid == null) return;

      final profileFuture = Supabase.instance.client
          .from('user_profiles')
          .select('avatar_id, display_name, created_at, xp, level, preferred_streak_sort')
          .eq('id', uid)
          .single();

      final streaksFuture = TeamStreakService().getAllUserStreaks();
      final levelFuture = LevelService().getLevelInfo();
      final workoutsFuture = Supabase.instance.client
          .from('workouts')
          .select('id')
          .or('user_id.eq.$uid,buddy_id.eq.$uid')
          .eq('status', 'completed');
      final friendsFuture = FriendService().getFriends();

      final profile  = await profileFuture;
      final streaks  = await streaksFuture;
      final level    = await levelFuture;
      final workouts = await workoutsFuture;
      final friends  = await friendsFuture;

      if (!mounted) return;

      setState(() {
        _profile       = profile as Map<String, dynamic>;
        _allStreaks     = streaks;
        _streakSortMode = StreakSortMode.values.firstWhere(
          (e) => e.name == profile['preferred_streak_sort'],
          orElse: () => StreakSortMode.highestCurrent,
        );
        _levelInfo     = level;
        _totalWorkouts = (workouts as List).length;
        _buddyCount    = friends.length;
        _isLoading     = false;
      });

      await Future.delayed(const Duration(milliseconds: 50));
      if (mounted) _fadeController.forward();
    } catch (e) {
      if (kDebugMode) debugLog('❌ ProfilePage._loadAll: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _formatYear(String? dateStr) {
    if (dateStr == null) return '2025';
    try { return '${DateTime.parse(dateStr).year}'; } catch (_) { return '2025'; }
  }

  int get _bestStreak => _allStreaks.isEmpty
      ? 0
      : _allStreaks.map((s) => s.bestStreak).reduce((a, b) => a > b ? a : b);

  String _avatarEmoji(String? id) {
    const map = {
      'lion': '🦁', 'wolf': '🐺', 'bear': '🐻',
      'eagle': '🦅', 'shark': '🦈', 'gorilla': '🦍',
      'tiger': '🐯', 'buffalo': '🦬', 'robot': '🤖',
      'flexed': '💪', 'weightlifter': '🏋️', 'runner': '🏃',
    };
    return map[id] ?? '🦁';
  }

  List<Color> _levelGradient(int level) {
    if (level >= 91) return [const Color(0xFF7F77DD), const Color(0xFF534AB7)];
    if (level >= 76) return [const Color(0xFFD85A30), const Color(0xFF993C1D)];
    if (level >= 56) return [const Color(0xFFD4537E), const Color(0xFF993556)];
    if (level >= 46) return [const Color(0xFFEF9F27), const Color(0xFFBA7517)];
    if (level >= 26) return [const Color(0xFF1D9E75), const Color(0xFF0F6E56)];
    if (level >= 11) return [const Color(0xFF378ADD), const Color(0xFF185FA5)];
    return [const Color(0xFFFFB300), const Color(0xFFFF8F00)];
  }

  String _titleIcon(String title) {
    const map = {
      'Newcomer': '🌱', 'Beginner': '⚡', 'Rookie': '🔥',
      'Athlete': '💪', 'Warrior': '⚔️', 'Iron': '🛡️',
      'Beast': '🦁', 'Legend': '👑', 'Elite': '💎',
      'Champion': '🏆', 'Gym Pro': '🌟',
    };
    return map[title] ?? '⭐';
  }
 
  // ══════════════════════════════════════════════════════════════
  // BUILD
  // ══════════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    if (_isLoading) return _buildSkeleton();

    final appColors = AppColors.of(context);
    final profile  = _profile ?? {};
    final level    = _levelInfo?.level ?? 1;
    final title    = _levelInfo?.title ?? 'Newcomer';
    final avatarId = profile['avatar_id'] as String? ?? 'lion';
    final name     = profile['display_name'] as String? ?? 'User';
    final year     = _formatYear(profile['created_at'] as String?);

    return Scaffold(
      backgroundColor: appColors.sectionBackground,
      body: RefreshIndicator(
        onRefresh: () async {
          _fadeController.reset();
          await _loadAll();
        },
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.zero,
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
                      _buildStatsRow(),
                      const SizedBox(height: 22),
                      _sectionLabel('Activity'),
                      const SizedBox(height: 10),
                      _buildMenuCard([
                        _MenuItem(
                          emoji: '🔥',
                          color: appColors.sectionBackground,
                          label: 'All Streaks',
                          sub: '$_streakCount active streaks',
                          onTap: () => showDialog(
                            context: context,
                            builder: (_) => _AllStreaksDialog(streaks: _listStreaks),
                          ),
                        ),
                        _MenuItem(
                          emoji: '🏆',
                          color: appColors.sectionBackground,
                          label: 'Achievements',
                          sub: 'View all achievements',
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => achievements_page.AchievementsPage()),
                          ),
                        ),
                        _MenuItem(
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
                      _buildMenuCard([
                        _MenuItem(
                          emoji: '🔔',
                          color: appColors.sectionBackground,
                          label: 'Notifications',
                          sub: 'Manage alerts',
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => const NotificationSettingsPage()),
                          ),
                        ),
                        _MenuItem(
                          emoji: '🎨',
                          color: appColors.sectionBackground,
                          label: 'Appearance',
                          sub: 'Avatar & border',
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => Scaffold(
                                appBar: AppBar(
                                  // Inherits transparent bg + foreground from appBarTheme
                                  title: const Text('Choose Avatar'),
                                ),
                                body: AvatarPickerScreen(
                                  onComplete: () {
                                    Navigator.pop(context);
                                    _fadeController.reset();
                                    _loadAll();
                                  },
                                ),
                              ),
                            ),
                          ),
                        ),
                        _MenuItem(
                          emoji: '🌈',
                          color: appColors.sectionBackground,
                          label: 'Accent Theme',
                          sub: _accentThemeLabel(context),
                          onTap: () => _showAccentThemePicker(context),
                        ),
                        _MenuItem(
                          emoji: '❓',
                          color: appColors.sectionBackground,
                          label: 'Help & Support',
                          sub: 'FAQs & contact',
                          onTap: () {},
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

  void _showAccentThemePicker(BuildContext context) {
    final provider = context.read<AccentThemeProvider>();
    showModalBottomSheet(
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
              ? appColors.avatarRing.withOpacity(0.1)
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
                  color: Colors.white.withOpacity(0.06),
                ),
              ),
            ),
            Positioned(
              bottom: 20, left: -20,
              child: Container(
                width: 120, height: 120,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withOpacity(0.04),
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
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const NotificationSettingsPage()),
                        ),
                        child: Container(
                          width: 36, height: 36,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white.withOpacity(0.15),
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
                      Stack(
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
                                backgroundColor: Colors.white.withOpacity(0.2),
                                valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
                              ),
                            ),
                          ),
                          Container(
                            width: 86, height: 86,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.white.withOpacity(0.15),
                              border: Border.all(color: Colors.white.withOpacity(0.3), width: 2),
                            ),
                            child: Center(
                              child: Text(_avatarEmoji(avatarId), style: const TextStyle(fontSize: 46)),
                            ),
                          ),
                          Positioned(
                            bottom: -4, right: -4,
                            child: Container(
                              width: 30, height: 30,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: LinearGradient(
                                  colors: _levelGradient(level),
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                                border: Border.all(color: Colors.white, width: 2),
                                boxShadow: [
                                  BoxShadow(
                                    color: _levelGradient(level).last.withOpacity(0.5),
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
                              style: TextStyle(color: Colors.white.withOpacity(0.65), fontSize: 13),
                            ),
                            const SizedBox(height: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(20),
                                color: Colors.white.withOpacity(0.18),
                                border: Border.all(color: Colors.white.withOpacity(0.3)),
                              ),
                              child: Text(
                                '${_titleIcon(title)}  $title',
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
            color: accentPalette.statusInfo.withOpacity(0.1),
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
                          color: accentPalette.statusInfo.withOpacity(0.12),
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
  Widget _buildStatsRow() {
    return Row(
      children: [
        _buildStatCard('🔥', '$_bestStreak', 'Best streak'),
        const SizedBox(width: 10),
        _buildStatCard('💪', '$_totalWorkouts', 'Workouts'),
        const SizedBox(width: 10),
        _buildStatCard('👥', '$_buddyCount', 'Buddies'),
        const SizedBox(width: 10),
        _buildStatCard('⚡', '${_allStreaks.length}', 'Streaks'),
      ],
    );
  }

  Widget _buildStatCard(String emoji, String value, String label) {
    final appColors = AppColors.of(context);
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: appColors.cardBackground,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 12,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          children: [
            Text(emoji, style: const TextStyle(fontSize: 20)),
            const SizedBox(height: 4),
            Text(
              value,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(fontSize: 9, color: appColors.subtleText, fontWeight: FontWeight.w500),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
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

  Widget _buildMenuCard(List<_MenuItem> items) {
    final appColors = AppColors.of(context);
    return Container(
      decoration: BoxDecoration(
        color: appColors.cardBackground,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 12,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: items.asMap().entries.map((entry) {
          final i = entry.key;
          final item = entry.value;
          return Column(
            children: [
              InkWell(
                onTap: () {
                  HapticFeedback.selectionClick();
                  item.onTap();
                },
                borderRadius: BorderRadius.vertical(
                  top: i == 0 ? const Radius.circular(18) : Radius.zero,
                  bottom: i == items.length - 1 ? const Radius.circular(18) : Radius.zero,
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  child: Row(
                    children: [
                      Container(
                        width: 36, height: 36,
                        decoration: BoxDecoration(
                          color: item.color,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Center(
                          child: Text(item.emoji, style: const TextStyle(fontSize: 17)),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item.label,
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                color: Theme.of(context).colorScheme.onSurface,
                              ),
                            ),
                            if (item.sub != null) ...[
                              const SizedBox(height: 1),
                              Text(
                                item.sub!,
                                style: TextStyle(fontSize: 12, color: appColors.subtleText),
                              ),
                            ],
                          ],
                        ),
                      ),
                      Icon(Icons.chevron_right_rounded, color: appColors.subtleText, size: 20),
                    ],
                  ),
                ),
              ),
              if (i < items.length - 1)
                Divider(height: 1, indent: 66, color: appColors.divider),
            ],
          );
        }).toList(),
      ),
    );
  }
 
  // ══════════════════════════════════════════════════════════════
  // LOG OUT
  // ══════════════════════════════════════════════════════════════
  Widget _buildLogoutButton() {
    return GestureDetector(
      onTap: () async {
        HapticFeedback.mediumImpact();
        // Release this handset's FCM token before the session goes away —
        // removeToken() scopes its delete to auth.uid(), so it has to run
        // while the user is still signed in.
        await NotificationService().removeToken();
        await Supabase.instance.client.auth.signOut();
        if (!mounted) return;
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => LoginScreen()),
          (route) => false,
        );
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFFE53935).withOpacity(0.08),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE53935).withOpacity(0.3), width: 1.5),
        ),
        child: const Center(
          child: Text(
            'Log Out',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: Color(0xFFE53935),
            ),
          ),
        ),
      ),
    );
  }
 
  // ══════════════════════════════════════════════════════════════
  // SKELETON — shown while data loads
  // Shows a realistic shimmer layout matching the real page
  // ══════════════════════════════════════════════════════════════
   Widget _buildSkeleton() {
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
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _shimmerBox(60, 18, radius: 6),
                        _shimmerCircle(36),
                      ],
                    ),
                    const SizedBox(height: 24),
                    Row(
                      children: [
                        _shimmerCircle(86),
                        const SizedBox(width: 16),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _shimmerBox(120, 20, radius: 6),
                            const SizedBox(height: 8),
                            _shimmerBox(90, 14, radius: 6),
                            const SizedBox(height: 10),
                            _shimmerBox(100, 26, radius: 13),
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
                  _shimmerCard(height: 110),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(child: _shimmerCard(height: 90)),
                      const SizedBox(width: 10),
                      Expanded(child: _shimmerCard(height: 90)),
                      const SizedBox(width: 10),
                      Expanded(child: _shimmerCard(height: 90)),
                      const SizedBox(width: 10),
                      Expanded(child: _shimmerCard(height: 90)),
                    ],
                  ),
                  const SizedBox(height: 22),
                  _shimmerBox(70, 12, radius: 4),
                  const SizedBox(height: 10),
                  _shimmerCard(height: 160),
                  const SizedBox(height: 22),
                  _shimmerBox(70, 12, radius: 4),
                  const SizedBox(height: 10),
                  _shimmerCard(height: 160),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _shimmerBox(double width, double height, {double radius = 8}) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.3, end: 0.7),
      duration: const Duration(milliseconds: 900),
      curve: Curves.easeInOut,
      builder: (_, value, __) => Container(
        width: width, height: height,
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(value),
          borderRadius: BorderRadius.circular(radius),
        ),
      ),
    );
  }

  Widget _shimmerCircle(double size) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.3, end: 0.7),
      duration: const Duration(milliseconds: 900),
      curve: Curves.easeInOut,
      builder: (_, value, __) => Container(
        width: size, height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white.withOpacity(value),
        ),
      ),
    );
  }

  Widget _shimmerCard({required double height}) {
    final appColors = AppColors.of(context);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.6, end: 1.0),
      duration: const Duration(milliseconds: 900),
      curve: Curves.easeInOut,
      builder: (_, value, __) => Container(
        height: height,
        decoration: BoxDecoration(
          color: appColors.cardBackground.withOpacity(value),
          borderRadius: BorderRadius.circular(18),
        ),
      ),
    );
  }
}
 
// ── Simple data class for menu items ─────────────────────────────
class _MenuItem {
  final String emoji;
  final Color color;
  final String label;
  final String? sub;
  final VoidCallback onTap;

  const _MenuItem({
    required this.emoji,
    required this.color,
    required this.label,
    this.sub,
    required this.onTap,
  });
}

// Helper Widgets
class _QuickActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _QuickActionButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Column(
        children: [
          CircleAvatar(
            radius: 30,
            backgroundColor: color.withOpacity(0.1),
            child: Icon(icon, color: color, size: 30),
          ),
          const SizedBox(height: 8),
          Text(label, style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurface)),
        ],
      ),
    );
  }
}


class _DayCircle extends StatelessWidget {
  final String day;
  final bool completed;

  const _DayCircle(this.day, this.completed);

  @override
  Widget build(BuildContext context) {
    return CircleAvatar(
      radius: 20,
      backgroundColor: completed ? Colors.green : AppColors.of(context).divider,
      child: Text(
        day,
        style: TextStyle(
          color: completed ? Colors.white : Theme.of(context).colorScheme.onSurface,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

class _WorkoutCard extends StatelessWidget {
  final String day;
  final String time;
  final String type;
  final String buddy;

  const _WorkoutCard({
    required this.day,
    required this.time,
    required this.type,
    required this.buddy,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: Colors.blue,
          child: const Icon(Icons.fitness_center, color: Colors.white),
        ),
        title: Text('$day • $time'),
        subtitle: Text('$type • with $buddy'),
        trailing: const Icon(Icons.arrow_forward_ios),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;

  const _StatCard(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
        Text(
          label,
          style: TextStyle(color: AppColors.of(context).subtleText),
        ),
      ],
    );
  }
}

class _QuickTip extends StatelessWidget {
  final IconData icon;
  final String text;

  const _QuickTip({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, size: 20, color: AppColors.of(context).subtleText),
        const SizedBox(height: 4),
        Text(
          text,
          style: TextStyle(
            fontSize: 10,
            color: AppColors.of(context).subtleText,
          ),
        ),
      ],
    );
  }
}

class _BenefitRow extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color color;

  const _BenefitRow({
    required this.icon,
    required this.text,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: color, size: 24),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 14,
              color: Theme.of(context).colorScheme.onSurface,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// WEEKLY PLAN DIALOG — Editorial stepper redesign
// Returns breakDays (int) on confirm, null on cancel.
// ═══════════════════════════════════════════════════════════════
class _WeeklyPlanDialog extends StatefulWidget {
  final int initialWorkoutDays;
  const _WeeklyPlanDialog({required this.initialWorkoutDays});

  @override
  State<_WeeklyPlanDialog> createState() => _WeeklyPlanDialogState();
}

class _WeeklyPlanDialogState extends State<_WeeklyPlanDialog>
    with SingleTickerProviderStateMixin {
  late int _workoutDays;
  late AnimationController _numAnim;
  late Animation<double> _scaleAnim;

  static const int _min = 4;
  static const int _max = 7;

  @override
  void initState() {
    super.initState();
    _workoutDays = widget.initialWorkoutDays.clamp(_min, _max);
    _numAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 120),
    );
    _scaleAnim = Tween<double>(begin: 1.0, end: 1.18).animate(
      CurvedAnimation(parent: _numAnim, curve: Curves.easeOut),
    );
  }

  @override
  void dispose() {
    _numAnim.dispose();
    super.dispose();
  }

  void _step(int delta) {
    final next = (_workoutDays + delta).clamp(_min, _max);
    if (next == _workoutDays) return;
    setState(() => _workoutDays = next);
    _numAnim.forward(from: 0).then((_) => _numAnim.reverse());
  }

  double get _trackProgress =>
      (_workoutDays - _min) / (_max - _min);

  @override
  Widget build(BuildContext context) {
    final appColors = AppColors.of(context);
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final breakDays = 7 - _workoutDays;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
      child: Container(
        decoration: BoxDecoration(
          color: appColors.cardBackground,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: appColors.cardBorder, width: 0.5),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Header ──────────────────────────────────────────
            Container(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                      color: appColors.cardBorder, width: 0.5),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'THIS WEEK',
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.2,
                      color: const Color(0xFFF97316),
                    ),
                  ),
                  const SizedBox(height: 4),
                  RichText(
                    text: TextSpan(
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -1.5,
                        height: 0.9,
                        color: cs.onSurface,
                      ),
                      children: [
                        const TextSpan(text: 'WORKOUT\n'),
                        TextSpan(
                          text: 'PLAN',
                          style: TextStyle(
                            color: isDark
                                ? const Color(0xFF7C3AED)
                                : const Color(0xFF6D28D9),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // ── Body ─────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
              child: Column(
                children: [
                  // Big animated number
                  ScaleTransition(
                    scale: _scaleAnim,
                    child: Column(
                      children: [
                        Text(
                          '$_workoutDays',
                          style: const TextStyle(
                            fontSize: 72,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -4,
                            height: 1,
                            color: Color(0xFFF97316),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'workout day${_workoutDays == 1 ? '' : 's'}',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.3,
                            color: appColors.subtleText,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 20),

                  // Stepper row: − track +
                  Row(
                    children: [
                      _StepButton(
                        label: '−',
                        enabled: _workoutDays > _min,
                        onTap: () => _step(-1),
                        appColors: appColors,
                        cs: cs,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          children: [
                            // Gradient track
                            ClipRRect(
                              borderRadius: BorderRadius.circular(3),
                              child: SizedBox(
                                height: 5,
                                child: Stack(
                                  children: [
                                    Container(
                                        color: appColors.divider),
                                    FractionallySizedBox(
                                      widthFactor: _trackProgress,
                                      child: Container(
                                        decoration: const BoxDecoration(
                                          gradient: LinearGradient(
                                            colors: [
                                              Color(0xFFF97316),
                                              Color(0xFF7C3AED),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 6),
                            Row(
                              mainAxisAlignment:
                                  MainAxisAlignment.spaceBetween,
                              children: [
                                Text('4 days',
                                    style: TextStyle(
                                        fontSize: 10,
                                        color: appColors.subtleText)),
                                Text('7 days',
                                    style: TextStyle(
                                        fontSize: 10,
                                        color: appColors.subtleText)),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      _StepButton(
                        label: '+',
                        enabled: _workoutDays < _max,
                        onTap: () => _step(1),
                        appColors: appColors,
                        cs: cs,
                        accent: true,
                      ),
                    ],
                  ),

                  const SizedBox(height: 20),

                  // Break days info row
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF3B82F6).withOpacity(0.08),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color:
                              const Color(0xFF3B82F6).withOpacity(0.2),
                          width: 0.5),
                    ),
                    child: Row(
                      children: [
                        const Text('🌙',
                            style: TextStyle(fontSize: 18)),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            '$breakDays break day${breakDays == 1 ? '' : 's'}',
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF3B82F6),
                            ),
                          ),
                        ),
                        Text(
                          '$breakDays',
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -1,
                            color: const Color(0xFF3B82F6)
                                .withOpacity(0.35),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 12),

                  Text(
                    'Your streak stays safe on break days.',
                    style: TextStyle(
                      fontSize: 11,
                      color: appColors.subtleText,
                      height: 1.4,
                    ),
                    textAlign: TextAlign.center,
                  ),

                  const SizedBox(height: 20),
                ],
              ),
            ),

            // ── Actions ──────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: Container(
                        padding:
                            const EdgeInsets.symmetric(vertical: 14),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                              color: appColors.cardBorder, width: 0.5),
                        ),
                        child: Center(
                          child: Text(
                            'Cancel',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: appColors.subtleText,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: GestureDetector(
                      onTap: () => Navigator.pop(context, breakDays),
                      child: Container(
                        padding:
                            const EdgeInsets.symmetric(vertical: 14),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF97316),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Center(
                          child: Text(
                            'Set Plan',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                              letterSpacing: 0.2,
                            ),
                          ),
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
    );
  }
}

// ── Stepper button ──────────────────────────────────────────────
class _StepButton extends StatelessWidget {
  final String label;
  final bool enabled;
  final bool accent;
  final VoidCallback onTap;
  final AppColors appColors;
  final ColorScheme cs;

  const _StepButton({
    required this.label,
    required this.enabled,
    required this.onTap,
    required this.appColors,
    required this.cs,
    this.accent = false,
  });

  @override
  Widget build(BuildContext context) {
      final active = enabled && accent;
      return GestureDetector(
        onTap: enabled ? onTap : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: active
                ? const Color(0xFFF97316)
                : appColors.sectionBackground,
            shape: BoxShape.circle,
            border: Border.all(
              color: active
                  ? const Color(0xFFF97316)
                  : appColors.cardBorder,
              width: 0.5,
            ),
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                height: 1,
                color: !enabled
                    ? appColors.subtleText.withOpacity(0.4)
                    : active
                        ? Colors.white
                        : cs.onSurface,
              ),
            ),
          ),
        ),
      );
    }
}

// ── Tab swipe physics — rubber-band at edges ───────────────────────────────
// ── Tab swipe physics — deliberate one-page swipes ───────────────
class _TabScrollPhysics extends ScrollPhysics {
  const _TabScrollPhysics({super.parent});

  @override
  _TabScrollPhysics applyTo(ScrollPhysics? ancestor) {
    return _TabScrollPhysics(parent: buildParent(ancestor));
  }

  @override
  Simulation? createBallisticSimulation(
      ScrollMetrics position, double velocity) {
    final tolerance = toleranceFor(position);
    final page = position.pixels / position.viewportDimension;
    final currentPage = page.round();

    // Require a deliberate flick to move (default fling threshold is ~50)
    if (velocity.abs() < 500) {
      final target = currentPage * position.viewportDimension;
      return ScrollSpringSimulation(
        spring,
        position.pixels,
        target,
        velocity,
        tolerance: tolerance,
      );
    }

    // Move exactly 1 page in swipe direction
    final targetPage = (velocity < 0 ? currentPage + 1 : currentPage - 1)
        .clamp(0, (position.maxScrollExtent / position.viewportDimension).round());
    final target = targetPage * position.viewportDimension;

    return ScrollSpringSimulation(
      spring,
      position.pixels,
      target,
      velocity,
      tolerance: tolerance,
    );
  }

  @override
  bool get allowImplicitScrolling => false;
}

  // ── Custom nav bar ─────────────────────────────────────────────────────────

class _GymBuddyNavBar extends StatelessWidget {
    final int selectedIndex;
    final ValueChanged<int> onTabSelected;

    const _GymBuddyNavBar({
      required this.selectedIndex,
      required this.onTabSelected,
    });

    // Visual order → logical index mapping
    // Display: [Buddies, Schedule, 🔥Streaks, Shop, Profile]
    // Indices: [1,       2,        0,          3,    4      ]
    static const _visualToLogical = [1, 2, 0, 3, 4];

    @override
    Widget build(BuildContext context) {
      final c = AppColors.of(context);
      // Same clay language as the cards above it: raised slab, dual shadow,
      // rounded top so the bar reads as part of one surface system.
      final inactiveColor = c.inkMuted;
      final activeColor = c.readableForeground(c.claySurface);

      return Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [c.claySurfaceLight, c.claySurface],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
          boxShadow: c.clayShadow(),
        ),
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: 62,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Schedule (logical 0)
              _NavIcon(
                icon: Icons.calendar_today_outlined,
                activeIcon: Icons.calendar_today,
                isActive: selectedIndex == 0,
                color: selectedIndex == 0 ? activeColor : inactiveColor,
                semanticLabel: 'Schedule',
                onTap: () {
                  HapticFeedback.selectionClick();
                  onTabSelected(0);
                },
              ),
              // Buddies (logical 1)
              _NavIcon(
                icon: Icons.people_outline,
                activeIcon: Icons.people,
                isActive: selectedIndex == 1,
                color: selectedIndex == 1 ? activeColor : inactiveColor,
                semanticLabel: 'Buddies',
                onTap: () {
                  HapticFeedback.selectionClick();
                  onTabSelected(1);
                },
              ),
              // 🔥 Streaks — centre hero (logical 2)
              _FireNavButton(
                isActive: selectedIndex == 2,
                onTap: () {
                  HapticFeedback.mediumImpact();
                  onTabSelected(2);
                },
              ),
              // Shop (logical 3)
              _NavIcon(
                icon: Icons.shopping_bag_outlined,
                activeIcon: Icons.shopping_bag,
                isActive: selectedIndex == 3,
                color: selectedIndex == 3 ? activeColor : inactiveColor,
                semanticLabel: 'Shop',
                onTap: () {
                  HapticFeedback.selectionClick();
                  onTabSelected(3);
                },
              ),
              // Profile (logical 4)
              _NavIcon(
                icon: Icons.person_outline,
                activeIcon: Icons.person,
                isActive: selectedIndex == 4,
                color: selectedIndex == 4 ? activeColor : inactiveColor,
                semanticLabel: 'Profile',
                onTap: () {
                  HapticFeedback.selectionClick();
                  onTabSelected(4);
                },
              ),
              ],
            ),
          ),
        ),
      );
    }
  }

class _NavIcon extends StatelessWidget {

    final IconData icon;
    final IconData activeIcon;
    final bool isActive;
    final Color color;
    final String semanticLabel;
    final VoidCallback onTap;

    const _NavIcon({
      required this.icon,
      required this.activeIcon,
      required this.isActive,
      required this.color,
      required this.semanticLabel,
      required this.onTap,
    });

    @override
    Widget build(BuildContext context) {
      return Semantics(
        label: semanticLabel,
        button: true,
        child: GestureDetector(
          onTap: onTap,
          behavior: HitTestBehavior.opaque,
          child: SizedBox(
            width: 48,
            height: 48,
            child: Center(
              child: Icon(
                isActive ? activeIcon : icon,
                color: color,
                size: 26,
              ),
            ),
          ),
        ),
      );
    }
  }

class _FireNavButton extends StatelessWidget {

    final bool isActive;
    final VoidCallback onTap;

    const _FireNavButton({required this.isActive, required this.onTap});

    @override
    Widget build(BuildContext context) {
      final c = AppColors.of(context);
      return Semantics(
        label: 'Streaks',
        button: true,
        child: GestureDetector(
          onTap: onTap,
          child: Transform.translate(
            offset: const Offset(0, -10),
            child: Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                // Same action gradient as the Check In CTA, so the hero button
                // and the hero action read as one thing.
                gradient: LinearGradient(
                  colors: c.actionGradient,
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(18),
                boxShadow: c.clayShadow(inset: isActive),
              ),
              child: Center(
                child: Icon(Icons.local_fire_department,
                    color: c.readableForeground(c.streakOrange), size: 32),
              ),
            ),
          ),
        ),
      );
    }
  }