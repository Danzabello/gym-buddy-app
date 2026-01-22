import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'user_avatar.dart';
import 'workout_history_sheet.dart';
import 'quick_schedule_sheet.dart';

/// A bottom sheet that displays a buddy's profile information
/// Shows: avatar, display name, @username, streak stats, and actions
class BuddyProfileSheet extends StatefulWidget {
  final String buddyDisplayName;
  final String buddyUsername;
  final String buddyAvatarId;
  final String buddyUserId;
  final int currentStreak;
  final int bestStreak;
  final int totalWorkouts;
  final DateTime? memberSince;
  final String? nickname; // Your custom nickname for this buddy
  final VoidCallback? onNicknameChanged;

  const BuddyProfileSheet({
    super.key,
    required this.buddyDisplayName,
    required this.buddyUsername,
    required this.buddyAvatarId,
    required this.buddyUserId,
    required this.currentStreak,
    required this.bestStreak,
    required this.totalWorkouts,
    this.memberSince,
    this.nickname,
    this.onNicknameChanged,
  });

  /// Static method to show the sheet
  static void show(
    BuildContext context, {
    required String buddyDisplayName,
    required String buddyUsername,
    required String buddyAvatarId,
    required String buddyUserId,
    required int currentStreak,
    required int bestStreak,
    required int totalWorkouts,
    DateTime? memberSince,
    String? nickname,
    VoidCallback? onNicknameChanged,
  }) {
    HapticFeedback.mediumImpact();
    
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => BuddyProfileSheet(
        buddyDisplayName: buddyDisplayName,
        buddyUsername: buddyUsername,
        buddyAvatarId: buddyAvatarId,
        buddyUserId: buddyUserId,
        currentStreak: currentStreak,
        bestStreak: bestStreak,
        totalWorkouts: totalWorkouts,
        memberSince: memberSince,
        nickname: nickname,
        onNicknameChanged: onNicknameChanged,
      ),
    );
  }

  @override
  State<BuddyProfileSheet> createState() => _BuddyProfileSheetState();
}

class _BuddyProfileSheetState extends State<BuddyProfileSheet> {
  String? _currentNickname;

  @override
  void initState() {
    super.initState();
    _currentNickname = widget.nickname;
  }

