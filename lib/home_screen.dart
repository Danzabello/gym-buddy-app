import 'main.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'services/friend_service.dart';
import 'services/workout_service.dart';
import 'services/team_streak_service.dart';
import 'widgets/coach_max_widget.dart';
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
import 'widgets/buddy_profile_sheet.dart';
import 'services/nickname_service.dart';
import 'widgets/workout_card.dart';
import 'widgets/schedule_workout_sheet.dart';
import 'widgets/workout_checkin_sheet.dart';
import 'services/workout_history_service.dart';
import 'widgets/workout_selection_modal.dart';
import 'widgets/workout_join_checker.dart';







// import 'services/streak_service.dart'; Not using it anymore

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedIndex = 0;

  final GlobalKey<_DashboardPageState> _dashboardKey = GlobalKey<_DashboardPageState>();
  
  // Different pages for each tab
  late List<Widget> _pages;
  
  @override
  void initState() {
    super.initState();
    // Initialize pages with the dashboard key
    _pages = [
      DashboardPage(key: _dashboardKey),  // Add the key here
      const FriendsPageModern(),
      const SchedulePage(),
      const ProfilePage(),
    ];
  }

  void _onTabChanged(int index) {
    final previousIndex = _selectedIndex;
    
    setState(() {
      _selectedIndex = index;
    });
    
    // Refresh dashboard when returning from friends page
    if (index == 0 && previousIndex == 1) {
      _dashboardKey.currentState?._syncTeamCheckIns();
      _dashboardKey.currentState?._loadStreakData();
    }

    if (index == 2) {
      // Force entire page to rebuild, which will reload WorkoutInvitesCard
      setState(() {
        // Recreate the pages list to force rebuild
        _pages[2] = SchedulePage(key: ValueKey('schedule_${DateTime.now().millisecondsSinceEpoch}'));
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _pages[_selectedIndex],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: _onTabChanged,  // Use the new method
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.people_outline),
            selectedIcon: Icon(Icons.people),
            label: 'Buddies',
          ),
          NavigationDestination(
            icon: Icon(Icons.calendar_today_outlined),
            selectedIcon: Icon(Icons.calendar_today),
            label: 'Schedule',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: 'Profile',
          ),
        ],
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
}

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
    }
  }
}

class _DashboardPageState extends State<DashboardPage> with TickerProviderStateMixin {
  final SupabaseClient _supabase = Supabase.instance.client;
  final TeamStreakService _teamStreakService = TeamStreakService();
  final WorkoutService _workoutService = WorkoutService();
  final TeamSyncService _teamSyncService = TeamSyncService();
  final BreakDayService _breakDayService = BreakDayService();
  Map<String, bool> _streakCompletionStatus = {};
  Map<String, String> _nicknames = {};

  
  TeamStreak? _highestStreak;
  List<TeamStreak> _allStreaks = [];
  List<Map<String, dynamic>> _todaysWorkouts = [];
  bool _hasCheckedInToday = false;
  bool _isLoading = true;
  bool _isCheckingIn = false;

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


  @override
  void initState() {
    super.initState();
    
    // ✅ Set initial index ONCE
    _currentCarouselIndex = 1;
    
    // ✅ Create controller ONCE
    _carouselController = PageController(
      viewportFraction: 0.40,
      initialPage: 1,
    );
    
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
    Future.delayed(const Duration(minutes: 1), _updateCountdown);
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
    // Clean up stale workouts first
    await _workoutService.cleanupStaleWorkouts(); 
    await _workoutService.cleanupOrphanedSessions();

    // Check and reset any broken streaks FIRST
    await _teamStreakService.checkAndResetBrokenStreaks();

    // Check if user needs to set weekly plan
    await _checkWeeklyPlan();

    // Check for active workout session
  await _checkForActiveWorkout();
    
    // Then load streaks normally
    await _loadStreakData();
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
    super.dispose();
  }


