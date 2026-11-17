part of '../home_screen.dart';

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
    // Dashboard is the landing tab. Kept in sync on every tab change so a
    // buddy_checked_in push knows whether the dashboard's own realtime banner
    // is already visibly handling that event.
    LiveEventToast.dashboardTabActive = true;
    _pages = [
      const SchedulePage(),
      const FriendsPageModern(),
      DashboardPage(key: _dashboardKey),
      const ShopPage(),
      const ProfilePage(),
    ];
    NotificationService.tabRequest.addListener(_openRequestedTab);
    NotificationService.workoutRequest.addListener(_openRequestedWorkout);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _openRequestedTab();
      _openRequestedWorkout();
    });
  }

  /// A tapped push asked for a tab (see NotificationService.tabRequest).
  void _openRequestedTab() {
    final tab = NotificationService.tabRequest.value;
    if (tab == null || !mounted) return;
    NotificationService.tabRequest.value = null;
    _onTabChanged(tab);
  }

  /// A tapped workout push asked for that workout's page (see
  /// NotificationService.workoutRequest). Only a tap ever sets it.
  void _openRequestedWorkout() {
    if (!mounted) return;
    final id = NotificationService.takeWorkoutRequest();
    if (id == null) return;
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => WorkoutPage(workoutId: id)));
  }

  @override
  void dispose() {
    NotificationService.workoutRequest.removeListener(_openRequestedWorkout);
    NotificationService.tabRequest.removeListener(_openRequestedTab);
    _tabPageController.dispose();
    LiveEventToast.dashboardTabActive = false;
    HeaderMotion.session = null; // next sign-in sweeps again
    super.dispose();
  }

  void _onTabChanged(int index) {
    final previousIndex = _selectedIndex;

    setState(() {
      _selectedIndex = index;
    });
    LiveEventToast.dashboardTabActive = index == 2;

    // Animate tab PageView if not already on the right page
    if (_tabPageController.hasClients &&
        _tabPageController.page?.round() != index) {
      _tabPageController.animateToPage(
        index,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }

    if (index == 2 && previousIndex != 2) {
      _dashboardKey.currentState?._onTabShown();
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
      backgroundColor: context.watch<AccentThemeProvider>().palette.background,
      extendBody: true,
      body: PageView(
        controller: _tabPageController,
        physics: const PageScrollPhysics(),
        onPageChanged: (index) {
          if (index != _selectedIndex) {
            setState(() => _selectedIndex = index);
            LiveEventToast.dashboardTabActive = index == 2;
            if (index == 2) _dashboardKey.currentState?._onTabShown();
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
