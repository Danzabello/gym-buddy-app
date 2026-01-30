import 'package:flutter/material.dart';
import '../services/break_day_service.dart';

class BreakDaySection extends StatefulWidget {
  final VoidCallback onBreakTaken;
  
  const BreakDaySection({
    Key? key,
    required this.onBreakTaken,
  }) : super(key: key);

  @override
  State<BreakDaySection> createState() => _BreakDaySectionState();
}

class _BreakDaySectionState extends State<BreakDaySection> {
  final BreakDayService _breakDayService = BreakDayService();
  int _remainingBreakDays = 0;
  bool _isOnBreakToday = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadBreakDayStatus();
  }

  Future<void> _loadBreakDayStatus() async {
    setState(() => _loading = true);
    
    final remaining = await _breakDayService.getRemainingBreakDays();
    final onBreak = await _breakDayService.isCurrentUserOnBreakToday();
    
    setState(() {
      _remainingBreakDays = remaining;
      _isOnBreakToday = onBreak;
      _loading = false;
    });
  }

  Future<void> _handleTakeBreak() async {
    // Show confirmation dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Take a Break Day?'),
        content: Text(
          'This will use one of your break days.\n\n'
          'Remaining after: ${_remainingBreakDays - 1} break days',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Take Break'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final success = await _breakDayService.declareBreakDay();
      
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Break day taken! Rest up 😴')),
        );
        widget.onBreakTaken();
        await _loadBreakDayStatus();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No break days remaining this week')),
        );
      }
    }
  }

  Future<void> _handleCancelBreak() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancel Break Day?'),
        content: const Text(
          'This will restore your break day token and allow you to check in.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('No'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Cancel Break'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _breakDayService.cancelBreakDay();
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Break day cancelled!')),
      );
      widget.onBreakTaken();
      await _loadBreakDayStatus();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const SizedBox(
        height: 60,
        child: Center(child: CircularProgressIndicator()),
      );
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _isOnBreakToday 
            ? Colors.blue.shade50 
            : Colors.grey.shade100,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _isOnBreakToday 
              ? Colors.blue.shade200 
              : Colors.grey.shade300,
        ),
      ),
      child: _isOnBreakToday
          ? _buildOnBreakView()
          : _buildNormalView(),
    );
  }

  Widget _buildOnBreakView() {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.blue.shade100,
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.bedtime, color: Colors.blue, size: 24),
        ),
        const SizedBox(width: 12),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Taking a Break Today',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              Text(
                'Rest up and recover 😴',
                style: TextStyle(
                  color: Colors.grey,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
        TextButton(
          onPressed: _handleCancelBreak,
          child: const Text('Cancel Break'),
        ),
      ],
    );
  }

  Widget _buildNormalView() {
    final hasBreakDays = _remainingBreakDays > 0;
    
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: hasBreakDays 
                ? Colors.orange.shade100 
                : Colors.grey.shade300,
            shape: BoxShape.circle,
          ),
          child: Icon(
            Icons.bedtime_outlined,
            color: hasBreakDays ? Colors.orange : Colors.grey,
            size: 24,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$_remainingBreakDays Break Day${_remainingBreakDays == 1 ? '' : 's'} Left',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              const Text(
                'Use when you need rest',
                style: TextStyle(
                  color: Colors.grey,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
        ElevatedButton(
          onPressed: hasBreakDays ? _handleTakeBreak : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.orange,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          child: const Text('Take Break'),
        ),
      ],
    );
  }
}