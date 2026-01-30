import 'package:flutter/material.dart';
import '../widgets/workout_calendar_widget.dart';
import '../widgets/workout_history_list.dart';

class WorkoutHistoryPage extends StatefulWidget {
  const WorkoutHistoryPage({super.key});

  @override
  State<WorkoutHistoryPage> createState() => _WorkoutHistoryPageState();
}

class _WorkoutHistoryPageState extends State<WorkoutHistoryPage> with SingleTickerProviderStateMixin {
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
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: const Text(
          'Workout History',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.white,
        foregroundColor: Colors.grey.shade800,
        elevation: 0,
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.orange.shade700,
          unselectedLabelColor: Colors.grey.shade500,
          indicatorColor: Colors.orange.shade700,
          indicatorWeight: 3,
          tabs: const [
            Tab(
              icon: Icon(Icons.calendar_month),
              text: 'Calendar',
            ),
            Tab(
              icon: Icon(Icons.list),
              text: 'History',
            ),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: const [
          // Calendar Tab
          SingleChildScrollView(
            padding: EdgeInsets.all(16),
            child: WorkoutCalendarWidget(),
          ),
          
          // History List Tab
          WorkoutHistoryList(),
        ],
      ),
    );
  }
}