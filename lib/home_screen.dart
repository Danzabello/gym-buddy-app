import 'main.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'services/friend_service.dart';
import 'services/workout_service.dart';
import 'services/team_streak_service.dart';
import 'widgets/coach_max_widget.dart';
import 'package:confetti/confetti.dart';


// import 'services/streak_service.dart'; Not using it anymore

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedIndex = 0;
  
  // Different pages for each tab
  final List<Widget> _pages = [
    const DashboardPage(),
    const FriendsPage(),
    const SchedulePage(),
    const ProfilePage(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _pages[_selectedIndex],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (index) {
          setState(() {
            _selectedIndex = index;
          });
        },
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

  @override
  void initState() {
    super.initState();
    _loadStreakData();
    _updateCountdown();
    Future.delayed(const Duration(minutes: 1), _updateCountdown);

    _confettiController = ConfettiController(duration: const Duration(seconds: 3));

  }

  @override
  void dispose() {
    _confettiController.dispose();  // ADD THIS LINE
    super.dispose();
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
    
    // Schedule next update
    Future.delayed(const Duration(minutes: 1), _updateCountdown);
  }

  Future<void> _loadStreakData() async {
    setState(() {
      _isLoading = true;
    });

    // Get current user ID
    final currentUserId = Supabase.instance.client.auth.currentUser?.id;

    // Get all streaks
    final allStreaks = await _teamStreakService.getAllUserStreaks();
    
    // Get highest streak for main display
    final highestStreak = await _teamStreakService.getHighestStreak();
    
    // Check if already checked in today
    final hasCheckedIn = await _teamStreakService.hasCheckedInToday();

    // Get today's workouts  
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
      _allStreaks = allStreaks;
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

  Future<void> _checkIn() async {
    // Double-check before proceeding
    if (_hasCheckedInToday) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('You\'ve already checked in today! 💪'),
          backgroundColor: Colors.orange,
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    setState(() {
      _isCheckingIn = true;
    });

    final result = await _teamStreakService.checkInAllTeams();

    setState(() {
      _isCheckingIn = false;
    });

    if (result['success'] == true) {
      // Success animation or feedback
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
              _showAllStreaks();
            },
          ),
        ),
      );

      await _loadStreakData();

      _checkForMilestone();

      _loadStreakData(); // Refresh data
    } else {
      // Handle duplicate or error
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
      
      // If it was a duplicate, refresh to update the UI
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
        appBar: AppBar(
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _getGreeting(),
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                _getCurrentDate(),
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[700],
                  fontWeight: FontWeight.normal,
                ),
              ),
            ],
          ),
          backgroundColor: Theme.of(context).colorScheme.inversePrimary,
          actions: [
            // Notification bell
            Stack(
              children: [
                IconButton(
                  icon: const Icon(Icons.notifications_outlined),
                  onPressed: () {
                    // TODO: Show notifications
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('No new notifications'),
                        duration: Duration(seconds: 1),
                      ),
                    );
                  },
                ),
                // Badge for unread notifications
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
            // Profile avatar
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: CircleAvatar(
                backgroundColor: Colors.blue[700],
                radius: 18,
                child: const Icon(
                  Icons.person,
                  color: Colors.white,
                  size: 20,
                ),
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
                      // Welcome Card
                      Card(
                        elevation: 4,
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Welcome back!',
                                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                _hasCheckedInToday 
                                    ? 'Great job checking in today!'
                                    : 'Ready to crush your workout?',
                                style: TextStyle(fontSize: 16, color: Colors.grey[600]),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),

                      Card(
                        elevation: 2,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [
                              _buildQuickStat(
                                icon: Icons.local_fire_department,
                                value: '${_highestStreak?.currentStreak ?? 0}',
                                label: 'Days',
                                color: Colors.orange,
                              ),
                              Container(
                                height: 30,
                                width: 1,
                                color: Colors.grey[300],
                              ),
                              _buildQuickStat(
                                icon: Icons.fitness_center,
                                value: '$_totalWorkouts',
                                label: 'Workouts',
                                color: Colors.blue,
                              ),
                              Container(
                                height: 30,
                                width: 1,
                                color: Colors.grey[300],
                              ),
                              _buildQuickStat(
                                icon: Icons.people,
                                value: '$_buddyCount',
                                label: 'Buddies',
                                color: Colors.green,
                              ),
                              Container(
                                height: 30,
                                width: 1,
                                color: Colors.grey[300],
                              ),
                              _buildQuickStat(
                                icon: Icons.emoji_events,
                                value: '$_achievementCount',
                                label: 'Badges',
                                color: Colors.purple,
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      
                      // Main Streak Card with Coach Max 
                      if (_highestStreak != null) ...[
                        Card(
                          color: Colors.orange[50],
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              children: [
                                // Coach Max Widget at the top
                                CoachMaxWidget(
                                  currentStreak: _highestStreak!.currentStreak,
                                  hasCheckedInToday: _hasCheckedInToday,
                                  showSpeechBubble: true,
                                ),
                                
                                const SizedBox(height: 16),
                                const Divider(),
                                const SizedBox(height: 16),
                                
                                // Header with team name
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Row(
                                      children: [
                                        Text(
                                          _highestStreak!.teamEmoji,
                                          style: const TextStyle(fontSize: 24),
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          _highestStreak!.teamName,
                                          style: const TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ],
                                    ),
                                    if (_allStreaks.length > 1)
                                      TextButton(
                                        onPressed: _showAllStreaks,
                                        child: Text('${_allStreaks.length} streaks'),
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                
                                // Main streak display
                                Row(
                                  children: [
                                    _buildProgressRing(
                                      currentStreak: _highestStreak!.currentStreak,
                                      nextMilestone: _getNextMilestone(_highestStreak!.currentStreak),
                                      color: Colors.orange[700]!,
                                      child: Icon(
                                        Icons.local_fire_department,
                                        size: 40,
                                        color: Colors.orange[700],
                                      ),
                                    ),
                                    const SizedBox(width: 16),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          const Text(
                                            'Current Streak',
                                            style: TextStyle(fontSize: 16),
                                          ),
                                          Text(
                                            '${_highestStreak!.currentStreak} Days',
                                            style: TextStyle(
                                              fontSize: 28,
                                              fontWeight: FontWeight.bold,
                                              color: Colors.orange[700],
                                            ),
                                          ),
                                          if (_highestStreak!.longestStreak > 0)
                                            Text(
                                              'Best: ${_highestStreak!.longestStreak} days',
                                              style: TextStyle(
                                                fontSize: 12,
                                                color: Colors.grey[600],
                                              ),
                                            ),
                                          const SizedBox(height: 4),
                                          // Next milestone indicator
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 8,
                                              vertical: 4,
                                            ),
                                            decoration: BoxDecoration(
                                              color: Colors.orange[100],
                                              borderRadius: BorderRadius.circular(12),
                                            ),
                                            child: Text(
                                              'Next: ${_getMilestoneName(_getNextMilestone(_highestStreak!.currentStreak))} (${_getNextMilestone(_highestStreak!.currentStreak)} days)',
                                              style: TextStyle(
                                                fontSize: 10,
                                                color: Colors.orange[900],
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ),  
                                        ],
                                      ),
                                    ),
                                    
                                    // Check-in Button
                                    ElevatedButton.icon(
                                      onPressed: _hasCheckedInToday || _isCheckingIn ? null : _checkIn,
                                      icon: _isCheckingIn
                                          ? const SizedBox(
                                              width: 16,
                                              height: 16,
                                              child: CircularProgressIndicator(strokeWidth: 2),
                                            )
                                          : Icon(_hasCheckedInToday ? Icons.check : Icons.fitness_center),
                                      label: Text(_hasCheckedInToday ? 'Checked In' : 'Check In'),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: _hasCheckedInToday ? Colors.green : Colors.orange[700],
                                        foregroundColor: Colors.white,
                                      ),
                                    ),
                                  ],
                                ),
                                
                                // Team completion status
                                if (_highestStreak!.members.length > 1) ...[
                                  const SizedBox(height: 16),
                                  _buildTeamCompletionBar(_highestStreak!),
                                ],

                                const SizedBox(height: 16),
                                const Divider(),
                                const SizedBox(height: 12),
                                _buildCalendarHeatMap(),
                                
                              ],
                            ),
                          ),
                        ),
                      ] else ...[
                        // No streaks yet
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(32),
                            child: Center(
                              child: Column(
                                children: [
                                  Icon(
                                    Icons.local_fire_department,
                                    size: 48,
                                    color: Colors.grey[400],
                                  ),
                                  const SizedBox(height: 16),
                                  Text(
                                    'No active streaks yet',
                                    style: TextStyle(
                                      fontSize: 16,
                                      color: Colors.grey[600],
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'Check in to start your streak!',
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: Colors.grey[500],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                      
                      const SizedBox(height: 20),
                      
                      // Today's Workout (unchanged)
                      const Text(
                        "Today's Workout",
                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 12),
                      Card(
                        child: ListTile(
                          leading: const CircleAvatar(
                            backgroundColor: Colors.blue,
                            child: Icon(Icons.fitness_center, color: Colors.white),
                          ),
                          title: const Text('Upper Body Day'),
                          subtitle: const Text('with John Smith • 6:00 PM'),
                          trailing: ElevatedButton(
                            onPressed: () {},
                            child: const Text('View'),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      
                      // Quick Actions
                      const Text(
                        'Quick Actions',
                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          _QuickActionButton(
                            icon: Icons.add_circle_outline,
                            label: 'New Workout',
                            color: Colors.green,
                            onTap: () {
                              final homeState = context.findAncestorStateOfType<_HomeScreenState>();
                              homeState?.setState(() {
                                homeState._selectedIndex = 2;
                              });
                            },
                          ),
                          _QuickActionButton(
                            icon: Icons.person_add,
                            label: 'Find Buddy',
                            color: Colors.blue,
                            onTap: () {
                              final homeState = context.findAncestorStateOfType<_HomeScreenState>();
                              homeState?.setState(() {
                                homeState._selectedIndex = 1;
                              });
                            },
                          ),
                          _QuickActionButton(
                            icon: Icons.history,
                            label: 'All Streaks',
                            color: Colors.purple,
                            onTap: _showAllStreaks,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Align(
          alignment: Alignment.topCenter,
          child: ConfettiWidget(
            confettiController: _confettiController,
            blastDirection: 3.14 / 2, // down
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
        
        // Progress bar
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
        
        // Member avatars
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

  // Show all streaks dialog
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

  Widget _buildQuickStat({
    required IconData icon,
    required String value,
    required String label,
    required Color color,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 4),
            Text(
              value,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: Colors.grey[600],
          ),
        ),
      ],
    );
  }

  Widget _buildProgressRing({
    required int currentStreak,
    required int nextMilestone,
    required Color color,
    required Widget child,
  }) {
    final progress = currentStreak / nextMilestone;
    
    return Stack(
      alignment: Alignment.center,
      children: [
        // Background ring (make it darker/more visible)
        SizedBox(
          width: 80,
          height: 80,
          child: CircularProgressIndicator(
            value: 1.0,
            strokeWidth: 8, // THICKER
            backgroundColor: Colors.grey[300], // DARKER
            valueColor: AlwaysStoppedAnimation<Color>(Colors.grey[300]!),
          ),
        ),
        // Progress ring (animated)
        SizedBox(
          width: 80,
          height: 80,
          child: TweenAnimationBuilder<double>(
            duration: const Duration(milliseconds: 1000),
            curve: Curves.easeInOut,
            tween: Tween<double>(
              begin: 0.0,
              end: progress > 1.0 ? 1.0 : progress,
            ),
            builder: (context, value, _) => CircularProgressIndicator(
              value: value,
              strokeWidth: 8, // THICKER
              backgroundColor: Colors.transparent,
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
        ),
        // Percentage text (optional - shows progress)
        if (progress > 0 && progress < 1)
          Positioned(
            bottom: 0,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: color, width: 1),
              ),
              child: Text(
                '${(progress * 100).toInt()}%',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
            ),
          ),
        // Center content (flame icon)
        child,
      ],
    );
  }

  int _getNextMilestone(int currentStreak) {
    if (currentStreak < 7) return 7;
    if (currentStreak < 30) return 30;
    if (currentStreak < 100) return 100;
    return currentStreak + 100; // Keep going!
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

  Widget _buildCalendarHeatMap() {
    // Get last 7 days of check-ins
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
    // Check if this date is in our check-in history
    if (_highestStreak == null) return false;
    
    final dateStr = date.toIso8601String().split('T')[0];
    
    // Check today's check-ins
    if (_isSameDay(date, DateTime.now())) {
      return _hasCheckedInToday;
    }
    
    // For past dates, check if within current streak
    final today = DateTime.now();
    final daysDiff = today.difference(date).inDays;
    
    // If within current streak range, it's checked in
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
    
    // Check if we hit a new milestone
    final milestones = [1, 3, 7, 14, 30, 50, 100, 365];
    
    if (milestones.contains(currentStreak) && currentStreak > _lastCelebratedStreak) {
      _lastCelebratedStreak = currentStreak;
      
      // Trigger confetti!
      _confettiController.play();
      
      // Show celebration dialog
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
      _loadFriends();
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
                              leading: CircleAvatar(
                                backgroundColor: Colors.blue,
                                child: Text(
                                  user['display_name']?.substring(0, 1).toUpperCase() ?? '?',
                                  style: const TextStyle(color: Colors.white),
                                ),
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
                              leading: CircleAvatar(
                                backgroundColor: Colors.orange,
                                child: Text(
                                  profile?['display_name']?.substring(0, 1).toUpperCase() ?? '?',
                                  style: const TextStyle(color: Colors.white),
                                ),
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
                                  CircleAvatar(
                                    backgroundColor: Colors.green,
                                    child: Text(
                                      friend['display_name']?.substring(0, 1).toUpperCase() ?? '?',
                                      style: const TextStyle(color: Colors.white),
                                    ),
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

        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: _getWorkoutColor(workout['workout_type']),
              child: const Icon(Icons.fitness_center, color: Colors.white),
            ),
            title: Row(
              children: [
                Text(
                  workout['workout_type'] ?? 'Workout',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                if (isBuddy && buddyStatus == 'pending')
                  Container(
                    margin: const EdgeInsets.only(left: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
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
                Text(
                  '${_formatDate(workout['workout_date'])} • ${workout['workout_time']}',
                ),
                if (workout['planned_duration_minutes'] != null)
                  Text(
                    'Duration: ${_formatDuration(workout['planned_duration_minutes'])}',
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                if (workout['status'] == 'in_progress')
                  Text(
                    'IN PROGRESS - Started ${_timeAgo(workout['workout_started_at'])}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: Colors.green,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                if (buddy != null)
                  Text(
                    isCreator 
                        ? 'with ${buddy['display_name']} ${buddyStatus == 'accepted' ? '✓' : '(pending)'}'
                        : 'with ${creator['display_name']}',
                    style: TextStyle(
                      fontWeight: FontWeight.w500,
                      color: buddyStatus == 'accepted' ? Colors.green : Colors.orange,
                    ),
                  )
                else
                  const Text('Solo workout'),
              ],
            ),
            trailing: PopupMenuButton(
              itemBuilder: (context) {
                // If user is the invited buddy and hasn't responded
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
                
                // Normal menu for creator or accepted workouts
                return [
                  if (workout['status'] == 'scheduled')
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
                  if (workout['status'] == 'in_progress')
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
                  if (isCreator && workout['status'] == 'scheduled')
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
        );
      },
    );
  }

  Color _getWorkoutColor(String? type) {
    switch (type?.toLowerCase()) {
      case 'cardio':
        return Colors.red;
      case 'strength':
      case 'weights':
        return Colors.blue;
      case 'legs':
      case 'leg day':
        return Colors.orange;
      case 'upper body':
        return Colors.purple;
      default:
        return Colors.green;
    }
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
        const SnackBar(
          content: Text('Workout scheduled!'),
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
              
              // Buddy Selection
              DropdownButtonFormField<String?>(
                value: _selectedBuddyId,
                decoration: const InputDecoration(
                  labelText: 'Workout Buddy (Optional)',
                  border: OutlineInputBorder(),
                ),
                items: [
                  const DropdownMenuItem<String?>(
                    value: null,
                    child: Text('Solo Workout'),
                  ),
                  ...widget.friends.map<DropdownMenuItem<String?>>((friend) {
                    return DropdownMenuItem<String?>(
                      value: friend['id'] as String?,
                      child: Text(friend['display_name'] ?? 'Unknown'),
                    );
                  }),
                ],
                onChanged: (String? value) {
                  setState(() {
                    _selectedBuddyId = value;
                  });
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
          child: _isCreating
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
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
class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key});

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
          const Center(
            child: Column(
              children: [
                CircleAvatar(
                  radius: 50,
                  backgroundColor: Colors.blue,
                  child: Icon(Icons.person, size: 50, color: Colors.white),
                ),
                SizedBox(height: 16),
                Text(
                  'Your Name',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                ),
                Text(
                  'Member since 2024',
                  style: TextStyle(color: Colors.grey),
                ),
              ],
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