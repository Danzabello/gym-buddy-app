import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/workout_invite_service.dart';
import 'user_avatar.dart';

/// Widget to display pending workout invites
class WorkoutInvitesCard extends StatefulWidget {
  const WorkoutInvitesCard({super.key});

  @override
  State<WorkoutInvitesCard> createState() => _WorkoutInvitesCardState();
}

class _WorkoutInvitesCardState extends State<WorkoutInvitesCard> {
  final _workoutInviteService = WorkoutInviteService();
  List<Map<String, dynamic>> _pendingInvites = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadPendingInvites();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _loadPendingInvites();
  }

  Future<void> _loadPendingInvites() async {
    setState(() => _isLoading = true);
    final invites = await _workoutInviteService.getPendingInvites();
    if (mounted) {
      setState(() {
        _pendingInvites = invites;
        _isLoading = false;
      });
    }
  }

  Future<void> _handleAccept(String inviteId) async {
    HapticFeedback.mediumImpact();
    final success = await _workoutInviteService.acceptInvite(inviteId);
    
    if (!mounted) return;

    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Row(
            children: [
              Icon(Icons.check_circle, color: Colors.white),
              SizedBox(width: 12),
              Text('Workout accepted! 💪'),
            ],
          ),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: 2),
        ),
      );
      _loadPendingInvites(); // Refresh list
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to accept invite'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _handleDecline(String inviteId) async {
    HapticFeedback.lightImpact();
    final success = await _workoutInviteService.declineInvite(inviteId);
    
    if (!mounted) return;

    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Invite declined'),
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: 2),
        ),
      );
      _loadPendingInvites(); // Refresh list
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to decline invite'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  String _formatDateTime(String isoString) {
    final dateTime = DateTime.parse(isoString);
    final now = DateTime.now();
    final difference = dateTime.difference(now);

    String dateStr;
    if (difference.inDays == 0) {
      dateStr = 'Today';
    } else if (difference.inDays == 1) {
      dateStr = 'Tomorrow';
    } else if (difference.inDays < 7) {
      dateStr = _getWeekday(dateTime.weekday);
    } else {
      dateStr = '${_getMonth(dateTime.month)} ${dateTime.day}';
    }

    final hour = dateTime.hour == 0 ? 12 : (dateTime.hour > 12 ? dateTime.hour - 12 : dateTime.hour);
    final minute = dateTime.minute.toString().padLeft(2, '0');
    final period = dateTime.hour >= 12 ? 'PM' : 'AM';

    return '$dateStr at $hour:$minute $period';
  }

  String _getWeekday(int weekday) {
    const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return weekdays[weekday - 1];
  }

  String _getMonth(int month) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return months[month - 1];
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Container(
        margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 10,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: const Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (_pendingInvites.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.orange[400]!, Colors.deepOrange[400]!],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.orange.withOpacity(0.3),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.notifications_active,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  'Workout Invites',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${_pendingInvites.length}',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Colors.orange[700],
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Invites list
          Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.only(
                bottomLeft: Radius.circular(16),
                bottomRight: Radius.circular(16),
              ),
            ),
            child: ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _pendingInvites.length,
              separatorBuilder: (context, index) => Divider(
                height: 1,
                color: Colors.grey[200],
                indent: 72,
              ),
              itemBuilder: (context, index) {
                final invite = _pendingInvites[index];
                final sender = invite['sender'] as Map<String, dynamic>;
                final senderName = sender['display_name'] ?? sender['username'] ?? 'Unknown';
                final scheduledFor = _formatDateTime(invite['scheduled_for']);

                return Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      // Avatar
                      UserAvatar(
                        avatarId: sender['avatar_id'],
                        size: 48,
                      ),
                      const SizedBox(width: 12),

                      // Info
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              senderName,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                Icon(Icons.schedule, size: 14, color: Colors.grey[600]),
                                const SizedBox(width: 4),
                                Text(
                                  scheduledFor,
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Colors.grey[700],
                                  ),
                                ),
                              ],
                            ),
                            if (invite['message'] != null) ...[
                              const SizedBox(height: 4),
                              Text(
                                invite['message'],
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Colors.grey[600],
                                  fontStyle: FontStyle.italic,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ],
                        ),
                      ),

                      const SizedBox(width: 12),

                      // Action buttons
                      Column(
                        children: [
                          // Accept button
                          InkWell(
                            onTap: () => _handleAccept(invite['id']),
                            borderRadius: BorderRadius.circular(8),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              decoration: BoxDecoration(
                                color: Colors.green,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Text(
                                'Accept',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 6),
                          // Decline button
                          InkWell(
                            onTap: () => _handleDecline(invite['id']),
                            borderRadius: BorderRadius.circular(8),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              decoration: BoxDecoration(
                                color: Colors.grey[300],
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                'Decline',
                                style: TextStyle(
                                  color: Colors.grey[700],
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}