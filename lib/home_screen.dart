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
      const FriendsPage(),
      const SchedulePage(),
      const ProfilePage(),
    ];
  }

  void _onTabChanged(int index) {
    final previousIndex = _selectedIndex;
    
    setState(() {
      _selectedIndex = index;
    });
    
    // Refresh dashboard when returning to it from friends page
    if (index == 0 && previousIndex == 1) {
      // Access the dashboard state and trigger refresh
      _dashboardKey.currentState?._loadStreakData();
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

class _DashboardPageState extends State<DashboardPage> {
  final TeamStreakService _teamStreakService = TeamStreakService();
  final WorkoutService _workoutService = WorkoutService();

  
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
  int _lastCelebratedStreak = 0;
  
  // NEW: For streak navigation
  int _currentStreakIndex = 0;
  final PageController _pageController = PageController();

  int _currentCarouselIndex = 0;
  late PageController _carouselController;

  @override
  void initState() {
    super.initState();
    _carouselController = PageController(
    viewportFraction: 0.35,
    initialPage: 1000, // Start in middle for infinite scroll
    );

    _loadStreakData();
    _updateCountdown();
    Future.delayed(const Duration(minutes: 1), _updateCountdown);
    _confettiController = ConfettiController(duration: const Duration(seconds: 3));

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _setupAppLifecycleListener();
    });
  }

  void _setupAppLifecycleListener() {
    _loadStreakData();
  }

  @override
  void dispose() {
    _confettiController.dispose();
    _carouselController.dispose();
    super.dispose();
  }

  Widget _buildStreakCarousel() {
    if (_allStreaks.isEmpty) {
      return _buildNoStreaksCard();
    }

    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
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
            // Title
            Text(
              'Your Active Streaks (${_allStreaks.length})',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Colors.grey[700],
              ),
            ),
            
            const SizedBox(height: 24),
            
            // CAROUSEL
            SizedBox(
              height: 200,
              child: _allStreaks.length == 1
                  ? _buildSingleStreakView(_allStreaks[0])  // ← NEW: Special case for 1 streak
                  : PageView.builder(
                      controller: _carouselController,
                      onPageChanged: (index) {
                        setState(() {
                          _currentCarouselIndex = index % _allStreaks.length;
                        });
                        HapticFeedback.selectionClick();
                      },
                      itemCount: _allStreaks.length >= 3 
                          ? _allStreaks.length * 1000  // Infinite scroll for 3+
                          : _allStreaks.length,        // No infinite for 1-2
                      itemBuilder: (context, index) {
                        final streakIndex = index % _allStreaks.length;
                        final streak = _allStreaks[streakIndex];
                        final isFocused = streakIndex == _currentCarouselIndex;
                        
                        return AnimatedBuilder(
                          animation: _carouselController,
                          builder: (context, child) {
                            double scale = 1.0;
                            if (_carouselController.position.haveDimensions) {
                              final page = _carouselController.page ?? index.toDouble();
                              final diff = (page - index).abs();
                              scale = (1 - (diff * 0.45)).clamp(0.55, 1.0);
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
                                  child: _buildCarouselAvatar(streak, isFocused),
                                ),
                              ),
                            );
                          },
                        );
                      },
                    ),
            ),
            
            const SizedBox(height: 20),
            
            // STREAK INFO for focused streak
            _buildStreakInfo(_allStreaks[_currentCarouselIndex]),
          ],
        ),
      ),
    );
  }

  Widget _buildSingleStreakView(TeamStreak streak) {
    return Center(
      child: _buildCarouselAvatar(streak, true),  // Always focused
    );
  }

  Widget _buildCarouselAvatar(TeamStreak streak, bool isFocused) {
    final isCoachMax = streak.isCoachMaxTeam;
    
    // For Coach Max, use the robot emoji
    if (isCoachMax) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            width: isFocused ? 140 : 75,
            height: isFocused ? 140 : 75,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: [Colors.blue[400]!, Colors.purple[400]!],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              border: Border.all(
                color: isFocused ? Colors.blue : Colors.transparent,
                width: isFocused ? 4 : 0,
              ),
              boxShadow: isFocused
                  ? [
                      BoxShadow(
                        color: Colors.blue.withOpacity(0.4),
                        blurRadius: 20,
                        spreadRadius: 5,
                      ),
                    ]
                  : [],
            ),
            child: Center(
              child: Text(
                '🤖',
                style: TextStyle(fontSize: isFocused ? 60 : 35),
              ),
            ),
          ),
          if (isFocused) ...[
            const SizedBox(height: 12),
            Text(
              streak.teamName,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ],
      );
    }

    final currentUserId = Supabase.instance.client.auth.currentUser?.id;
    final friendMember = streak.members.firstWhere(
      (member) => member.userId != currentUserId,
      orElse: () => streak.members.first,
    );
    
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          width: isFocused ? 140 : 75,
          height: isFocused ? 140 : 75,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              colors: [Colors.orange[400]!, Colors.red[400]!],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            border: Border.all(
              color: isFocused ? Colors.blue : Colors.transparent,
              width: isFocused ? 4 : 0,
            ),
            boxShadow: isFocused
                ? [
                    BoxShadow(
                      color: Colors.blue.withOpacity(0.4),
                      blurRadius: 20,
                      spreadRadius: 5,
                    ),
                  ]
                : [],
          ),
          child: ClipOval(
            child: UserAvatar(
              avatarId: friendMember.avatarId,
              size: isFocused ? 140 : 75,
            ),
          ),
        ),
        if (isFocused) ...[
          const SizedBox(height: 12),
          Text(
            friendMember.displayName,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildStreakInfo(TeamStreak streak) {
    final checkedInCount = streak.todayCheckIns.length;
    final totalMembers = streak.members.length;
    final isComplete = checkedInCount >= totalMembers;
    
    Color statusColor;
    String statusText;
    IconData statusIcon;
    
    if (checkedInCount == 0) {
      statusColor = Colors.orange;
      statusText = '⚠️ 0/$totalMembers Checked In';
      statusIcon = Icons.warning_amber_rounded;
    } else if (checkedInCount < totalMembers) {
      statusColor = Colors.blue;
      statusText = '⏳ $checkedInCount/$totalMembers Checked In';
      statusIcon = Icons.pending;
    } else {
      statusColor = Colors.green;
      statusText = '✓ Streak Complete!';
      statusIcon = Icons.check_circle;
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
            value: checkedInCount / totalMembers,
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

  Widget _buildThreeCardLayout() {
    final currentStreak = _allStreaks.isNotEmpty 
        ? _allStreaks[_currentCarouselIndex] 
        : null;
    
    return Row(
      children: [
        // CARD 1: Coach Max Quote
        Expanded(
          child: _buildCoachMaxCard(currentStreak),
        ),
        const SizedBox(width: 12),
        
        // CARD 2: Check In Button
        Expanded(
          child: _buildCheckInCard(),
        ),
        const SizedBox(width: 12),
        
        // CARD 3: Stats
        Expanded(
          child: _buildStatsCard(),
        ),
      ],
    );
  }

  Widget _buildCoachMaxCard(TeamStreak? streak) {
    String quote = "Let's crush today! 💪";
    
    if (streak != null) {
      if (streak.isCompleteToday) {
        quote = "Both checked in!\nYou're unstoppable! 🔥";
      } else if (streak.currentStreak >= 7) {
        quote = "${streak.currentStreak} days!\nKeep it going! 🚀";
      }
    }
    
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [Colors.blue[50]!, Colors.purple[50]!],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              '🤖',
              style: TextStyle(fontSize: 32),
            ),
            const SizedBox(height: 8),
            Text(
              quote,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Colors.grey[800],
                height: 1.3,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCheckInCard() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: _hasCheckedInToday 
                ? [Colors.green[100]!, Colors.green[200]!]
                : [Colors.orange[100]!, Colors.orange[200]!],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              _hasCheckedInToday ? Icons.check_circle : Icons.local_fire_department,
              size: 40,
              color: _hasCheckedInToday ? Colors.green[700] : Colors.orange[700],
            ),
            const SizedBox(height: 8),
            ElevatedButton(
              onPressed: _hasCheckedInToday || _isCheckingIn ? null : _checkIn,
              style: ElevatedButton.styleFrom(
                backgroundColor: _hasCheckedInToday ? Colors.green : Colors.orange[700],
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: _isCheckingIn
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Text(
                      _hasCheckedInToday ? 'Done! ✓' : 'Check In',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatsCard() {
    final checkedInStreaks = _allStreaks.where((s) => s.isCompleteToday).length;
    
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [Colors.white, Colors.blue[50]!],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '$checkedInStreaks/${_allStreaks.length}',
              style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.bold,
                color: Colors.blue[700],
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Complete',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[600],
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
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

  Future<void> _loadStreakData() async {
    setState(() {
      _isLoading = true;
    });

    final currentUserId = Supabase.instance.client.auth.currentUser?.id;

    final allStreaks = await _teamStreakService.getAllUserStreaks();
    
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
    
    print('✅ After deduplication: ${uniqueStreaks.length} streaks');
    
    final highestStreak = await _teamStreakService.getHighestStreak();
    final hasCheckedIn = await _teamStreakService.hasCheckedInToday();
    final todaysWorkouts = await _workoutService.getTodaysWorkouts();

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

    setState(() {
      _allStreaks = uniqueStreaks;  // ✅ Use deduplicated list
      _highestStreak = highestStreak;
      _hasCheckedInToday = hasCheckedIn;
      _todaysWorkouts = todaysWorkouts;
      _pendingRequests = pendingFriends.length + pendingWorkouts;

      _totalWorkouts = completedWorkouts;
      _buddyCount = friends.length;
      _achievementCount = achievements;

      _isLoading = false;
    });
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
      HapticFeedback.mediumImpact();  // ✅ HAPTIC FEEDBACK!
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('You\'ve already checked in today! 💪'),
          backgroundColor: Colors.orange,
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    HapticFeedback.lightImpact();  // ✅ HAPTIC FEEDBACK ON PRESS!
    
    setState(() {
      _isCheckingIn = true;
    });

    final result = await _teamStreakService.checkInAllTeams();

    setState(() {
      _isCheckingIn = false;
    });

    if (result['success'] == true) {
      HapticFeedback.heavyImpact();  // ✅ SUCCESS HAPTIC!
      
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
          action: SnackBarAction(
            label: 'VIEW',
            textColor: Colors.white,
            onPressed: () {
              HapticFeedback.selectionClick();  // ✅ HAPTIC FEEDBACK!
              _showAllStreaks();
            },
          ),
        ),
      );

      // ✅ Wait a moment for database to process, then refresh
      await Future.delayed(const Duration(milliseconds: 500));
      await _loadStreakData();
      _checkForMilestone();
    }else {
      HapticFeedback.mediumImpact();  // ✅ ERROR HAPTIC!
      
      final message = result['message'] ?? 'Check-in failed';
      final isDuplicate = message.toLowerCase().contains('already');
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(
                isDuplicate ? Icons.info : Icons.error,
                color: Colors.white,
              ),
              const SizedBox(width: 12),
              Expanded(child: Text(message)),
            ],
          ),
          backgroundColor: isDuplicate ? Colors.orange : Colors.red,
          duration: const Duration(seconds: 3),
        ),
      );
      
      if (isDuplicate) {
        _loadStreakData();
      }
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
                        
                        // THREE CARD LAYOUT
                        _buildThreeCardLayout(),
                        
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
          alignment: Alignment.topCenter,
          child: ConfettiWidget(
            confettiController: _confettiController,
            blastDirection: 3.14 / 2,
            emissionFrequency: 0.05,
            numberOfParticles: 50,
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

  void _showQuickCreateWorkoutDialog() async {
    final friendService = FriendService();
    final friends = await friendService.getFriends();
    
    if (!mounted) return;
    
    showDialog(
      context: context,
      builder: (context) => _CreateWorkoutDialog(
        friends: friends,
        onWorkoutCreated: _loadStreakData,
      ),
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

}

// All Streaks Dialog
class _AllStreaksDialog extends StatelessWidget {
  final List<TeamStreak> streaks;

  const _AllStreaksDialog({required this.streaks});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('All Your Streaks'),
      content: SizedBox(
        width: double.maxFinite,
        height: 400,
        child: streaks.isEmpty
            ? const Center(
                child: Text('No active streaks yet!'),
              )
            : ListView.builder(
                itemCount: streaks.length,
                itemBuilder: (context, index) {
                  final streak = streaks[index];
                  return Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    child: ListTile(
                      leading: Text(
                        streak.teamEmoji,
                        style: const TextStyle(fontSize: 32),
                      ),
                      title: Text(
                        streak.teamName,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 4),
                          Text(
                            '${streak.currentStreak} day streak',
                            style: const TextStyle(
                              color: Colors.orange,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if (streak.members.length > 1)
                            Text(
                              '${streak.todayCheckIns.length}/${streak.members.length} checked in today',
                              style: const TextStyle(fontSize: 12),
                            ),
                        ],
                      ),
                      trailing: Icon(
                        streak.isCompleteToday 
                            ? Icons.check_circle 
                            : Icons.pending,
                        color: streak.isCompleteToday 
                            ? Colors.green 
                            : Colors.orange,
                      ),
                    ),
                  );
                },
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
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

// Friends/Buddies Page with Real Functionality
class FriendsPage extends StatefulWidget {
  const FriendsPage({super.key});

  @override
  State<FriendsPage> createState() => _FriendsPageState();
}

class _FriendsPageState extends State<FriendsPage> {
  final FriendService _friendService = FriendService();
  final TextEditingController _searchController = TextEditingController();
  
  List<Map<String, dynamic>> _friends = [];
  List<Map<String, dynamic>> _pendingRequests = [];
  List<Map<String, dynamic>> _searchResults = [];
  bool _isLoading = true;
  bool _isSearching = false;
  
  // Loading state tracking
  String? _sendingRequestTo;
  String? _processingRequestId;

  @override
  void initState() {
    super.initState();
    _loadFriends();
  }

  Future<void> _loadFriends() async {
    setState(() {
      _isLoading = true;
    });

    final friends = await _friendService.getFriends();
    final pending = await _friendService.getPendingRequests();

    setState(() {
      _friends = friends;
      _pendingRequests = pending;
      _isLoading = false;
    });
  }

  Future<void> _searchUsers(String query) async {
    if (query.isEmpty) {
      setState(() {
        _searchResults = [];
        _isSearching = false;
      });
      return;
    }

    setState(() {
      _isSearching = true;
    });

    final results = await _friendService.searchUsers(query);

    setState(() {
      _searchResults = results;
      _isSearching = false;
    });
  }

  Future<void> _sendFriendRequest(String friendId) async {
    setState(() {
      _sendingRequestTo = friendId;
    });
    
    final success = await _friendService.sendFriendRequest(friendId);
    
    setState(() {
      _sendingRequestTo = null;
    });
    
    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Friend request sent!'),
          backgroundColor: Colors.green,
        ),
      );
      _searchController.clear();
      setState(() {
        _searchResults = [];
      });
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Already friends or request pending'),
          backgroundColor: Colors.orange,
        ),
      );
    }
  }

  Future<void> _acceptRequest(String requestId) async {
    setState(() {
      _processingRequestId = requestId;
    });
    
    final success = await _friendService.acceptFriendRequest(requestId);
    
    setState(() {
      _processingRequestId = null;
    });
    
    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Friend request accepted!'),
          backgroundColor: Colors.green,
        ),
      );
      await _loadFriends();
      
      // ✅ NEW: Force refresh the home page to show new streak
      if (mounted) {
        final homeState = context.findAncestorStateOfType<_HomeScreenState>();
        if (homeState != null) {
          // Switch to home tab
          homeState.setState(() {
            homeState._selectedIndex = 0;
          });
          // Force reload dashboard
          final dashboardState = homeState._pages[0] as DashboardPage;
          final dashboardStateKey = dashboardState.key as GlobalKey<_DashboardPageState>?;
          dashboardStateKey?.currentState?._loadStreakData();
        }
      }
    }
  }

  Future<void> _declineRequest(String requestId) async {
    // Show confirmation dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Decline Friend Request'),
        content: const Text('Are you sure you want to decline this friend request?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Decline'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() {
      _processingRequestId = requestId;
    });
    
    final success = await _friendService.declineFriendRequest(requestId);
    
    setState(() {
      _processingRequestId = null;
    });
    
    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Friend request declined'),
          backgroundColor: Colors.grey,
        ),
      );
      _loadFriends();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Gym Buddies'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadFriends,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Search Bar
                      TextField(
                        controller: _searchController,
                        decoration: InputDecoration(
                          hintText: 'Search for gym buddies...',
                          prefixIcon: const Icon(Icons.search),
                          suffixIcon: _searchController.text.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.clear),
                                  onPressed: () {
                                    _searchController.clear();
                                    setState(() {
                                      _searchResults = [];
                                    });
                                  },
                                )
                              : null,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          filled: true,
                          fillColor: Colors.grey[100],
                        ),
                        onChanged: (value) {
                          _searchUsers(value);
                        },
                      ),
                      
                      // Search Results
                      if (_searchResults.isNotEmpty) ...[
                        const SizedBox(height: 20),
                        const Text(
                          'Search Results',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 12),
                        ..._searchResults.map((user) {
                          return Card(
                            child: ListTile(
                              leading: UserAvatar(
                                avatarId: user['avatar_id'],
                                size: 40,
                              ),
                              title: Text(user['display_name'] ?? 'Unknown'),
                              subtitle: Text(
                                'Level: ${user['fitness_level'] ?? 'Not specified'}',
                              ),
                              trailing: _sendingRequestTo == user['id']
                                  ? const SizedBox(
                                      width: 24,
                                      height: 24,
                                      child: CircularProgressIndicator(strokeWidth: 2),
                                    )
                                  : IconButton(
                                      icon: const Icon(Icons.person_add),
                                      onPressed: () => _sendFriendRequest(user['id']),
                                    ),
                            ),
                          );
                        }).toList(),
                        const SizedBox(height: 20),
                      ],
                      
                      // Pending Requests
                      if (_pendingRequests.isNotEmpty) ...[
                        const SizedBox(height: 20),
                        const Text(
                          'Pending Requests',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 12),
                        ..._pendingRequests.map((request) {
                          final profile = request['user_profiles'];
                          return Card(
                            color: Colors.orange[50],
                            child: ListTile(
                              leading: UserAvatar(
                                avatarId: profile?['avatar_id'],
                                size: 40,
                              ),
                              title: Text(profile?['display_name'] ?? 'Unknown'),
                              subtitle: const Text('Wants to be your gym buddy'),
                              trailing: _processingRequestId == request['id']
                                  ? const SizedBox(
                                      width: 48,
                                      height: 24,
                                      child: Center(
                                        child: CircularProgressIndicator(strokeWidth: 2),
                                      ),
                                    )
                                  : Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        IconButton(
                                          icon: const Icon(Icons.check, color: Colors.green),
                                          onPressed: () => _acceptRequest(request['id']),
                                        ),
                                        IconButton(
                                          icon: const Icon(Icons.close, color: Colors.red),
                                          onPressed: () => _declineRequest(request['id']),
                                        ),
                                      ],
                                    ),
                            ),
                          );
                        }).toList(),
                      ],
                      
                      // Active Buddies
                      const SizedBox(height: 20),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Your Gym Buddies',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            '${_friends.length} buddies',
                            style: TextStyle(
                              color: Colors.grey[600],
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      
                      if (_friends.isEmpty)
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(32),
                            child: Center(
                              child: Column(
                                children: [
                                  Icon(
                                    Icons.group_add,
                                    size: 48,
                                    color: Colors.grey[400],
                                  ),
                                  const SizedBox(height: 16),
                                  Text(
                                    'No gym buddies yet',
                                    style: TextStyle(
                                      fontSize: 16,
                                      color: Colors.grey[600],
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'Search for friends to start training together!',
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: Colors.grey[500],
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        )
                      else
                        ..._friends.map((friend) {
                          return Card(
                            child: ListTile(
                              leading: Stack(
                                children: [
                                  UserAvatar(
                                    avatarId: friend['avatar_id'],
                                    size: 40,
                                  ),
                                  Positioned(
                                    right: 0,
                                    bottom: 0,
                                    child: Container(
                                      width: 12,
                                      height: 12,
                                      decoration: BoxDecoration(
                                        color: Colors.green,
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                          color: Colors.white,
                                          width: 2,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              title: Text(friend['display_name'] ?? 'Unknown'),
                              subtitle: Text(
                                '${friend['workout_days_per_week'] ?? 0} days/week • ${friend['fitness_level'] ?? 'beginner'}',
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.local_fire_department,
                                    color: Colors.orange,
                                    size: 20,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    '0',
                                    style: const TextStyle(fontSize: 14),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }).toList(),
                    ],
                  ),
                ),
              ),
            ),
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Widget _buildEmptyFriendsState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Animated Icon
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0.0, end: 1.0),
              duration: const Duration(milliseconds: 1200),
              curve: Curves.elasticOut,
              builder: (context, value, child) {
                return Transform.scale(
                  scale: value,
                  child: Container(
                    padding: const EdgeInsets.all(32),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Colors.green[100]!, Colors.blue[100]!],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.green.withOpacity(0.3),
                          blurRadius: 20,
                          spreadRadius: 5,
                        ),
                      ],
                    ),
                    child: Icon(
                      Icons.group_add,
                      size: 72,
                      color: Colors.green[700],
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 32),
            Text(
              'Find Your Gym Buddies!',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.grey[800],
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            Text(
              'Working out is better with friends.\nSearch for people and start training together!',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[600],
                height: 1.6,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.blue[50],
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: Colors.blue[700],
                          shape: BoxShape.circle,
                        ),
                        child: const Center(
                          child: Text(
                            '1',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Text(
                          'Search for friends using the search bar above',
                          style: TextStyle(color: Colors.grey[700]),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: Colors.blue[700],
                          shape: BoxShape.circle,
                        ),
                        child: const Center(
                          child: Text(
                            '2',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Text(
                          'Send friend requests',
                          style: TextStyle(color: Colors.grey[700]),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: Colors.blue[700],
                          shape: BoxShape.circle,
                        ),
                        child: const Center(
                          child: Text(
                            '3',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Text(
                          'Schedule workouts together and build streaks!',
                          style: TextStyle(color: Colors.grey[700]),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Text(
              '💡 Tip: Invite your real-life gym buddies!',
              style: TextStyle(
                fontSize: 12,
                color: Colors.orange[700],
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
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
  
  List<Map<String, dynamic>> _upcomingWorkouts = [];
  List<Map<String, dynamic>> _friends = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
    });

    final workouts = await _workoutService.getUpcomingWorkouts();
    final friends = await _friendService.getFriends();

    setState(() {
      _upcomingWorkouts = workouts;
      _friends = friends;
      _isLoading = false;
    });
  }

  void _showCreateWorkoutDialog() {
    showDialog(
      context: context,
      builder: (context) => _CreateWorkoutDialog(
        friends: _friends,
        onWorkoutCreated: _loadData,
      ),
    );
  }

  Future<void> _startWorkout(String workoutId) async {
    final success = await _workoutService.startWorkout(workoutId);
    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Workout started! Timer is running.'),
          backgroundColor: Colors.blue,
        ),
      );
      _loadData();
    }
  }

  Future<void> _completeWorkout(String workoutId) async {
    final workout = _upcomingWorkouts.firstWhere((w) => w['id'] == workoutId);
    final currentUserId = Supabase.instance.client.auth.currentUser?.id;
    
    // Check if this workout has a buddy and if they've accepted
    if (workout['buddy_id'] != null && workout['buddy_status'] != 'accepted') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Your buddy needs to accept the workout invitation first!'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    
    final success = await _workoutService.completeWorkoutWithDuration(workoutId);
    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Workout completed! Great job!'),
          backgroundColor: Colors.green,
        ),
      );
      _loadData();
    }
  }

  Future<void> _cancelWorkout(String workoutId) async {
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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Workout cancelled'),
            backgroundColor: Colors.grey,
          ),
        );
        _loadData();
      }
    }
  }

  Future<void> _acceptInvitation(String workoutId) async {
    final success = await _workoutService.acceptWorkoutInvitation(workoutId);
    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Workout invitation accepted!'),
          backgroundColor: Colors.green,
        ),
      );
      _loadData();
    }
  }

  Future<void> _declineInvitation(String workoutId) async {
    final success = await _workoutService.declineWorkoutInvitation(workoutId);
    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Workout invitation declined'),
          backgroundColor: Colors.grey,
        ),
      );
      _loadData();
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
              onRefresh: _loadData,
              child: _upcomingWorkouts.isEmpty
                  ? _buildEmptyState()
                  : _buildWorkoutList(),
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
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _upcomingWorkouts.length,
      itemBuilder: (context, index) {
        final workout = _upcomingWorkouts[index];
        final creator = workout['creator'];
        final buddy = workout['buddy'];
        final currentUserId = Supabase.instance.client.auth.currentUser?.id;
        final isCreator = workout['user_id'] == currentUserId;
        final isBuddy = workout['buddy_id'] == currentUserId;
        final buddyStatus = workout['buddy_status'];
        final workoutStatus = workout['status'];

        return Card(
          elevation: 3,
          margin: const EdgeInsets.only(bottom: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Colors.white,
                  _getWorkoutStatusColor(workoutStatus).withOpacity(0.05),
                ],
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
              ),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              children: [
                // Main content
                ListTile(
                  contentPadding: const EdgeInsets.all(16),
                  leading: Stack(
                    children: [
                      Hero(
                        tag: 'workout_${workout['id']}',
                        child: CircleAvatar(
                          radius: 28,
                          backgroundColor: _getWorkoutColor(workout['workout_type']).withOpacity(0.2),
                          child: Icon(
                            _getWorkoutIcon(workout['workout_type']),
                            color: _getWorkoutColor(workout['workout_type']),
                            size: 28,
                          ),
                        ),
                      ),
                      if (isBuddy && buddyStatus == 'pending')
                        Positioned(
                          right: 0,
                          top: 0,
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: Colors.orange,
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 2),
                            ),
                            child: const Icon(
                              Icons.notification_important,
                              color: Colors.white,
                              size: 10,
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
                      _buildStatusBadge(workoutStatus),  // ✅ NEW STATUS BADGE!
                    ],
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 8),
                      // Date and time row
                      Row(
                        children: [
                          Icon(Icons.calendar_today, size: 14, color: Colors.grey[600]),
                          const SizedBox(width: 4),
                          Text(
                            '${_formatDate(workout['workout_date'])} • ${workout['workout_time']}',
                            style: TextStyle(color: Colors.grey[600], fontSize: 13),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      // Duration and buddy row
                      Wrap(
                        spacing: 12,
                        children: [
                          if (workout['planned_duration_minutes'] != null)
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.timer, size: 14, color: Colors.grey[600]),
                                const SizedBox(width: 4),
                                Text(
                                  _formatDuration(workout['planned_duration_minutes']),
                                  style: TextStyle(color: Colors.grey[600], fontSize: 12),
                                ),
                              ],
                            ),
                          if (buddy != null || creator != null)
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.person, size: 14, color: Colors.blue[700]),
                                const SizedBox(width: 4),
                                Text(
                                  isCreator 
                                      ? 'with ${buddy?['display_name'] ?? 'Unknown'}'
                                      : 'with ${creator?['display_name'] ?? 'Unknown'}',
                                  style: TextStyle(
                                    color: Colors.blue[700],
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                        ],
                      ),
                      // In progress timer
                      if (workoutStatus == 'in_progress') ...[
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.orange[100],
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.timer, size: 14, color: Colors.orange[700]),
                              const SizedBox(width: 4),
                              Text(
                                'Started ${_timeAgo(workout['workout_started_at'])}',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.orange[900],
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      // Pending invite banner
                      if (isBuddy && buddyStatus == 'pending') ...[
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.orange[50],
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.orange[200]!),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.mail, size: 16, color: Colors.orange[700]),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  '${creator?['display_name']} invited you to join!',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.orange[900],
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                  trailing: PopupMenuButton(
                    itemBuilder: (context) {
                      if (isBuddy && buddyStatus == 'pending') {
                        return [
                          const PopupMenuItem(
                            value: 'accept',
                            child: Row(
                              children: [
                                Icon(Icons.check_circle, color: Colors.green),
                                SizedBox(width: 8),
                                Text('Accept Invite'),
                              ],
                            ),
                          ),
                          const PopupMenuItem(
                            value: 'decline',
                            child: Row(
                              children: [
                                Icon(Icons.cancel, color: Colors.red),
                                SizedBox(width: 8),
                                Text('Decline Invite'),
                              ],
                            ),
                          ),
                        ];
                      }
                      
                      return [
                        if (workoutStatus == 'scheduled')
                          const PopupMenuItem(
                            value: 'start',
                            child: Row(
                              children: [
                                Icon(Icons.play_arrow, color: Colors.blue),
                                SizedBox(width: 8),
                                Text('Start Workout'),
                              ],
                            ),
                          ),
                        if (workoutStatus == 'in_progress')
                          const PopupMenuItem(
                            value: 'complete',
                            child: Row(
                              children: [
                                Icon(Icons.check_circle, color: Colors.green),
                                SizedBox(width: 8),
                                Text('Complete'),
                              ],
                            ),
                          ),
                        if (isCreator && workoutStatus == 'scheduled')
                          const PopupMenuItem(
                            value: 'cancel',
                            child: Row(
                              children: [
                                Icon(Icons.cancel, color: Colors.red),
                                SizedBox(width: 8),
                                Text('Cancel'),
                              ],
                            ),
                          ),
                      ];
                    },
                    onSelected: (value) {
                      HapticFeedback.selectionClick();
                      if (value == 'start') {
                        _startWorkout(workout['id']);
                      } else if (value == 'complete') {
                        _completeWorkout(workout['id']);
                      } else if (value == 'cancel') {
                        _cancelWorkout(workout['id']);
                      } else if (value == 'accept') {
                        _acceptInvitation(workout['id']);
                      } else if (value == 'decline') {
                        _declineInvitation(workout['id']);
                      }
                    },
                  ),
                ),
                // Quick action buttons for pending invites
                if (isBuddy && buddyStatus == 'pending')
                  Container(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () {
                              HapticFeedback.lightImpact();
                              _acceptInvitation(workout['id']);
                            },
                            icon: const Icon(Icons.check, size: 20),
                            label: const Text('Accept'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () {
                              HapticFeedback.lightImpact();
                              _declineInvitation(workout['id']);
                            },
                            icon: const Icon(Icons.close, size: 20),
                            label: const Text('Decline'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.red,
                              side: const BorderSide(color: Colors.red),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
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
      },
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
  

}

// Create Workout Dialog
class _CreateWorkoutDialog extends StatefulWidget {
  final List<Map<String, dynamic>> friends;
  final VoidCallback onWorkoutCreated;

  const _CreateWorkoutDialog({
    required this.friends,
    required this.onWorkoutCreated,
  });

  @override
  State<_CreateWorkoutDialog> createState() => _CreateWorkoutDialogState();
}

class _CreateWorkoutDialogState extends State<_CreateWorkoutDialog> {
  final WorkoutService _workoutService = WorkoutService();
  final _formKey = GlobalKey<FormState>();
  
  String _workoutType = 'Cardio';
  DateTime _selectedDate = DateTime.now();
  TimeOfDay _selectedTime = TimeOfDay.now();
  int _plannedDuration = 60;
  String? _selectedBuddyId;
  final TextEditingController _notesController = TextEditingController();
  bool _isCreating = false;

  final List<String> _workoutTypes = [
    'Cardio',
    'Strength',
    'Weights',
    'Upper Body',
    'Lower Body',
    'Leg Day',
    'Full Body',
    'HIIT',
    'Yoga',
    'Other',
  ];

  @override
  void initState() {
    super.initState();
    print('📋 Friends in dialog: ${widget.friends.length}');
    widget.friends.forEach((friend) {
      print('  - ${friend['display_name']} (${friend['id']})');
    });
  }

  Future<void> _createWorkout() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isCreating = true;
    });

    final timeString = '${_selectedTime.hour.toString().padLeft(2, '0')}:${_selectedTime.minute.toString().padLeft(2, '0')}:00';

    final error = await _workoutService.createWorkout(
      workoutType: _workoutType,
      date: _selectedDate,
      time: timeString,
      plannedDurationMinutes: _plannedDuration,
      buddyId: _selectedBuddyId,
      notes: _notesController.text.isEmpty ? null : _notesController.text,
    );

    setState(() {
      _isCreating = false;
    });

    if (error == null) {
      widget.onWorkoutCreated();
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _selectedBuddyId != null 
                ? 'Workout invitation sent! 🎉'
                : 'Workout scheduled! 💪',
          ),
          backgroundColor: Colors.green,
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: $error'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Text('Schedule Workout'),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Workout Type
              DropdownButtonFormField<String>(
                value: _workoutType,
                decoration: const InputDecoration(
                  labelText: 'Workout Type',
                  border: OutlineInputBorder(),
                ),
                items: _workoutTypes.map((type) {
                  return DropdownMenuItem(value: type, child: Text(type));
                }).toList(),
                onChanged: (value) {
                  setState(() {
                    _workoutType = value!;
                  });
                },
              ),
              const SizedBox(height: 16),
              
              // Duration Selector
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Planned Duration: ${_formatDuration(_plannedDuration)}',
                      style: const TextStyle(fontSize: 16),
                    ),
                  ),
                  Row(
                    children: [
                      IconButton(
                        onPressed: _plannedDuration > 15
                            ? () => setState(() => _plannedDuration -= 15)
                            : null,
                        icon: const Icon(Icons.remove),
                      ),
                      IconButton(
                        onPressed: _plannedDuration < 240
                            ? () => setState(() => _plannedDuration += 15)
                            : null,
                        icon: const Icon(Icons.add),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 16),
              
              // Date Picker
              ListTile(
                title: const Text('Date'),
                subtitle: Text(_formatDate(_selectedDate)),
                trailing: const Icon(Icons.calendar_today),
                onTap: () async {
                  final date = await showDatePicker(
                    context: context,
                    initialDate: _selectedDate,
                    firstDate: DateTime.now(),
                    lastDate: DateTime.now().add(const Duration(days: 365)),
                  );
                  if (date != null) {
                    setState(() {
                      _selectedDate = date;
                    });
                  }
                },
              ),
              
              // Time Picker
              ListTile(
                title: const Text('Time'),
                subtitle: Text(_selectedTime.format(context)),
                trailing: const Icon(Icons.access_time),
                onTap: () async {
                  final time = await showTimePicker(
                    context: context,
                    initialTime: _selectedTime,
                  );
                  if (time != null) {
                    setState(() {
                      _selectedTime = time;
                    });
                  }
                },
              ),
              const SizedBox(height: 16),
              
              // Buddy Selection - FIXED WITHOUT EXPANDED
              DropdownButtonFormField<String?>(
                value: _selectedBuddyId,
                decoration: InputDecoration(
                  labelText: 'Workout Buddy (Optional)',
                  border: const OutlineInputBorder(),
                  helperText: widget.friends.isEmpty 
                      ? 'Add friends to invite them!' 
                      : '${widget.friends.length} friend${widget.friends.length == 1 ? '' : 's'} available',
                  helperStyle: TextStyle(
                    color: widget.friends.isEmpty ? Colors.orange : Colors.grey,
                  ),
                ),
                items: [
                  const DropdownMenuItem<String?>(
                    value: null,
                    child: Text('👤 Solo Workout'),
                  ),
                  ...widget.friends.map<DropdownMenuItem<String?>>((friend) {
                    final name = friend['display_name'] ?? 'Unknown';
                    final initial = name.isNotEmpty ? name.substring(0, 1).toUpperCase() : '?';
                    
                    return DropdownMenuItem<String?>(
                      value: friend['id'] as String?,
                      child: Text('🟢 $name'),  // Simple text, no complex Row widget
                    );
                  }),
                ],
                onChanged: (String? value) {
                  setState(() {
                    _selectedBuddyId = value;
                  });
                  if (value != null) {
                    final friendName = widget.friends
                        .firstWhere((f) => f['id'] == value)['display_name'];
                    print('🎯 Selected buddy: $friendName ($value)');
                  } else {
                    print('🎯 Selected: Solo workout');
                  }
                },
              ),
              const SizedBox(height: 16),
              
              // Notes
              TextFormField(
                controller: _notesController,
                decoration: const InputDecoration(
                  labelText: 'Notes (Optional)',
                  border: OutlineInputBorder(),
                ),
                maxLines: 2,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isCreating ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _isCreating ? null : _createWorkout,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.blue[700],
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          child: _isCreating
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Text('Schedule'),
        ),
      ],
    );
  }

  String _formatDate(DateTime date) {
    return '${date.month}/${date.day}/${date.year}';
  }

  String _formatDuration(int minutes) {
    final hours = minutes ~/ 60;
    final mins = minutes % 60;
    if (hours > 0) {
      return mins > 0 ? '${hours}h ${mins}m' : '${hours}h';
    }
    return '${mins}m';
  }

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }
}

// Profile Page
class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
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
              // Sign out from Supabase
              await Supabase.instance.client.auth.signOut();
    
              // Navigate to login and remove all previous routes
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