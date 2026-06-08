import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../theme/app_theme.dart';
import 'user_avatar.dart';
import 'workout_history_sheet.dart';
import 'quick_schedule_sheet.dart';

class BuddyProfileSheet extends StatefulWidget {
  final String buddyDisplayName;
  final String buddyUsername;
  final String buddyAvatarId;
  final String buddyUserId;
  final int currentStreak;
  final int bestStreak;
  final int totalWorkouts;
  final DateTime? memberSince;
  final String? nickname;
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
              autofocus: false,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(
                labelText: 'Nickname',
                hintText: 'e.g., Gym Bro, Mike',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                prefixIcon: const Icon(Icons.person_outline),
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
              onPressed: () => Navigator.pop(context, ''),
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
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
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
        await Supabase.instance.client
            .from('friend_nicknames')
            .delete()
            .eq('user_id', currentUserId)
            .eq('friend_id', widget.buddyUserId);
        setState(() => _currentNickname = null);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Nickname removed'), backgroundColor: Colors.grey),
          );
        }
      } else {
        await Supabase.instance.client.from('friend_nicknames').upsert({
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
      widget.onNicknameChanged?.call();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to save nickname'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final appColors = AppColors.of(context);

    return Container(
      decoration: BoxDecoration(
        color: appColors.cardBackground,  // ✅ was Colors.white
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 12),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: appColors.divider,  // ✅ was Colors.grey[300]
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 20),
          _buildProfileHeader(appColors),
          const SizedBox(height: 24),
          _buildStatsRow(appColors),
          const SizedBox(height: 24),
          _buildActionsSection(appColors),
          SizedBox(height: MediaQuery.of(context).padding.bottom + 16),
        ],
      ),
    );
  }

  Widget _buildProfileHeader(AppColors appColors) {
    final displayedName = _currentNickname ?? widget.buddyDisplayName;
    return Column(
      children: [
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
            decoration: BoxDecoration(
              color: appColors.cardBackground,  // ✅ was Colors.white
              shape: BoxShape.circle,
            ),
            child: UserAvatar(avatarId: widget.buddyAvatarId, size: 100),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          displayedName,
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: Theme.of(context).colorScheme.onSurface,  // ✅ theme-aware
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '@${widget.buddyUsername}',
          style: TextStyle(fontSize: 16, color: Colors.blue[600], fontWeight: FontWeight.w500),
        ),
      ],
    );
  }

  Widget _buildStatsRow(AppColors appColors) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _buildStatItem('${widget.currentStreak}', 'Current\nStreak',
              Icons.local_fire_department, Colors.orange[700]!, appColors),
          Container(height: 50, width: 1, color: appColors.divider),  // ✅
          _buildStatItem('${widget.bestStreak}', 'Best\nStreak',
              Icons.emoji_events, Colors.amber[700]!, appColors),
          Container(height: 50, width: 1, color: appColors.divider),  // ✅
          _buildStatItem('${widget.totalWorkouts}', 'Total\nWorkouts',
              Icons.fitness_center, Colors.blue[700]!, appColors),
        ],
      ),
    );
  }

  Widget _buildStatItem(String value, String label, IconData icon,
      Color color, AppColors appColors) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color, size: 24),
        const SizedBox(height: 4),
        Text(value,
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: color)),
        Text(label,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 10, color: appColors.subtleText, height: 1.2)),  // ✅
      ],
    );
  }

  Widget _buildActionsSection(AppColors appColors) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        children: [
          _buildActionTile(
            icon: Icons.edit,
            iconColor: Colors.blue[600]!,
            title: _currentNickname != null ? 'Change Nickname' : 'Set Nickname',
            subtitle: _currentNickname != null
                ? 'Currently: "$_currentNickname"'
                : 'Give them a custom name only you see',
            onTap: _showSetNicknameDialog,
            appColors: appColors,
          ),
          const SizedBox(height: 12),
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
            appColors: appColors,
          ),
          const SizedBox(height: 12),
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
            appColors: appColors,
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
    required AppColors appColors,
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
            color: appColors.sectionBackground,  // ✅ was Colors.grey[50]
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: appColors.cardBorder),  // ✅ was Colors.grey[200]
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
                    Text(title,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Theme.of(context).colorScheme.onSurface,  // ✅
                        )),
                    const SizedBox(height: 2),
                    Text(subtitle,
                        style: TextStyle(fontSize: 12, color: appColors.subtleText)),  // ✅
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: appColors.subtleText),  // ✅
            ],
          ),
        ),
      ),
    );
  }
}