  Future<void> _showSetNicknameDialog() async {
    final controller = TextEditingController(text: _currentNickname ?? '');
    
    final newNickname = await showDialog<String?>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Icon(Icons.edit, color: Colors.blue[600], size: 24),
            const SizedBox(width: 12),
            const Text('Set Nickname'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Give ${widget.buddyDisplayName} a custom nickname that only you can see.',
              style: TextStyle(fontSize: 14, color: Colors.grey[600]),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(
                labelText: 'Nickname',
                hintText: 'e.g., Gym Bro, Mike',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                prefixIcon: const Icon(Icons.person_outline),
                suffixIcon: controller.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () => controller.clear(),
                      )
                    : null,
              ),
              onSubmitted: (value) => Navigator.pop(context, value),
            ),
            const SizedBox(height: 8),
            Text(
              'Leave empty to use their display name',
              style: TextStyle(fontSize: 12, color: Colors.grey[500]),
            ),
          ],
        ),
        actions: [
          if (_currentNickname != null && _currentNickname!.isNotEmpty)
            TextButton(
              onPressed: () => Navigator.pop(context, ''), // Empty = remove
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: const Text('Remove'),
            ),
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

    if (newNickname != null) {
      await _saveNickname(newNickname.isEmpty ? null : newNickname);
    }
  }

  Future<void> _saveNickname(String? nickname) async {
    try {
      final currentUserId = Supabase.instance.client.auth.currentUser?.id;
      if (currentUserId == null) return;

      if (nickname == null || nickname.isEmpty) {
        // Remove nickname
        await Supabase.instance.client
            .from('friend_nicknames')
            .delete()
            .eq('user_id', currentUserId)
            .eq('friend_id', widget.buddyUserId);
        
        setState(() => _currentNickname = null);
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Nickname removed'),
              backgroundColor: Colors.grey,
            ),
          );
        }
      } else {
        // Upsert nickname
        await Supabase.instance.client
            .from('friend_nicknames')
            .upsert({
              'user_id': currentUserId,
              'friend_id': widget.buddyUserId,
              'nickname': nickname,
              'updated_at': DateTime.now().toUtc().toIso8601String(),
            }, onConflict: 'user_id, friend_id');
        
        setState(() => _currentNickname = nickname);
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Nickname set to "$nickname"'),
              backgroundColor: Colors.green[600],
            ),
          );
        }
      }

      // Notify parent to refresh
      widget.onNicknameChanged?.call();
    } catch (e) {
      print('❌ Error saving nickname: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to save nickname'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle bar
          Container(
            margin: const EdgeInsets.only(top: 12),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          
          const SizedBox(height: 20),
          
          // Avatar and name section
          _buildProfileHeader(),
          
          const SizedBox(height: 24),
          
          // Stats row
          _buildStatsRow(),
          
          const SizedBox(height: 24),
          
          // Actions section
          _buildActionsSection(),
          
          // Bottom padding for safe area
          SizedBox(height: MediaQuery.of(context).padding.bottom + 16),
        ],
      ),
    );
  }

  Widget _buildProfileHeader() {
    final displayedName = _currentNickname ?? widget.buddyDisplayName;
    
    return Column(
      children: [
        // Avatar with gradient border
        Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              colors: [Colors.orange[400]!, Colors.deepOrange[400]!],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: Container(
            padding: const EdgeInsets.all(3),
            decoration: const BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
            ),
            child: UserAvatar(
              avatarId: widget.buddyAvatarId,
              size: 100,
            ),
          ),
        ),
        
        const SizedBox(height: 16),
        
        // Display name (or nickname) - clean, no extra tags
        Text(
          displayedName,
          style: const TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
          ),
        ),
        
        const SizedBox(height: 4),
        
        // Username
        Text(
          '@${widget.buddyUsername}',
          style: TextStyle(
            fontSize: 16,
            color: Colors.blue[600],
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _buildStatsRow() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _buildStatItem(
            icon: Icons.local_fire_department,
            value: '${widget.currentStreak}',
            label: 'Current\nStreak',
            color: Colors.orange[700]!,
          ),
          Container(
            height: 50,
            width: 1,
            color: Colors.grey[200],
          ),
          _buildStatItem(
            icon: Icons.emoji_events,
            value: '${widget.bestStreak}',
            label: 'Best\nStreak',
            color: Colors.amber[700]!,
          ),
          Container(
            height: 50,
            width: 1,
            color: Colors.grey[200],
          ),
          _buildStatItem(
            icon: Icons.fitness_center,
            value: '${widget.totalWorkouts}',
            label: 'Total\nWorkouts',
            color: Colors.blue[700]!,
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem({
    required IconData icon,
    required String value,
    required String label,
    required Color color,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color, size: 24),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 10,
            color: Colors.grey[600],
            height: 1.2,
          ),
        ),
      ],
    );
  }

  Widget _buildActionsSection() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        children: [
          // Set Nickname button
          _buildActionTile(
            icon: Icons.edit,
            iconColor: Colors.blue[600]!,
            title: _currentNickname != null ? 'Change Nickname' : 'Set Nickname',
            subtitle: _currentNickname != null
                ? 'Currently: "$_currentNickname"'
                : 'Give them a custom name only you see',
            onTap: _showSetNicknameDialog,
          ),
          
          const SizedBox(height: 12),
          
          // View Workout History
          _buildActionTile(
            icon: Icons.history,
            iconColor: Colors.purple[600]!,
            title: 'Workout History',
            subtitle: 'See workouts you\'ve done together',
            onTap: () {
              Navigator.pop(context);
              WorkoutHistorySheet.show(
                context,
                buddyUserId: widget.buddyUserId,
                buddyDisplayName: widget.buddyDisplayName,
                buddyAvatarId: widget.buddyAvatarId,
              );
            },
          ),
          
          const SizedBox(height: 12),
          
          // Schedule Workout button
          _buildActionTile(
            icon: Icons.calendar_today,
            iconColor: Colors.green[600]!,
            title: 'Schedule Workout',
            subtitle: 'Plan your next session together',
            onTap: () {
              Navigator.pop(context);
              QuickScheduleSheet.show(
                context,
                buddyUserId: widget.buddyUserId,
                buddyDisplayName: widget.buddyDisplayName,
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildActionTile({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.grey[50],
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.grey[200]!),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: iconColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: iconColor, size: 24),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[600],
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: Colors.grey[400]),
            ],
          ),
        ),
      ),
    );
  }
}