  Widget _buildStreakCarousel() {
    if (_allStreaks.isEmpty) {
      return _buildNoStreaksCard();
    }

  // ✅ INFINITE CAROUSEL: Always shows exactly 3 slots that wrap around
  final displayItems = <dynamic>[null, null, null]; // 3 slots: [0, 1, 2]

  // Find Coach Max and friends
  final coachMaxStreak = _allStreaks.firstWhere(
    (s) => s.isCoachMaxTeam,
    orElse: () => _allStreaks.first,
  );

  // Get friends and sort them by selected mode
  final friendStreaks = _streakSortMode == StreakSortMode.custom
    ? _allStreaks.where((s) => !s.isCoachMaxTeam).toList()  // Just filter, don't sort
    : _sortStreaks(_allStreaks, _streakSortMode);

  if (_streakSortMode == StreakSortMode.favorites && friendStreaks.isEmpty) {
    return _buildEmptyFavoritesCard();
  }

  // ✅ BUILD CAROUSEL ITEMS (in display order)
  if (friendStreaks.isEmpty) {
    // NO FRIENDS: [Add] [Coach Max] [Add]
    displayItems[0] = null;
    displayItems[1] = coachMaxStreak;
    displayItems[2] = null;
    
  } else if (friendStreaks.length == 1) {
    // 1 FRIEND: Compare friend vs Coach Max for center
    final friend = friendStreaks[0];
    
    // For numeric modes, use > for comparison
    final friendValue = friend.currentStreak;
    final coachValue = coachMaxStreak.currentStreak;
    
    bool friendIsHigher;
    if (friendValue == coachValue) {
      // ✅ TIE! Use alphabetical as tiebreaker
      friendIsHigher = friend.teamName.toLowerCase().compareTo('coach max') < 0;
      print('🤝 TIE at $friendValue! Tiebreaker: ${friend.teamName} vs Coach Max → ${friendIsHigher ? "Friend wins" : "Coach Max wins"}');
    } else {
      friendIsHigher = friendValue > coachValue;
    }
    
    if (friendIsHigher) {
      displayItems[0] = null;
      displayItems[1] = friend;
      displayItems[2] = coachMaxStreak;
    } else {
      displayItems[0] = null;
      displayItems[1] = coachMaxStreak;
      displayItems[2] = friend;
    }
    
  } else {
    // 2+ FRIENDS: Use sorted list directly!
    
    // ✅ CUSTOM MODE: Use exact order, no comparison with Coach Max
    if (_streakSortMode == StreakSortMode.custom) {
      // Use the saved order exactly as provided
      displayItems[0] = friendStreaks[0];  // Left = first selection
      displayItems[1] = friendStreaks[1];  // Center = second selection
      displayItems[2] = friendStreaks[2];  // Right = third selection
      print('👤 CUSTOM: Using exact order from selection');
    } else {
      // ✅ OTHER MODES: Compare with Coach Max to find center
      bool friendIsHigher;
      final friendValue = friendStreaks[0].currentStreak;
      final coachValue = coachMaxStreak.currentStreak;

      if (friendValue == coachValue) {
        friendIsHigher = friendStreaks[0].teamName.toLowerCase().compareTo('coach max') < 0;
        print('🤝 TIE at $friendValue! Tiebreaker: ${friendStreaks[0].teamName} vs Coach Max → ${friendIsHigher ? "Friend wins" : "Coach Max wins"}');
      } else {
        friendIsHigher = friendValue > coachValue;
      }
      
      if (friendIsHigher) {
        // Friend #1 in center
        displayItems[0] = friendStreaks.length > 2 ? friendStreaks[2] : coachMaxStreak;
        displayItems[1] = friendStreaks[0];  // #1 friend
        displayItems[2] = friendStreaks.length > 1 ? friendStreaks[1] : coachMaxStreak;
      } else {
        // Coach Max #1 in center
        displayItems[0] = friendStreaks.length > 1 ? friendStreaks[1] : null;
        displayItems[1] = coachMaxStreak;
        displayItems[2] = friendStreaks[0];  // Top friend on right
      }
    }
  }

  // ✅ Debug output
  print('📊 DISPLAY ITEMS:');
  print('  [0] Left: ${displayItems[0] is TeamStreak ? (displayItems[0] as TeamStreak).teamName : 'Add Buddy'}');
  print('  [1] Center: ${displayItems[1] is TeamStreak ? (displayItems[1] as TeamStreak).teamName : 'Add Buddy'}');
  print('  [2] Right: ${displayItems[2] is TeamStreak ? (displayItems[2] as TeamStreak).teamName : 'Add Buddy'}');
  print('  Current index: $_currentCarouselIndex');
  print('  Showing: ${displayItems[_currentCarouselIndex] is TeamStreak ? (displayItems[_currentCarouselIndex] as TeamStreak).teamName : 'Add Buddy'}');

    // ✅ MERGED CARD: Carousel + Action Buttons in one!
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [Colors.white, Colors.blue[50]!],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          children: [
            // ✅ PERFECTLY CENTERED: Equal width on both sides
            Row(
              children: [
                // Left: Three-dot menu (fixed width)
                SizedBox(
                  width: 60,  // Fixed width for left side
                  child: GestureDetector(
                    onTap: _showSortBottomSheet,
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.grey[100],
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        Icons.more_vert,
                        size: 20,
                        color: Colors.grey[700],
                      ),
                    ),
                  ),
                ),
                
                // Center: Title (takes remaining space)
                Expanded(
                  child: Center(
                    child: GestureDetector(
                      onTap: _showAllStreaks,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.grey[100],
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'Your Active Streaks (${_allStreaks.length})',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: Colors.grey[700],
                              ),
                            ),
                            const SizedBox(width: 6),
                            Icon(
                              Icons.chevron_right,
                              size: 20,
                              color: Colors.grey[600],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                
                // Right: Check-in badge (fixed width)
                SizedBox(
                  width: 60,  // Same width as left side
                  child: displayItems[_currentCarouselIndex] != null
                      ? Align(
                          alignment: Alignment.centerRight,
                          child: _buildCompactCheckInBadge(
                            displayItems[_currentCarouselIndex] as TeamStreak,
                          ),
                        )
                      : const SizedBox.shrink(),
                ),
              ],
            ),
            
            const SizedBox(height: 24),
            
            // ✅ INFINITE CAROUSEL - Wraps around in a circle
            SizedBox(
              height: 200,
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
                    final newIndex = index % 3;
                    
                    // ✅ ONLY update index - preset stays locked
                    setState(() {
                      _currentCarouselIndex = newIndex;
                    });
                  },
                  itemCount: null,
                  itemBuilder: (context, index) {
                    final displayIndex = index % 3;
                    final item = displayItems[displayIndex];
                    final isFocused = displayIndex == _currentCarouselIndex;
                    
                    return AnimatedBuilder(
                      animation: _carouselController,
                      builder: (context, child) {
                        double scale = 1.0;

                        if (_carouselController.position.haveDimensions && 
                            _carouselEntranceAnimation.value >= 1.0) {
                          final page = _carouselController.page ?? index.toDouble();
                          final diff = (page - index).abs();
                          scale = (1 - (diff * 0.45)).clamp(0.75, 1.0);
                        } else if (displayIndex == 1) {
                          scale = 1.0;
                        } else {
                          scale = 0.75;
                        }
                        
                        return Transform.scale(
                          scale: scale,
                          child: Center(
                            child: GestureDetector(
                              onTap: () {
                                _carouselController.animateToPage(
                                  index,
                                  duration: const Duration(milliseconds: 300),
                                  curve: Curves.easeInOut,
                                );
                              },
                              child: item != null
                                  ? _buildCarouselAvatar(item as TeamStreak, isFocused)
                                  : _buildAddFriendPlaceholder(isFocused),
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ),
            
            const SizedBox(height: 16),
            
            // ✅ NAME & STREAK COUNT (simplified, no progress bar)
            Column(
              children: [
                Text(
                  _getDisplayName(displayItems[_currentCarouselIndex]),
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: displayItems[_currentCarouselIndex] != null 
                        ? Colors.black
                        : Colors.grey[600],
                  ),
                ),
                const SizedBox(height: 8),
                // Just show streak count - removed progress bar
                if (displayItems[_currentCarouselIndex] != null)
                  Text(
                    '${(displayItems[_currentCarouselIndex] as TeamStreak).currentStreak} Day Streak',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey[800],
                    ),
                  )
                else
                  Text(
                    '— Day Streak',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey[400],
                    ),
                  ),
              ],
            ),
            
            const SizedBox(height: 24),
            
            // ✅ MERGED: Action buttons now part of same card!
            Column(
              children: [
                // CHECK IN BUTTON
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _hasCheckedInToday || _isCheckingIn ? null : _checkIn,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _hasCheckedInToday 
                          ? Colors.green[600]
                          : Colors.orange[600],
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 18),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      elevation: 4,
                      disabledBackgroundColor: _hasCheckedInToday 
                          ? Colors.green[600]
                          : Colors.grey[400],
                    ),
                    child: _isCheckingIn
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(
                              strokeWidth: 3,
                              color: Colors.white,
                            ),
                          )
                        : Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                _hasCheckedInToday ? Icons.check_circle : Icons.local_fire_department,
                                size: 28,
                                color: Colors.white,
                              ),
                              const SizedBox(width: 12),
                              Text(
                                _hasCheckedInToday ? 'Checked In! ✓' : 'Check In',
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                  ),
                ),
                
                const SizedBox(height: 12),
                
                // TAKE A BREAK BUTTON
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: _hasCheckedInToday ? null : () => _showTakeBreakDialog(),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      side: BorderSide(
                        color: _hasCheckedInToday ? Colors.grey[300]! : Colors.blue[600]!,
                        width: 2,
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.bedtime,
                          size: 24,
                          color: _hasCheckedInToday ? Colors.grey[400] : Colors.blue[700],
                        ),
                        const SizedBox(width: 12),
                        Text(
                          _hasCheckedInToday ? 'Already Checked In' : 'Take a Break',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: _hasCheckedInToday ? Colors.grey[400] : Colors.blue[700],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
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
    final currentUserId = Supabase.instance.client.auth.currentUser?.id;
    final friendMember = streak.members.firstWhere(
      (m) => m.userId != currentUserId,
      orElse: () => streak.members.first,
    );
    
    // Check for nickname first!
    final nickname = _nicknames[friendMember.userId];
    if (nickname != null && nickname.isNotEmpty) {
      return nickname;  // Show nickname
    }
    
    return friendMember.displayName;  // Fall back to display name
  }

  Widget _buildAddFriendPlaceholder(bool isFocused) {
    return GestureDetector(
      onTap: () {
        // Navigate to Buddies tab
        HapticFeedback.selectionClick();
        final homeState = context.findAncestorStateOfType<_HomeScreenState>();
        if (homeState != null) {
          homeState.setState(() {
            homeState._selectedIndex = 1; // Switch to Buddies tab
          });
        }
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        width: isFocused ? 120 : 65,
        height: isFocused ? 120 : 65,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
            colors: [Colors.blue[50]!, Colors.purple[50]!],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          border: Border.all(
            color: isFocused ? Colors.blue[400]! : Colors.blue[200]!,
            width: isFocused ? 4 : 2,
          ),
          boxShadow: isFocused
              ? [
                  BoxShadow(
                    color: Colors.blue.withOpacity(0.3),
                    blurRadius: 20,
                    spreadRadius: 5,
                  ),
                ]
              : [],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.person_add_rounded,
              size: isFocused ? 40 : 25,
              color: Colors.blue[600],
            ),
            if (isFocused) ...[
              const SizedBox(height: 8),
              Text(
                'Add\nBuddy',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.blue[700],
                  height: 1.1,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // NEW METHOD 2: Build Add Friend Info (replaces streak info when placeholder is focused)
  Widget _buildAddFriendInfo() {
    return Column(
      children: [
        // Placeholder streak count
        Text(
          '— Day Streak',
          style: TextStyle(
            fontSize: 32,
            fontWeight: FontWeight.bold,
            color: Colors.grey[400],
          ),
        ),
        
        const SizedBox(height: 12),
        
        // Progress bar (empty)
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: LinearProgressIndicator(
            value: 0.0,
            minHeight: 8,
            backgroundColor: Colors.grey[300],
            valueColor: AlwaysStoppedAnimation<Color>(Colors.grey[400]!),
          ),
        ),
        
        const SizedBox(height: 12),
        
        // Call to action badge
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Colors.blue[100]!, Colors.purple[100]!],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(25),
            border: Border.all(color: Colors.blue[300]!, width: 2),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.touch_app_rounded, color: Colors.blue[700], size: 22),
              const SizedBox(width: 10),
              Text(
                'Tap to find friends!',
                style: TextStyle(
                  color: Colors.blue[700],
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ],
          ),
        ),
      ],
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

  Widget _buildSingleStreakView(TeamStreak streak) {
    return Center(
      child: _buildCarouselAvatar(streak, true),  // Always focused
    );
  }

  Widget _buildCarouselAvatar(TeamStreak streak, bool isFocused) {
    final size = isFocused ? 140.0 : 110.0;
    
    // Get the friend's info
    final currentUserId = Supabase.instance.client.auth.currentUser?.id;
    final friendMember = streak.isCoachMaxTeam
        ? null
        : streak.members.firstWhere(
            (m) => m.userId != currentUserId,
            orElse: () => streak.members.first,
          );
    
    return GestureDetector(
      onTap: isFocused && !streak.isCoachMaxTeam && friendMember != null
          ? () => _showBuddyProfile(streak, friendMember)
          : null,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: streak.isCoachMaxTeam
                    ? [Colors.blue[400]!, Colors.purple[400]!]
                    : streak.isCompleteToday
                        ? [Colors.green[400]!, Colors.teal[400]!]
                        : [Colors.orange[400]!, Colors.deepOrange[400]!],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              border: Border.all(color: Colors.white, width: 4),
              boxShadow: [
                BoxShadow(
                  color: streak.isCompleteToday 
                      ? Colors.green.withOpacity(0.4)
                      : Colors.orange.withOpacity(0.4),
                  blurRadius: 20,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: Center(
              child: streak.isCoachMaxTeam
                  ? Text(
                      '🤖',
                      style: TextStyle(fontSize: size * 0.5),
                    )
                  : ClipOval(
                      child: UserAvatar(
                        avatarId: friendMember?.avatarId ?? 'avatar_1',
                        size: size * 0.85,
                      ),
                    ),
            ),
          ),
          
          // ⭐ Favorite star button (only for non-Coach Max when focused)
          if (!streak.isCoachMaxTeam && isFocused)
            Positioned(
              top: -5,
              right: -5,
              child: GestureDetector(
                onTap: () => _toggleFavorite(streak),
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: streak.isFavorite ? Colors.orange[400] : Colors.white,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: streak.isFavorite ? Colors.orange[600]! : Colors.grey[300]!,
                      width: 2,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        blurRadius: 4,
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                  child: Icon(
                    streak.isFavorite ? Icons.star : Icons.star_border,
                    color: streak.isFavorite ? Colors.white : Colors.grey[600],
                    size: 20,
                  ),
                ),
              ),
            ),
          
          // Checkmark badge
          if (streak.isCompleteToday)
            Positioned(
              bottom: 0,
              right: 0,
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Colors.green,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 3),
                ),
                child: const Icon(
                  Icons.check,
                  color: Colors.white,
                  size: 20,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildCheckInButton() {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: _hasCheckedInToday || _isCheckingIn ? null : _checkIn,
        style: ElevatedButton.styleFrom(
          backgroundColor: _hasCheckedInToday 
              ? Colors.green[600]  // ← Green when checked in
              : Colors.orange[600],
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 20),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          elevation: 4,
          disabledBackgroundColor: _hasCheckedInToday 
              ? Colors.green[600]  // ← Stay green when disabled
              : Colors.grey[400],
        ),
        child: _isCheckingIn
            ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 3,
                  color: Colors.white,
                ),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    _hasCheckedInToday ? Icons.check_circle : Icons.local_fire_department,
                    size: 28,
                    color: Colors.white,  // ← Always white icon
                  ),
                  const SizedBox(width: 12),
                  Text(
                    _hasCheckedInToday ? 'Checked In! ✓' : 'Check In',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,  // ← Always white text
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildTakeBreakButton() {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton(
        onPressed: _hasCheckedInToday  // ✅ Disable if already checked in
            ? null 
            : () => _showTakeBreakDialog(),
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 18),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          side: BorderSide(
            color: _hasCheckedInToday ? Colors.grey[300]! : Colors.blue[600]!,
            width: 2,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.bedtime,
              size: 24,
              color: _hasCheckedInToday ? Colors.grey[400] : Colors.blue[700],
            ),
            const SizedBox(width: 12),
            Text(
              _hasCheckedInToday ? 'Already Checked In' : 'Take a Break',  // ✅ Change text
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: _hasCheckedInToday ? Colors.grey[400] : Colors.blue[700],
              ),
            ),
          ],
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

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day).toIso8601String().split('T')[0];

    // Check if already took break today
    final existingBreak = await Supabase.instance.client
        .from('break_day_usage')  // ✅ FIXED: Changed from 'break_days'
        .select()
        .eq('user_id', currentUserId)
        .eq('break_date', today)
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



    // Count breaks taken this week
    final startOfWeek = now.subtract(Duration(days: now.weekday - 1));
    final startOfWeekStr = DateTime(startOfWeek.year, startOfWeek.month, startOfWeek.day)
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
      // Take the break day
      await Supabase.instance.client.from('break_day_usage').insert({  // ✅ FIXED: Changed from 'break_days'
        'user_id': currentUserId,
        'break_date': today,
      });
      
      if (!mounted) return;
      
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
      
      _loadStreakData();
    }
  }

