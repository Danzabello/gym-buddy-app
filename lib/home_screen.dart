import 'main.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'services/friend_service.dart';

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

// Dashboard/Home Page
class DashboardPage extends StatelessWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Gym Buddy'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: SingleChildScrollView(
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
                      'Ready to crush your workout?',
                      style: TextStyle(fontSize: 16, color: Colors.grey[600]),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            
            // Streak Card
            Card(
              color: Colors.orange[50],
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Icon(Icons.local_fire_department, 
                         size: 48, 
                         color: Colors.orange[700]),
                    const SizedBox(width: 16),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Current Streak',
                          style: TextStyle(fontSize: 16),
                        ),
                        Text(
                          '7 Days',
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                            color: Colors.orange[700],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            
            // Today's Workout
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
                  child: const Text('Check In'),
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
                  label: 'Log Workout',
                  color: Colors.green,
                  onTap: () {},
                ),
                _QuickActionButton(
                  icon: Icons.person_add,
                  label: 'Find Buddy',
                  color: Colors.blue,
                  onTap: () {},
                ),
                _QuickActionButton(
                  icon: Icons.camera_alt,
                  label: 'Progress Pic',
                  color: Colors.purple,
                  onTap: () {},
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// NEW Friends/Buddies Page with Real Functionality
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
  
  // NEW: Loading state tracking
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

  // UPDATED: With loading state
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

  // UPDATED: With loading state
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

  // UPDATED: With confirmation dialog and loading state
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
                      
                      // Search Results - UPDATED WITH LOADING STATE
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
                              // UPDATED: Show loading spinner while sending request
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
                      
                      // Pending Requests - UPDATED WITH LOADING STATE
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
                              // UPDATED: Show loading spinner while processing
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
                      
                      // Active Buddies (unchanged)
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

// Schedule Page (unchanged)
class SchedulePage extends StatelessWidget {
  const SchedulePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Workout Schedule'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () {},
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Week Overview
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'This Week',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _DayCircle('M', true),
                      _DayCircle('T', true),
                      _DayCircle('W', false),
                      _DayCircle('T', false),
                      _DayCircle('F', false),
                      _DayCircle('S', false),
                      _DayCircle('S', false),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          
          // Upcoming Workouts
          const Text(
            'Upcoming Workouts',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          _WorkoutCard(
            day: 'Today',
            time: '6:00 PM',
            type: 'Upper Body',
            buddy: 'John Smith',
          ),
          _WorkoutCard(
            day: 'Tomorrow',
            time: '7:00 AM',
            type: 'Cardio',
            buddy: 'Sarah Johnson',
          ),
          _WorkoutCard(
            day: 'Friday',
            time: '5:30 PM',
            type: 'Leg Day',
            buddy: 'Solo',
          ),
        ],
      ),
    );
  }
}

// Profile Page (unchanged)
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
