import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../widgets/workout_calendar_widget.dart';
import '../widgets/workout_history_list.dart';

class WorkoutHistoryPage extends StatefulWidget {
  const WorkoutHistoryPage({super.key});
  @override
  State<WorkoutHistoryPage> createState() => _WorkoutHistoryPageState();
}

class _WorkoutHistoryPageState extends State<WorkoutHistoryPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final appColors = AppColors.of(context);

    return Scaffold(
      // ✅ No backgroundColor — inherits scaffoldBackgroundColor from theme
      appBar: AppBar(
        title: const Text(
          'Workout History',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        // ✅ No backgroundColor/foregroundColor — inherits appBarTheme (transparent)
        bottom: TabBar(
          controller: _tabController,
          labelColor: appColors.streakOrange,
          unselectedLabelColor: appColors.subtleText,
          indicatorColor: appColors.streakOrange,
          indicatorWeight: 3,
          tabs: const [
            Tab(icon: Icon(Icons.calendar_month), text: 'Calendar'),
            Tab(icon: Icon(Icons.list), text: 'History'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: const [
          SingleChildScrollView(
            padding: EdgeInsets.all(16),
            child: WorkoutCalendarWidget(),
          ),
          WorkoutHistoryList(),
        ],
      ),
    );
  }
}