  Widget _buildStreakInfo(TeamStreak streak) {
    final checkedInCount = streak.todayCheckIns.length;
    final totalMembers = streak.members.length;
    
    // ✅ Get pre-calculated completion status
    final isComplete = _streakCompletionStatus[streak.id] ?? false;
    
    Color statusColor;
    String statusText;
    IconData statusIcon;
    
    if (isComplete) {
      statusColor = Colors.green;
      statusText = '✓ Streak Complete!';
      statusIcon = Icons.check_circle;
    } else if (checkedInCount == 0) {
      statusColor = Colors.orange;
      statusText = '⚠️ 0/$totalMembers Checked In';
      statusIcon = Icons.warning_amber_rounded;
    } else {
      statusColor = Colors.blue;
      statusText = '⏳ $checkedInCount/$totalMembers Checked In';
      statusIcon = Icons.pending;
    }
    
    return Column(
      children: [
        // Streak count
        Text(
          '${streak.currentStreak} Day Streak',
          style: TextStyle(
            fontSize: 32,
            fontWeight: FontWeight.bold,
            color: Colors.grey[800],
          ),
        ),
        
        const SizedBox(height: 12),
        
        // Progress bar
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: LinearProgressIndicator(
            value: isComplete ? 1.0 : (checkedInCount / totalMembers),
            minHeight: 8,
            backgroundColor: Colors.grey[300],
            valueColor: AlwaysStoppedAnimation<Color>(statusColor),
          ),
        ),
        
        const SizedBox(height: 12),
        
        // Status badge
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: statusColor.withOpacity(0.1),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: statusColor, width: 2),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(statusIcon, color: statusColor, size: 20),
              const SizedBox(width: 8),
              Text(
                statusText,
                style: TextStyle(
                  color: statusColor,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCompactCheckInBadge(TeamStreak streak) {
    final checkedInCount = streak.todayCheckIns.length;
    final totalMembers = streak.members.length;
    final isComplete = _streakCompletionStatus[streak.id] ?? false;
    
    Color badgeColor;
    IconData badgeIcon;
    
    if (isComplete) {
      badgeColor = Colors.green;
      badgeIcon = Icons.check_circle;
    } else if (checkedInCount == 0) {
      badgeColor = Colors.orange;
      badgeIcon = Icons.warning_amber_rounded;
    } else {
      badgeColor = Colors.blue;
      badgeIcon = Icons.pending;
    }
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),  // ✅ Reduced padding
      decoration: BoxDecoration(
        color: badgeColor.withOpacity(0.15),
        borderRadius: BorderRadius.circular(16),  // ✅ Slightly smaller radius
        border: Border.all(color: badgeColor, width: 1.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(badgeIcon, color: badgeColor, size: 12),  // ✅ Smaller icon
          const SizedBox(width: 4),  // ✅ Less spacing
          Text(
            '$checkedInCount/$totalMembers',
            style: TextStyle(
              color: badgeColor,
              fontWeight: FontWeight.bold,
              fontSize: 11,  // ✅ Smaller font
            ),
          ),
        ],
      ),
    );
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
    
    Future.delayed(const Duration(minutes: 1), _updateCountdown);
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
    if (result != null && result.length == 3) {
      print('💾 Custom selection received: ${result.map((s) => s.teamName).join(", ")}');
      
      // ✅ 1. Update state
      setState(() {
        _customSelection = result;
        _streakSortMode = StreakSortMode.custom;
        _currentCarouselIndex = 1;  // Reset to center
      });
      
      // ✅ 2. Save to database (both mode AND order)
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId != null) {
        try {
          await Supabase.instance.client.from('user_profiles').update({
            'preferred_streak_sort': 'custom',
            'custom_streak_order': result.map((s) => s.teamId).toList(),
          }).eq('id', userId);
          
          print('💾 Saved custom mode with order: ${result.map((s) => s.teamId).join(", ")}');
          
          // ✅ 3. Show success message
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Row(
                  children: [
                    const Icon(Icons.check_circle, color: Colors.white),
                    const SizedBox(width: 12),
                    Text('Custom order saved: ${result[0].teamName}, ${result[1].teamName}, ${result[2].teamName}'),
                  ],
                ),
                backgroundColor: Colors.green[600],
                duration: const Duration(seconds: 3),
              ),
            );
          }
        } catch (e) {
          print('❌ Error saving custom order: $e');
        }
      }
      
      // ✅ 4. Reload data to apply the new order
      await _loadStreakData();
      
      // ✅ 5. Jump carousel to center after a brief delay
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_carouselController.hasClients && mounted) {
          _carouselController.jumpToPage(1000);
          print('🎯 Jumped to center after custom selection');
        }
      });
    } else {
      // User cancelled or didn't fill all 3 slots
      print('❌ Custom selection cancelled or incomplete');
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
    
    // Get today's date
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day).toIso8601String().split('T')[0];
    
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

  Future<void> _loadStreakData() async {
    setState(() {
      _isLoading = true;
    });

    // ✅ LOAD SAVED PREFERENCES (mode + custom order)
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId != null) {
      try {
        final prefs = await Supabase.instance.client
          .from('user_profiles')
          .select('preferred_streak_sort, custom_streak_order')  // ✅ Added custom_streak_order
          .eq('id', userId)
          .single();
        
        // Load sort mode preference
        if (prefs['preferred_streak_sort'] != null) {
          final savedMode = prefs['preferred_streak_sort'];
          // ✅ Validate and default to highestCurrent if invalid or empty
          if (savedMode == null || savedMode.toString().isEmpty) {
            _streakSortMode = StreakSortMode.highestCurrent;
          } else {
            _streakSortMode = StreakSortMode.values.firstWhere(
              (e) => e.name == savedMode,
              orElse: () => StreakSortMode.highestCurrent,
            );
          }
          print('📥 Loaded sort mode: ${_streakSortMode.displayName}');
        } else {
          // ✅ No preference saved - use default
          _streakSortMode = StreakSortMode.highestCurrent;
        }

        // ✅ NEW: Load custom streak order if in custom mode
        if (_streakSortMode == StreakSortMode.custom && prefs['custom_streak_order'] != null) {
          _customStreakOrder = List<String>.from(prefs['custom_streak_order']);
          print('📥 Loaded custom order: ${_customStreakOrder.length} team IDs');
        } else {
          _customStreakOrder = [];
        }
      } catch (e) {
        print('⚠️ Could not load preferences: $e');
        _customStreakOrder = [];
        // No problem, use defaults
      }
    }

    await _syncTeamCheckIns();

    final currentUserId = Supabase.instance.client.auth.currentUser?.id;
    final allStreaks = await _teamStreakService.getAllUserStreaks();
    final nicknames = await nicknameService.getAllNicknames();
    
    // 🔍 DEBUG: See what we're getting
    print('🔥 Raw streaks count: ${allStreaks.length}');
    for (var streak in allStreaks) {
      print('  - ${streak.teamName} (${streak.teamId}) - CoachMax: ${streak.isCoachMaxTeam}');
    }
    
    // ✅ BETTER FIX: Remove duplicate team IDs
    final Map<String, TeamStreak> uniqueStreaksMap = {};
    for (final streak in allStreaks) {
      uniqueStreaksMap[streak.teamId] = streak;
    }
    final uniqueStreaks = uniqueStreaksMap.values.toList();

    // ✅ NEW: Apply custom order if in custom mode and order exists
    if (_streakSortMode == StreakSortMode.custom && _customStreakOrder.isNotEmpty) {
      print('🎯 Applying custom order to ${uniqueStreaks.length} streaks');
      
      // Create a map for quick lookup
      final streakMap = {for (var s in uniqueStreaks) s.teamId: s};
      
      // Build ordered list based on saved order
      final orderedStreaks = <TeamStreak>[];
      for (final teamId in _customStreakOrder) {
        if (streakMap.containsKey(teamId)) {
          orderedStreaks.add(streakMap[teamId]!);
          streakMap.remove(teamId);  // Remove so we don't duplicate
        }
      }
      
      // Add any remaining streaks that weren't in the custom order (new friends)
      orderedStreaks.addAll(streakMap.values);
      
      // Replace uniqueStreaks with the ordered version
      uniqueStreaks.clear();
      uniqueStreaks.addAll(orderedStreaks);
      
      print('✅ Custom order applied: ${orderedStreaks.length} streaks ordered');
    }

    final completionStatus = <String, bool>{};
    for (var streak in uniqueStreaks) {
      completionStatus[streak.id] = await _isStreakCompleteToday(streak);
    }
    
    final highestStreak = await _teamStreakService.getHighestStreak();
    final hasCheckedIn = await _teamStreakService.hasCheckedInToday();
    final todaysWorkouts = await _workoutService.getTodaysWorkouts();
    
    print('✅ After deduplication: ${uniqueStreaks.length} streaks');
    
    final friendService = FriendService();
    final pendingFriends = await friendService.getPendingRequests();
    final pendingWorkouts = todaysWorkouts.where((w) => 
      w['buddy_id'] == currentUserId && w['buddy_status'] == 'pending'
    ).length;

    final friends = await friendService.getFriends();
    final allWorkouts = await _workoutService.getAllWorkouts();
    final completedWorkouts = allWorkouts.where((w) => w['status'] == 'completed').length;

    int achievements = 0;
    if (hasCheckedIn) achievements++;
    if ((highestStreak?.currentStreak ?? 0) >= 7) achievements++;
    if ((highestStreak?.currentStreak ?? 0) >= 30) achievements++;
    if (friends.length >= 3) achievements++;

    if (!mounted) return;

    setState(() {
      _allStreaks = uniqueStreaks;  // ✅ Use deduplicated (and optionally ordered) list
      _nicknames = nicknames;
      _streakCompletionStatus = completionStatus;
      _highestStreak = highestStreak;
      _hasCheckedInToday = hasCheckedIn;
      _todaysWorkouts = todaysWorkouts;
      _pendingRequests = pendingFriends.length + pendingWorkouts;

      _totalWorkouts = completedWorkouts;
      _buddyCount = friends.length;
      _achievementCount = achievements;

      _isLoading = false;
    });

    if (_allStreaks.isNotEmpty && mounted) {
      // ✅ Just ensure index is set to center (no jump needed on initial load)
      _currentCarouselIndex = 1;
    }

    if (!_hasAnimatedEntrance && _allStreaks.isNotEmpty) {
      Future.delayed(const Duration(milliseconds: 100), () {
        if (mounted) {
          _carouselEntranceController.forward();
          _hasAnimatedEntrance = true;
        }
      });
    }
  }

  List<TeamStreak> _sortStreaks(List<TeamStreak> streaks, StreakSortMode mode) {
    print('🔄 SORT: Mode = ${mode.displayName}');
    print('🔄 SORT: Input streaks count = ${streaks.length}');
    
    // Filter out Coach Max
    final friendStreaks = streaks.where((s) => !s.isCoachMaxTeam).toList();
    print('🔄 SORT: After filtering Coach Max = ${friendStreaks.length}');
    
    // Sort based on mode
    switch (mode) {
      case StreakSortMode.highestCurrent:
        friendStreaks.sort((a, b) => b.currentStreak.compareTo(a.currentStreak));
        print('⚡ SORT: Highest Current - Order: ${friendStreaks.map((s) => '${s.teamName}(${s.currentStreak})').join(', ')}');
        break;
        
      case StreakSortMode.mostWorkouts:
        friendStreaks.sort((a, b) => b.totalWorkouts.compareTo(a.totalWorkouts)); 
        print('💪 SORT: Most Workouts - Order: ${friendStreaks.map((s) => '${s.teamName}(${s.totalWorkouts})').join(', ')}');
        break;
        
      case StreakSortMode.bestAllTime:
        friendStreaks.sort((a, b) => b.bestStreak.compareTo(a.bestStreak));  // ✅ Use real data!
        print('🏆 SORT: Best All-Time - Order: ${friendStreaks.map((s) => '${s.teamName}(${s.bestStreak})').join(', ')}');
        break;
        
      case StreakSortMode.mostRecent:
        friendStreaks.sort((a, b) {
          if (a.lastInteractionAt == null) return 1;  // ✅ Use real timestamps!
          if (b.lastInteractionAt == null) return -1;
          return b.lastInteractionAt!.compareTo(a.lastInteractionAt!);  // Most recent first
        });
        print('🕐 SORT: Most Recent - Order: ${friendStreaks.map((s) => '${s.teamName}(${s.lastInteractionAt})').join(', ')}');
        break;
        
      case StreakSortMode.favorites:
        // ✨ Filter to only favorites
        final favorites = friendStreaks.where((s) => s.isFavorite).toList();
        favorites.sort((a, b) => b.currentStreak.compareTo(a.currentStreak));
        print('⭐ SORT: Favorites - Found ${favorites.length} favorite(s)');
        return favorites; // ✅ Return empty list if no favorites
        
      case StreakSortMode.custom:
        // Don't need any code here for now
        break;
    }
    
    print('✅ SORT: Returning ${friendStreaks.length} sorted streaks');
    return friendStreaks;
  }

  Future<void> _checkWeeklyPlan() async {
    final needsPlan = await _breakDayService.needsToSetWeeklyPlan();
    
    if (needsPlan) {
      _showWeeklyPlanDialog();
    }
  }

  Future<void> _showWeeklyPlanDialog() async {
    int selectedWorkoutDays = 5; // Default to 5 workout days
    
    final result = await showDialog<int>(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          final breakDays = 7 - selectedWorkoutDays;
          
          return AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade100,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.calendar_today,
                    color: Colors.orange,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Weekly Workout Plan',
                    style: TextStyle(fontSize: 20),
                  ),
                ),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'How many days will you work out this week?',
                  style: TextStyle(fontSize: 16),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),
                
                // Workout Days Selector
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.orange.shade200, width: 2),
                  ),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.fitness_center, color: Colors.orange, size: 28),
                          const SizedBox(width: 8),
                          Text(
                            '$selectedWorkoutDays',
                            style: TextStyle(
                              fontSize: 48,
                              fontWeight: FontWeight.bold,
                              color: Colors.orange.shade700,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'workout day${selectedWorkoutDays == 1 ? '' : 's'}',
                            style: TextStyle(
                              fontSize: 16,
                              color: Colors.orange.shade700,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      
                      // Slider
                      Slider(
                        value: selectedWorkoutDays.toDouble(),
                        min: 4,
                        max: 7,
                        divisions: 3,
                        activeColor: Colors.orange,
                        inactiveColor: Colors.orange.shade200,
                        onChanged: (value) {
                          setDialogState(() {
                            selectedWorkoutDays = value.toInt();
                          });
                        },
                      ),
                      
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('4 days', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                          Text('7 days', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                        ],
                      ),
                    ],
                  ),
                ),
                
                const SizedBox(height: 16),
                
                // Break Days Info
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.blue.shade200, width: 2),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.bedtime, color: Colors.blue, size: 24),
                      const SizedBox(width: 8),
                      Text(
                        '$breakDays break day${breakDays == 1 ? '' : 's'}',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: Colors.blue.shade700,
                        ),
                      ),
                    ],
                  ),
                ),
                
                const SizedBox(height: 16),
                
                const Text(
                  'You can take break days when you need rest. Your streak stays safe! 💪',
                  style: TextStyle(fontSize: 14, color: Colors.grey),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, breakDays),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  'Set Plan',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          );
        },
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

      // ✅ NEW: Check if there's an active workout session first
      final activeSession = await WorkoutCheckInSheet.getActiveSession();
      
      if (activeSession != null && activeSession['started_at'] != null) {
        // ✅ Active workout exists - go directly to timer with saved details
        if (!mounted) return;
        
        final completed = await WorkoutCheckInSheet.show(
          context,
          workoutType: activeSession['workout_type'] ?? 'Workout',
          workoutEmoji: activeSession['workout_emoji'] ?? '💪',
          plannedDuration: activeSession['planned_duration'] ?? 30,
          onCheckInComplete: () async {
            // Use the saved workout details for check-in
            final result = await _teamStreakService.checkInAllTeams(
              workoutName: activeSession['workout_type'] ?? 'Workout',
              workoutEmoji: activeSession['workout_emoji'] ?? '💪',
              durationMinutes: activeSession['planned_duration'] ?? 30,
            );

            if (result['success'] == true) {
              HapticFeedback.heavyImpact();

              if (!mounted) return;

              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Row(
                    children: [
                      const Icon(Icons.check_circle, color: Colors.white),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(result['message'] ?? 'Check-in successful!'),
                      ),
                    ],
                  ),
                  backgroundColor: Colors.green,
                  behavior: SnackBarBehavior.floating,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              );
            }
          },
        );

        if (completed == true && mounted) {
          _loadStreakData();
        }
        return; // ← Important: Don't show selection modal
      }

      // ✅ No active workout - show selection modal (existing flow)
      await _handleCheckIn();
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
      print('Error checking for active workout: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Scaffold(
          backgroundColor: const Color(0xFFF5F7FA),
          appBar: AppBar(
            elevation: 0,
            title: Text(
              _getGreeting(),
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            flexibleSpace: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.blue[700]!, Colors.purple[600]!],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
            ),
            actions: [
              Stack(
                children: [
                  IconButton(
                    icon: const Icon(Icons.notifications_outlined, color: Colors.white),
                    onPressed: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('No new notifications'),
                          duration: Duration(seconds: 1),
                        ),
                      );
                    },
                  ),
                  if (_pendingRequests > 0)
                    Positioned(
                      right: 8,
                      top: 8,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: const BoxDecoration(
                          color: Colors.red,
                          shape: BoxShape.circle,
                        ),
                        constraints: const BoxConstraints(
                          minWidth: 16,
                          minHeight: 16,
                        ),
                        child: Text(
                          '$_pendingRequests',
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
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: IconButton(
                  icon: const Icon(Icons.settings, color: Colors.white),
                  onPressed: () {
                    // Navigate to settings
                    final homeState = context.findAncestorStateOfType<_HomeScreenState>();
                    homeState?.setState(() {
                      homeState._selectedIndex = 3; // Profile page
                    });
                  },
                ),
              ),
            ],
          ),
          body: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : RefreshIndicator(
                  onRefresh: _loadStreakData,
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // NEW CAROUSEL SECTION
                        _buildStreakCarousel(),
                        
                        const SizedBox(height: 24),
                        
                        // QUICK ACTIONS
                        _buildQuickActionsSection(),
                        
                        const SizedBox(height: 20),
                      ],
                    ),
                  ),
                ),
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: ConfettiWidget(
            confettiController: _confettiController,
            blastDirection: 0,  // ← Shoots to the right
            emissionFrequency: 0.05,
            numberOfParticles: 30,
            maxBlastForce: 100,
            minBlastForce: 80,
            gravity: 0.3,
            colors: const [
              Colors.green,
              Colors.blue,
              Colors.pink,
              Colors.orange,
              Colors.purple,
              Colors.yellow,
            ],
          ),
        ),

        // ✅ RIGHT SIDE CONFETTI
        Align(
          alignment: Alignment.centerRight,
          child: ConfettiWidget(
            confettiController: _confettiControllerRight,
            blastDirection: 3.14,  // ← Shoots to the left
            emissionFrequency: 0.05,
            numberOfParticles: 30,
            maxBlastForce: 100,
            minBlastForce: 80,
            gravity: 0.3,
            colors: const [
              Colors.green,
              Colors.blue,
              Colors.pink,
              Colors.orange,
              Colors.purple,
              Colors.yellow,
            ],
          ),
        ),
      ],
    );
  }

  // REDESIGNED: Quick stats row
  Widget _buildQuickStatsRow() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [Colors.white, Colors.blue[50]!],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _buildQuickStat(
              icon: Icons.local_fire_department,
              value: '${_highestStreak?.currentStreak ?? 0}',
              label: 'Day Streak',
              color: Colors.orange[700]!,
            ),
            _buildVerticalDivider(),
            _buildQuickStat(
              icon: Icons.fitness_center,
              value: '$_totalWorkouts',
              label: 'Workouts',
              color: Colors.blue[700]!,
            ),
            _buildVerticalDivider(),
            _buildQuickStat(
              icon: Icons.people,
              value: '$_buddyCount',
              label: 'Buddies',
              color: Colors.green[700]!,
            ),
            _buildVerticalDivider(),
            _buildQuickStat(
              icon: Icons.emoji_events,
              value: '$_achievementCount',
              label: 'Badges',
              color: Colors.purple[700]!,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVerticalDivider() {
    return Container(
      height: 40,
      width: 1,
      color: Colors.grey[300],
    );
  }

  Widget _buildQuickStat({
    required IconData icon,
    required String value,
    required String label,
    required Color color,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color, size: 24),
        const SizedBox(height: 6),
        Text(
          value,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            color: Colors.grey[600],
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  // REDESIGNED: Main streak card with centered avatar
  Widget _buildMainStreakCard() {
    final currentStreak = _allStreaks[_currentStreakIndex];
    final isCoachMax = currentStreak.isCoachMaxTeam;
    
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: isCoachMax 
                ? [Colors.blue[50]!, Colors.purple[50]!]
                : [Colors.orange[50]!, Colors.red[50]!],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          children: [
            // Header with navigation arrows
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Left arrow
                if (_allStreaks.length > 1)
                  IconButton(
                    icon: Icon(
                      Icons.arrow_back_ios,
                      color: isCoachMax ? Colors.blue[700] : Colors.orange[700],
                    ),
                    onPressed: _currentStreakIndex > 0
                        ? () {
                            setState(() {
                              _currentStreakIndex--;
                            });
                            _pageController.animateToPage(
                              _currentStreakIndex,
                              duration: const Duration(milliseconds: 300),
                              curve: Curves.easeInOut,
                            );
                          }
                        : null,
                  )
                else
                  const SizedBox(width: 48),
                
                // Team badge
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: isCoachMax ? Colors.blue[100] : Colors.orange[100],
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        currentStreak.teamEmoji,
                        style: const TextStyle(fontSize: 16),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        currentStreak.teamName,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: isCoachMax ? Colors.blue[900] : Colors.orange[900],
                        ),
                      ),
                    ],
                  ),
                ),
                
                // Right arrow
                if (_allStreaks.length > 1)
                  IconButton(
                    icon: Icon(
                      Icons.arrow_forward_ios,
                      color: isCoachMax ? Colors.blue[700] : Colors.orange[700],
                    ),
                    onPressed: _currentStreakIndex < _allStreaks.length - 1
                        ? () {
                            setState(() {
                              _currentStreakIndex++;
                            });
                            _pageController.animateToPage(
                              _currentStreakIndex,
                              duration: const Duration(milliseconds: 300),
                              curve: Curves.easeInOut,
                            );
                          }
                        : null,
                  )
                else
                  const SizedBox(width: 48),
              ],
            ),
            
            const SizedBox(height: 20),
            
            // CENTERED AVATAR with progress ring
            Stack(
              alignment: Alignment.center,
              children: [
                // Progress ring
                SizedBox(
                  width: 140,
                  height: 140,
                  child: TweenAnimationBuilder<double>(
                    duration: const Duration(milliseconds: 1000),
                    curve: Curves.easeInOut,
                    tween: Tween<double>(
                      begin: 0.0,
                      end: currentStreak.currentStreak / _getNextMilestone(currentStreak.currentStreak),
                    ),
                    builder: (context, value, _) => CircularProgressIndicator(
                      value: value > 1.0 ? 1.0 : value,
                      strokeWidth: 10,
                      backgroundColor: Colors.grey[300],
                      valueColor: AlwaysStoppedAnimation<Color>(
                        isCoachMax ? Colors.blue[700]! : Colors.orange[700]!,
                      ),
                    ),
                  ),
                ),
                
                // Avatar in center
                Container(
                  width: 110,
                  height: 110,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: isCoachMax 
                          ? [Colors.blue[400]!, Colors.purple[400]!]
                          : [Colors.orange[400]!, Colors.red[400]!],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: (isCoachMax ? Colors.blue : Colors.orange).withOpacity(0.4),
                        blurRadius: 20,
                        spreadRadius: 5,
                      ),
                    ],
                  ),
                  child: Center(
                    child: Text(
                      isCoachMax ? '🤖' : '🔥',
                      style: const TextStyle(fontSize: 50),
                    ),
                  ),
                ),
              ],
            ),
            
            const SizedBox(height: 24),
            
            // Streak number
            Text(
              '${currentStreak.currentStreak} Days',
              style: TextStyle(
                fontSize: 36,
                fontWeight: FontWeight.bold,
                color: isCoachMax ? Colors.blue[900] : Colors.orange[900],
              ),
            ),
            
            const SizedBox(height: 4),
            
            Text(
              'Current Streak',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[600],
              ),
            ),
            
            const SizedBox(height: 8),
            
            // Best streak
            if (currentStreak.longestStreak > 0)
              Text(
                'Best: ${currentStreak.longestStreak} days',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[600],
                ),
              ),
            
            const SizedBox(height: 16),
            
            // Next milestone
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: isCoachMax ? Colors.blue[100] : Colors.orange[100],
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                'Next: ${_getMilestoneName(_getNextMilestone(currentStreak.currentStreak))} (${_getNextMilestone(currentStreak.currentStreak)} days)',
                style: TextStyle(
                  fontSize: 12,
                  color: isCoachMax ? Colors.blue[900] : Colors.orange[900],
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            
            const SizedBox(height: 24),

            BreakDaySection(
              onBreakTaken: () {
                // Refresh streaks when break status changes
                _loadStreakData();
              },
            ),
            
            // Check-in button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _hasCheckedInToday || _isCheckingIn ? null : _checkIn,
                icon: _isCheckingIn
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Icon(_hasCheckedInToday ? Icons.check_circle : Icons.fitness_center),
                label: Text(
                  _hasCheckedInToday ? 'Checked In Today! 🎉' : 'Check In Now',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _hasCheckedInToday ? Colors.green : (isCoachMax ? Colors.blue[700] : Colors.orange[700]),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 4,
                ),
              ),
            ),
            
            const SizedBox(height: 20),
            
            // Team progress
            if (currentStreak.members.length > 1) ...[
              const Divider(),
              const SizedBox(height: 12),
              _buildTeamCompletionBar(currentStreak),
              const SizedBox(height: 12),
            ],
            
            // Calendar heatmap
            const Divider(),
            const SizedBox(height: 12),
            _buildCalendarHeatMap(),
          ],
        ),
      ),
    );
  }

  // No streaks card
  Widget _buildNoStreaksCard() {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        padding: const EdgeInsets.all(40),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [Colors.grey[100]!, Colors.grey[200]!],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Center(
          child: Column(
            children: [
              Icon(
                Icons.local_fire_department,
                size: 64,
                color: Colors.grey[400],
              ),
              const SizedBox(height: 16),
              Text(
                'No active streaks yet',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey[700],
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Check in to start your streak!',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[600],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyFavoritesCard() {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [Colors.white, Colors.orange[50]!],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.star_border,
              size: 80,
              color: Colors.orange[300],
            ),
            const SizedBox(height: 16),
            Text(
              'No Favorites Yet!',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.grey[800],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Star your workout buddies to add them here.\nTap the ⭐ on their avatar when viewing them.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[600],
                height: 1.5,
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () {
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
              },
              icon: const Icon(Icons.arrow_back),
              label: const Text('View All Streaks'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange[600],
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Today's workout section
  Widget _buildTodaysWorkoutSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              "Today's Workouts",
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Color(0xFF2C3E50),
              ),
            ),
            TextButton(
              onPressed: () {
                final homeState = context.findAncestorStateOfType<_HomeScreenState>();
                homeState?.setState(() {
                  homeState._selectedIndex = 2;
                });
              },
              child: const Text('View All'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        
        // Show real workouts or create prompt
        if (_todaysWorkouts.isEmpty)
          _buildCreateWorkoutPromptDashboard()
        else
          ..._todaysWorkouts.map((workout) => _buildWorkoutCardDashboard(workout)).toList(),
      ],
    );
  }

  Widget _buildWorkoutCardDashboard(Map<String, dynamic> workout) {
    final creator = workout['creator'];
    final buddy = workout['buddy'];
    final currentUserId = Supabase.instance.client.auth.currentUser?.id;
    final isCreator = workout['user_id'] == currentUserId;
    final isBuddy = workout['buddy_id'] == currentUserId;
    final buddyStatus = workout['buddy_status'];
    
    String buddyName = 'Solo';
    Color buddyColor = Colors.grey[700]!;
    
    if (buddy != null && isCreator) {
      buddyName = buddy['display_name'] ?? 'Unknown';
      buddyColor = buddyStatus == 'accepted' ? Colors.green[700]! : Colors.orange[700]!;
    } else if (creator != null && isBuddy) {
      buddyName = creator['display_name'] ?? 'Unknown';
      buddyColor = Colors.blue[700]!;
    }
    
    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [Colors.white, Colors.blue[50]!],
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
          ),
          borderRadius: BorderRadius.circular(16),
        ),
        child: ListTile(
          contentPadding: const EdgeInsets.all(16),
          leading: Stack(
            children: [
              CircleAvatar(
                radius: 28,
                backgroundColor: _getWorkoutColorDash(workout['workout_type']).withOpacity(0.2),
                child: Icon(
                  _getWorkoutIcon(workout['workout_type']),  // ✅ NEW ICON!
                  color: _getWorkoutColorDash(workout['workout_type']),
                  size: 28,
                ),
              ),
              if (isBuddy && buddyStatus == 'pending')
                Positioned(
                  right: 0,
                  top: 0,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: const BoxDecoration(
                      color: Colors.orange,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.notification_important,
                      color: Colors.white,
                      size: 12,
                    ),
                  ),
                ),
            ],
          ),
          title: Row(
            children: [
              Expanded(
                child: Text(
                  workout['workout_type'] ?? 'Workout',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ),
              if (isBuddy && buddyStatus == 'pending')
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.orange,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text(
                    'INVITE',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
            ],
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 4),
              Row(
                children: [
                  Icon(Icons.schedule, size: 14, color: Colors.grey[600]),
                  const SizedBox(width: 4),
                  Text(
                    workout['workout_time'] ?? '',
                    style: TextStyle(color: Colors.grey[600]),
                  ),
                  const SizedBox(width: 12),
                  Icon(Icons.person, size: 14, color: buddyColor),
                  const SizedBox(width: 4),
                  Text(
                    buddyName,
                    style: TextStyle(
                      color: buddyColor,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              if (workout['planned_duration_minutes'] != null) ...[
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(Icons.timer, size: 14, color: Colors.grey[600]),
                    const SizedBox(width: 4),
                    Text(
                      _formatDurationDash(workout['planned_duration_minutes']),
                      style: TextStyle(color: Colors.grey[600], fontSize: 12),
                    ),
                  ],
                ),
              ],
            ],
          ),
          trailing: _buildWorkoutActionButtonDashboard(workout),
        ),
      ),
    );
  }

  Widget _buildWorkoutActionButtonDashboard(Map<String, dynamic> workout) {
    final currentUserId = Supabase.instance.client.auth.currentUser?.id;
    final isBuddy = workout['buddy_id'] == currentUserId;
    final buddyStatus = workout['buddy_status'];
    
    if (isBuddy && buddyStatus == 'pending') {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.check_circle, color: Colors.green, size: 20),
            onPressed: () {
              HapticFeedback.lightImpact();  // ✅ HAPTIC FEEDBACK!
              _acceptWorkoutInviteDash(workout['id']);
            },
            tooltip: 'Accept',
          ),
          IconButton(
            icon: const Icon(Icons.cancel, color: Colors.red, size: 20),
            onPressed: () {
              HapticFeedback.lightImpact();  // ✅ HAPTIC FEEDBACK!
              _declineWorkoutInviteDash(workout['id']);
            },
            tooltip: 'Decline',
          ),
        ],
      );
    }
    
    return ElevatedButton(
      onPressed: () {
        HapticFeedback.selectionClick();  // ✅ HAPTIC FEEDBACK!
        final homeState = context.findAncestorStateOfType<_HomeScreenState>();
        homeState?.setState(() {
          homeState._selectedIndex = 2;
        });
      },
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.blue[700],
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      ),
      child: const Text('View'),
    );
  }

  Widget _buildCreateWorkoutPromptDashboard() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        onTap: _showQuickCreateWorkoutDialog,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Colors.blue[50]!, Colors.purple[50]!],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            children: [
              Icon(
                Icons.add_circle_outline,
                size: 48,
                color: Colors.blue[700],
              ),
              const SizedBox(height: 12),
              Text(
                'No workouts scheduled today',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey[800],
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Create a workout with a friend!',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[600],
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: _showQuickCreateWorkoutDialog,
                icon: const Icon(Icons.add),
                label: const Text('Create Workout'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue[700],
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ],
          ),
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

  // Quick actions section
  Widget _buildQuickActionsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Quick Actions',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: Color(0xFF2C3E50),
          ),
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _buildQuickActionCard(
              icon: Icons.add_circle_outline,
              label: 'New Workout',
              color: Colors.green[700]!,
              onTap: () {
                final homeState = context.findAncestorStateOfType<_HomeScreenState>();
                homeState?.setState(() {
                  homeState._selectedIndex = 2;
                });
              },
            ),
            _buildQuickActionCard(
              icon: Icons.person_add,
              label: 'Find Buddy',
              color: Colors.blue[700]!,
              onTap: () {
                final homeState = context.findAncestorStateOfType<_HomeScreenState>();
                homeState?.setState(() {
                  homeState._selectedIndex = 1;
                });
              },
            ),
            _buildQuickActionCard(
              icon: Icons.history,
              label: 'All Streaks',
              color: Colors.purple[700]!,
              onTap: _showAllStreaks,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildQuickActionCard({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: Card(
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: InkWell(
          onTap: () {
            HapticFeedback.selectionClick();  // ✅ HAPTIC FEEDBACK!
            onTap();
          },
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, color: color, size: 28),
                ),
                const SizedBox(height: 12),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey[800],
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // Build team completion bar (shows who checked in)
  Widget _buildTeamCompletionBar(TeamStreak streak) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Team Progress',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[600],
                fontWeight: FontWeight.w500,
              ),
            ),
            Text(
              '${streak.todayCheckIns.length}/${streak.members.length} checked in',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[600],
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: LinearProgressIndicator(
            value: streak.completionPercentage,
            minHeight: 8,
            backgroundColor: Colors.grey[300],
            valueColor: AlwaysStoppedAnimation<Color>(
              streak.isCompleteToday ? Colors.green : Colors.orange,
            ),
          ),
        ),
        
        const SizedBox(height: 8),
        
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: streak.members.map((member) {
            final hasCheckedIn = streak.todayCheckIns.any(
              (checkIn) => checkIn.userId == member.userId
            );
            
            return Chip(
              avatar: CircleAvatar(
                backgroundColor: hasCheckedIn ? Colors.green : Colors.grey[400],
                child: Icon(
                  hasCheckedIn ? Icons.check : Icons.person,
                  size: 16,
                  color: Colors.white,
                ),
              ),
              label: Text(
                member.displayName,
                style: const TextStyle(fontSize: 12),
              ),
              backgroundColor: hasCheckedIn ? Colors.green[50] : Colors.grey[200],
            );
          }).toList(),
        ),
      ],
    );
  }

  void _showAllStreaks() {
    showDialog(
      context: context,
      builder: (context) => _AllStreaksDialog(streaks: _allStreaks),
    );
  }

  String _getGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) {
      return 'Good Morning! ☀️';
    } else if (hour < 17) {
      return 'Good Afternoon! 👋';
    } else if (hour < 21) {
      return 'Good Evening! 🌆';
    } else {
      return 'Good Night! 🌙';
    }
  }

  String _getCurrentDate() {
    final now = DateTime.now();
    final days = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
    final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    
    return '${days[now.weekday - 1]}, ${months[now.month - 1]} ${now.day}';
  }

  Widget _buildCalendarHeatMap() {
    final today = DateTime.now();
    final last7Days = List.generate(7, (index) {
      return today.subtract(Duration(days: 6 - index));
    });

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Last 7 Days',
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey[600],
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: last7Days.map((date) {
            final isCheckedIn = _isDateCheckedIn(date);
            final isToday = _isSameDay(date, today);
            
            return Column(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isCheckedIn 
                        ? Colors.green 
                        : (isToday ? Colors.orange[100] : Colors.grey[300]),
                    border: isToday 
                        ? Border.all(color: Colors.orange, width: 2)
                        : null,
                  ),
                  child: Center(
                    child: isCheckedIn
                        ? const Icon(
                            Icons.check,
                            color: Colors.white,
                            size: 18,
                          )
                        : Text(
                            '${date.day}',
                            style: TextStyle(
                              fontSize: 12,
                              color: isToday ? Colors.orange : Colors.grey[600],
                              fontWeight: isToday ? FontWeight.bold : FontWeight.normal,
                            ),
                          ),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _getDayInitial(date),
                  style: TextStyle(
                    fontSize: 10,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            );
          }).toList(),
        ),
      ],
    );
  }

  bool _isDateCheckedIn(DateTime date) {
    if (_highestStreak == null) return false;
    
    if (_isSameDay(date, DateTime.now())) {
      return _hasCheckedInToday;
    }
    
    final today = DateTime.now();
    final daysDiff = today.difference(date).inDays;
    
    if (daysDiff <= _highestStreak!.currentStreak && daysDiff >= 0) {
      return true;
    }
    
    return false;
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
      _confettiController.play();
      _confettiControllerRight.play();
      _showMilestoneDialog(currentStreak);
    }
  }

  void _showMilestoneDialog(int streak) {
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
    
    showDialog(
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

  int _getNextMilestone(int currentStreak) {
    if (currentStreak < 7) return 7;
    if (currentStreak < 30) return 30;
    if (currentStreak < 100) return 100;
    return currentStreak + 100;
  }

  String _getMilestoneName(int milestone) {
    switch (milestone) {
      case 7:
        return '🔥 On Fire';
      case 30:
        return '💎 Diamond';
      case 100:
        return '👑 Legend';
      default:
        return '⚡ Unstoppable';
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

  Widget _buildEmptyWorkoutsState() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [Colors.blue[50]!, Colors.purple[50]!],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Animated Icon
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0.8, end: 1.0),
              duration: const Duration(milliseconds: 1500),
              curve: Curves.easeInOut,
              builder: (context, value, child) {
                return Transform.scale(
                  scale: value,
                  child: Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: Colors.blue[100],
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.calendar_today,
                      size: 64,
                      color: Colors.blue[700],
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 24),
            Text(
              'No workouts scheduled today',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.grey[800],
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              'Create a workout with a friend\nand start crushing your goals!',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[600],
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () {
                HapticFeedback.selectionClick();
                _showQuickCreateWorkoutDialog();
              },
              icon: const Icon(Icons.add_circle),
              label: const Text('Create Your First Workout'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue[700],
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 4,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _QuickTip(icon: Icons.people, text: 'Train together'),
                const SizedBox(width: 16),
                _QuickTip(icon: Icons.local_fire_department, text: 'Build streaks'),
                const SizedBox(width: 16),
                _QuickTip(icon: Icons.emoji_events, text: 'Earn badges'),
              ],
            ),
          ],
        ),
      ),
    );
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
    if (kDebugMode) print('🔄 Dashboard: Starting team sync...');
    
    final result = await _teamSyncService.syncAllTeamsCheckIns();
    
    if (result['success'] == true && result['synced'] > 0) {
      if (kDebugMode) print('✅ Dashboard: Synced ${result['synced']} teams');
      
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
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.5,
        minChildSize: 0.3,
        maxChildSize: 0.8,
        expand: false,
        builder: (context, scrollController) => Container(
          padding: const EdgeInsets.all(24),
          child: ListView(
            controller: scrollController,
            children: [
              // Handle bar
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              
              // Title with info hint
              Column(
                children: [
                  const Text(
                    '📊 Sort Your Streaks',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '👆 Tap to select • ✋ Long-press for info',  // ⭐ NEW HINT
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey[600],
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
                crossAxisSpacing: 8,        // ✅ REDUCED from 12
                mainAxisSpacing: 8,         // ✅ REDUCED from 12
                childAspectRatio: 2.0,      // ✅ ADJUSTED for less height
                physics: const NeverScrollableScrollPhysics(),
                children: StreakSortMode.values.map((mode) {
                  final isSelected = mode == _streakSortMode;
                  
                  return GestureDetector(
                    // ✅ FIX: Tap handler (was missing the actual code!)
                    onTap: () async {
                      print('🎯 USER TAPPED: ${mode.displayName}');
                      print('🎯 Old mode: ${_streakSortMode.displayName}');
                      
                      HapticFeedback.selectionClick();
                      
                      // ✅ SPECIAL HANDLING for Custom mode
                      if (mode == StreakSortMode.custom) {
                        Navigator.pop(context);  // Close sort menu first
                        
                        // ✅ Use addPostFrameCallback to show selector AFTER build completes
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          _showCustomModeSelector();
                        });
                        return;  // Don't continue with normal flow
                      }
                      
                      // ✅ For all other modes, continue normally
                      setState(() {
                        _streakSortMode = mode;
                        _currentCarouselIndex = 1;
                      });
                      
                      Navigator.pop(context);
                      
                      // Save preference to database
                      final userId = Supabase.instance.client.auth.currentUser?.id;
                      if (userId != null) {
                        await Supabase.instance.client.from('user_profiles').update({
                          'preferred_streak_sort': mode.name,
                        }).eq('id', userId);
                        print('💾 Saved preference: ${mode.name}');
                      }
                      
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (_carouselController.hasClients && mounted) {
                          _carouselController.jumpToPage(1000);
                          print('🎯 Jumped to center after preset change');
                        }
                      });
                    },
                    
                    // ⭐ Long-press shows info dialog
                    onLongPress: () {
                      HapticFeedback.mediumImpact();
                      _showSortModeInfo(context, mode);
                    },
                    
                    child: Container(
                      padding: const EdgeInsets.all(8),  // ✅ REDUCED from 12
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: isSelected
                              ? [Colors.blue[50]!, Colors.blue[100]!]
                              : [Colors.grey[50]!, Colors.grey[100]!],
                        ),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isSelected ? Colors.blue[400]! : Colors.grey[300]!,
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
                                    color: isSelected ? Colors.blue[900] : Colors.grey[800],
                                  ),
                                ),
                                Text(
                                  mode.description,
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: Colors.grey[600],
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
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Text(mode.emoji, style: const TextStyle(fontSize: 28)),
            const SizedBox(width: 12),
            Expanded(
              child: Text(mode.displayName, style: const TextStyle(fontSize: 20)),
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
                color: Colors.grey[700],
                height: 1.5,
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue[50],
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.blue[200]!),
              ),
              child: Row(
                children: [
                  Icon(Icons.lightbulb_outline, color: Colors.blue[700], size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _getSortModeExample(mode),
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.blue[900],
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
      print('❌ Error toggling favorite: $e');
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
    // Store template info to use after modal closes
    WorkoutTemplate? selectedTemplate;
    int? selectedDuration;
    String? selectedNotes;

    // Show workout selection modal FIRST
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (modalContext) => WorkoutSelectionModal(
        onWorkoutSelected: (template, duration, notes) {
          // Store selections
          selectedTemplate = template;
          selectedDuration = duration;
          selectedNotes = notes;
        },
      ),
    );

    // ✅ Check if user selected something (didn't just dismiss the modal)
    if (selectedTemplate == null || !mounted) return;

    // ✅ NOW show the timer with workout details (after modal is fully closed)
    final completed = await WorkoutCheckInSheet.show(
      context,
      workoutType: selectedTemplate!.name,
      workoutEmoji: selectedTemplate!.emoji,
      plannedDuration: selectedDuration!,
      onCheckInComplete: () async {
        // This runs when user completes the workout
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

          if (!mounted) return;

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(Icons.check_circle, color: Colors.white),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(result['message'] ?? 'Check-in successful!'),
                  ),
                ],
              ),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 3),
            ),
          );

          if (!mounted) return;

          // Reload data and check for milestones
          await _loadStreakData();
          _checkForMilestone();
        }
      },
    );

    // Reload data regardless of outcome
    if (completed != null && mounted) {
      await _loadStreakData();
    }
  }


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

  Future<void> _showRenameDialog(TeamStreak streak) async {
    final controller = TextEditingController(text: streak.teamName);
    
    final newName = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(Icons.edit, color: Colors.blue[600], size: 24),
            const SizedBox(width: 12),
            const Text('Rename Team'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Give your workout partnership a custom name!',
              style: TextStyle(fontSize: 14, color: Colors.grey[600]),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(
                labelText: 'Team Name',
                hintText: 'e.g., Gym Bros, Morning Crew',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                prefixIcon: const Icon(Icons.group),
              ),
              onSubmitted: (value) => Navigator.pop(context, value),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, controller.text),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue[600],
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (newName != null && newName.trim().isNotEmpty && newName != streak.teamName) {
      await _updateTeamName(streak, newName.trim());
    }
  }

  Future<void> _updateTeamName(TeamStreak streak, String newName) async {
    try {
      await Supabase.instance.client
          .from('buddy_teams')
          .update({'team_name': newName})
          .eq('id', streak.teamId);

      // Reload streaks and cast properly
      final teamStreakService = TeamStreakService();
      final updatedStreaks = await teamStreakService.getAllUserStreaks();

      if (mounted) {
        setState(() {
          _streaks = List<TeamStreak>.from(updatedStreaks);
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white, size: 20),
                const SizedBox(width: 12),
                Text('Renamed to "$newName"'),
              ],
            ),
            backgroundColor: Colors.green[600],
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
        );
      }
    } catch (e) {
      print('❌ Error renaming team: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to rename team'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  String _getBuddyName(TeamStreak streak) {
    if (streak.isCoachMaxTeam) return 'Coach Max';
    
    final currentUserId = Supabase.instance.client.auth.currentUser?.id;
    final buddy = streak.members.firstWhere(
      (m) => m.userId != currentUserId,
      orElse: () => streak.members.first,
    );
    return buddy.displayName;
  }

  String _getBuddyAvatar(TeamStreak streak) {
    if (streak.isCoachMaxTeam) return 'coach_max';
    
    final currentUserId = Supabase.instance.client.auth.currentUser?.id;
    final buddy = streak.members.firstWhere(
      (m) => m.userId != currentUserId,
      orElse: () => streak.members.first,
    );
    return buddy.avatarId ?? 'avatar_1';
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        width: double.maxFinite,
        constraints: const BoxConstraints(maxHeight: 500, maxWidth: 400),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.orange[400]!, Colors.deepOrange[400]!],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(20),
                  topRight: Radius.circular(20),
                ),
              ),
              child: Row(
                children: [
                  const Icon(Icons.local_fire_department, color: Colors.white, size: 28),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'All Your Streaks',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${_streaks.length}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Tip text
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  Icon(Icons.lightbulb_outline, size: 16, color: Colors.grey[500]),
                  const SizedBox(width: 8),
                  Text(
                    'Tap a streak to rename it',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[500],
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
              ),
            ),

            // Streaks list
            Flexible(
              child: _streaks.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.sentiment_neutral, size: 48, color: Colors.grey[400]),
                            const SizedBox(height: 12),
                            Text(
                              'No active streaks yet!',
                              style: TextStyle(color: Colors.grey[600]),
                            ),
                          ],
                        ),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                      shrinkWrap: true,
                      itemCount: _streaks.length,
                      itemBuilder: (context, index) {
                        final streak = _streaks[index];
                        return _buildStreakCard(streak);
                      },
                    ),
            ),

            // Close button
            Padding(
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: () => Navigator.pop(context),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(color: Colors.grey[300]!),
                    ),
                  ),
                  child: const Text('Close'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStreakCard(TeamStreak streak) {
    final buddyName = _getBuddyName(streak);
    final isComplete = streak.isCompleteToday;

    return GestureDetector(
      onTap: () => _showRenameDialog(streak),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isComplete ? Colors.green[50] : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isComplete ? Colors.green[200]! : Colors.grey[200]!,
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.03),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            // Avatar
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: streak.isCoachMaxTeam
                      ? [Colors.blue[400]!, Colors.purple[400]!]
                      : [Colors.orange[300]!, Colors.deepOrange[300]!],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: streak.isCoachMaxTeam
                  ? const Center(child: Text('🤖', style: TextStyle(fontSize: 22)))
                  : ClipOval(
                      child: UserAvatar(
                        avatarId: _getBuddyAvatar(streak),
                        size: 44,
                      ),
                    ),
            ),
            
            const SizedBox(width: 12),
            
            // Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Team name (or buddy name if not renamed)
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          streak.teamName,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Icon(
                        Icons.edit_outlined,
                        size: 14,
                        color: Colors.grey[400],
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  // Streak count
                  Row(
                    children: [
                      Icon(
                        Icons.local_fire_department,
                        size: 14,
                        color: Colors.orange[600],
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '${streak.currentStreak} day streak',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.orange[700],
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            
            // Status
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: isComplete ? Colors.green[100] : Colors.grey[100],
                shape: BoxShape.circle,
              ),
              child: Icon(
                isComplete ? Icons.check : Icons.access_time,
                size: 18,
                color: isComplete ? Colors.green[700] : Colors.grey[500],
              ),
            ),
          ],
        ),
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
          style: const TextStyle(
            fontSize: 12,
            color: Colors.grey,
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
    print('🔍 DEBUG: Current user ID: $currentUserId');
    
    final allInvites = await Supabase.instance.client
        .from('workout_invites')
        .select('*');
    
    print('🔍 DEBUG: ALL invites in database: $allInvites');
    
    final myInvites = await Supabase.instance.client
        .from('workout_invites')
        .select('*')
        .eq('recipient_id', currentUserId!);
    
    print('🔍 DEBUG: My invites as recipient: $myInvites');
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
      // ✅ Extra safety filter - remove completed/cancelled on client side too
      _upcomingWorkouts = workouts.where((w) => 
        w['status'] != 'completed' && w['status'] != 'cancelled'
      ).toList();
      _friends = friends;
      _isLoading = false;
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
      print('❌ Workout not found in list');
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
      print('❌ Failed to complete workout');
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
            print('✅ Creator (current user) check-in: ${userResult['message']}');
          } else {
            final result = await teamStreakService.checkInAllTeamsForUser(creatorId);
            print('✅ Creator check-in: Checked in to $result teams');
          }
        } else if (creatorCancelled) {
          print('⚠️ Creator cancelled - NO streak credit');
        }
        
        // Check in BUDDY if they didn't cancel
        if (!buddyCancelled && workoutBuddyId != null) {
          if (workoutBuddyId == currentUserId) {
            final userResult = await teamStreakService.checkInAllTeams();
            print('✅ Buddy (current user) check-in: ${userResult['message']}');
          } else {
            final result = await teamStreakService.checkInAllTeamsForUser(workoutBuddyId);
            print('✅ Buddy check-in: Checked in to $result teams');
          }
        } else if (buddyCancelled) {
          print('⚠️ Buddy cancelled - NO streak credit');
        }
        
      } catch (e) {
        print('❌ Auto check-in error: $e');
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
        if (!mounted) return; // ✅ CHECK MOUNTED
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
        title: const Text('Workout Schedule'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
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
              color: Colors.grey[400],
            ),
            const SizedBox(height: 16),
            Text(
              'No workouts scheduled',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.grey[600],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Tap the + button to schedule your first workout',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[500],
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
            print('📋 Schedule page: Invite action triggered, reloading data...');
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
            workout: workout,
            partnerName: partnerName,
            isCreator: isCreator,
            isBuddy: isBuddy,
            buddyStatus: buddyStatus,
            workoutStatus: workoutStatus,
            onStart: () => _startWorkout(workout['id']),
            onComplete: () => _completeWorkout(workout['id']),
            onCancel: () => _cancelWorkout(workout['id']),
            onAccept: () => _acceptInvitation(workout['id']),
            onDecline: () => _declineInvitation(workout['id']),
          );
        }).toList(),
        const CompletedWorkoutsSection(),
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
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          children: [
            Icon(Icons.calendar_today, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              'No scheduled workouts',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.grey[700],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Tap + to schedule a workout',
              style: TextStyle(fontSize: 14, color: Colors.grey[600]),
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

class _ProfilePageState extends State<ProfilePage> {
  List<dynamic> _allStreaks = [];
  bool _isLoadingStreaks = true;

  @override
  void initState() {
    super.initState();
    _loadStreaks();
  }

  Future<void> _loadStreaks() async {
    try {
      final teamStreakService = TeamStreakService();
      final streaks = await teamStreakService.getAllUserStreaks();
      
      if (mounted) {
        setState(() {
          _allStreaks = streaks;
          _isLoadingStreaks = false;
        });
      }
    } catch (e) {
      print('Error loading streaks: $e');
      if (mounted) {
        setState(() => _isLoadingStreaks = false);
      }
    }
  }

  Future<Map<String, dynamic>?> _loadProfileData() async {
    try {
      final currentUserId = Supabase.instance.client.auth.currentUser?.id;
      if (currentUserId == null) return null;

      final response = await Supabase.instance.client
          .from('user_profiles')
          .select('avatar_id, display_name, created_at')
          .eq('id', currentUserId)
          .single();

      return response;
    } catch (e) {
      return null;
    }
  }

  String _formatDate(String? dateStr) {
    if (dateStr == null) return '2024';
    try {
      final date = DateTime.parse(dateStr);
      return '${date.year}';
    } catch (e) {
      return '2024';
    }
  }

  void _showAllStreaksDialog() {
    showDialog(
      context: context,
      builder: (context) => _AllStreaksDialog(streaks: _allStreaks.cast<TeamStreak>()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () {},
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Profile Header
          Center(
            child: FutureBuilder<Map<String, dynamic>?>(
              future: _loadProfileData(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const CircularProgressIndicator();
                }
                
                final profile = snapshot.data!;
                
                return Column(
                  children: [
                    UserAvatar(
                      avatarId: profile['avatar_id'],
                      size: 100,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      profile['display_name'] ?? 'User',
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      'Member since ${_formatDate(profile['created_at'])}',
                      style: const TextStyle(color: Colors.grey),
                    ),
                  ],
                );
              },
            ),
          ),
          const SizedBox(height: 30),
          
          // Stats Grid
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _StatCard('Workouts', '42'),
              _StatCard('Streak', '7 days'),
              _StatCard('Buddies', '3'),
            ],
          ),
          const SizedBox(height: 30),

          // Menu Items
          ListTile(
            leading: Icon(Icons.local_fire_department, color: Colors.orange[700]),
            title: const Text('All Streaks'),
            trailing: const Icon(Icons.arrow_forward_ios),
            onTap: _showAllStreaksDialog,
          ),
          ListTile(
            leading: const Icon(Icons.emoji_events),
            title: const Text('Achievements'),
            trailing: const Icon(Icons.arrow_forward_ios),
            onTap: () {},
          ),
          ListTile(
            leading: const Icon(Icons.bar_chart),
            title: const Text('Progress'),
            trailing: const Icon(Icons.arrow_forward_ios),
            onTap: () {},
          ),
          ListTile(
            leading: const Icon(Icons.notifications),
            title: const Text('Notifications'),
            trailing: const Icon(Icons.arrow_forward_ios),
            onTap: () {},
          ),
          ListTile(
            leading: const Icon(Icons.help),
            title: const Text('Help & Support'),
            trailing: const Icon(Icons.arrow_forward_ios),
            onTap: () {},
          ),
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: () async {
              await Supabase.instance.client.auth.signOut();
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(builder: (_) => const LoginScreen()),
                (route) => false,
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Log Out'),
          ),
        ],
      ),
    );
  }

  // ✅ NEW: All Streaks Section Widget
  Widget _buildAllStreaksSection() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header row
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(Icons.local_fire_department, color: Colors.orange[700], size: 24),
                    const SizedBox(width: 8),
                    const Text(
                      'All Streaks',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                if (!_isLoadingStreaks)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.orange[100],
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${_allStreaks.length}',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Colors.orange[800],
                      ),
                    ),
                  ),
              ],
            ),
            
            const SizedBox(height: 16),
            
            // Streaks list or loading
            if (_isLoadingStreaks)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(20),
                  child: CircularProgressIndicator(),
                ),
              )
            else if (_allStreaks.isEmpty)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      Icon(Icons.sentiment_neutral, size: 48, color: Colors.grey[400]),
                      const SizedBox(height: 8),
                      Text(
                        'No active streaks yet',
                        style: TextStyle(color: Colors.grey[600]),
                      ),
                    ],
                  ),
                ),
              )
            else
              // Show first 3 streaks as preview
              Column(
                children: [
                  ..._allStreaks.take(3).map((streak) => _buildStreakTile(streak)).toList(),
                  
                  // "See All" button if more than 3
                  if (_allStreaks.length > 3)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: TextButton(
                        onPressed: _showAllStreaksDialog,
                        child: Text(
                          'See all ${_allStreaks.length} streaks →',
                          style: TextStyle(
                            color: Colors.blue[700],
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildStreakTile(dynamic streak) {
    final teamStreak = streak as TeamStreak;
    final currentUserId = Supabase.instance.client.auth.currentUser?.id;
    
    // Get friend's name for display
    String displayName;
    if (teamStreak.isCoachMaxTeam) {
      displayName = 'Coach Max';
    } else {
      final friendMember = teamStreak.members.firstWhere(
        (m) => m.userId != currentUserId,
        orElse: () => teamStreak.members.first,
      );
      displayName = friendMember.displayName;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: teamStreak.isCompleteToday ? Colors.green[50] : Colors.grey[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: teamStreak.isCompleteToday ? Colors.green[200]! : Colors.grey[200]!,
        ),
      ),
      child: Row(
        children: [
          // Avatar/Emoji
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: teamStreak.isCoachMaxTeam ? Colors.blue[100] : Colors.orange[100],
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                teamStreak.isCoachMaxTeam ? '🤖' : '💪',
                style: const TextStyle(fontSize: 20),
              ),
            ),
          ),
          const SizedBox(width: 12),
          
          // Name and streak
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  displayName,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
                Text(
                  '${teamStreak.currentStreak} day streak',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.orange[700],
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          
          // Status indicator
          Icon(
            teamStreak.isCompleteToday ? Icons.check_circle : Icons.radio_button_unchecked,
            color: teamStreak.isCompleteToday ? Colors.green : Colors.grey[400],
            size: 20,
          ),
        ],
      ),
    );
  }
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
          Text(label, style: const TextStyle(fontSize: 12)),
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
      backgroundColor: completed ? Colors.green : Colors.grey[300],
      child: Text(
        day,
        style: TextStyle(
          color: completed ? Colors.white : Colors.black,
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
          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
        ),
        Text(
          label,
          style: const TextStyle(color: Colors.grey),
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
        Icon(icon, size: 20, color: Colors.grey[600]),
        const SizedBox(height: 4),
        Text(
          text,
          style: TextStyle(
            fontSize: 10,
            color: Colors.grey[600],
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
              color: Colors.grey[700],
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }
}