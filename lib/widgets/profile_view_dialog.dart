import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'user_avatar.dart';

/// Profile View Dialog - Shows friend's profile details
class ProfileViewDialog extends StatefulWidget {
  final Map<String, dynamic> friendProfile;

  const ProfileViewDialog({
    super.key,
    required this.friendProfile,
  });

  @override
  State<ProfileViewDialog> createState() => _ProfileViewDialogState();
}

class _ProfileViewDialogState extends State<ProfileViewDialog> {
  List<Map<String, dynamic>> _sharedStreaks = [];
  bool _isLoadingStreaks = true;

  @override
  void initState() {
    super.initState();
    _loadSharedStreaks();
  }

  Future<void> _loadSharedStreaks() async {
    setState(() => _isLoadingStreaks = true);

    try {
      final currentUserId = Supabase.instance.client.auth.currentUser?.id;
      if (currentUserId == null) return;

      print('🔍 Loading shared streaks between $currentUserId and ${widget.friendProfile['id']}');

      // Step 1: Get all team_ids where current user is a member
      final myTeams = await Supabase.instance.client
          .from('team_members')
          .select('team_id')
          .eq('user_id', currentUserId);

      print('📊 My teams: ${myTeams.map((t) => t['team_id']).toList()}');

      // Step 2: Get all team_ids where friend is a member
      final friendTeams = await Supabase.instance.client
          .from('team_members')
          .select('team_id')
          .eq('user_id', widget.friendProfile['id']);

      print('📊 Friend teams: ${friendTeams.map((t) => t['team_id']).toList()}');

      // Step 3: Find teams that appear in both lists
      final myTeamIds = myTeams.map((t) => t['team_id']).toSet();
      final friendTeamIds = friendTeams.map((t) => t['team_id']).toSet();
      final sharedTeamIds = myTeamIds.intersection(friendTeamIds).toList();

      print('🤝 Shared team IDs: $sharedTeamIds');

      // Step 4: Get team details and streaks for shared teams
      final sharedStreaks = <Map<String, dynamic>>[];
      
      for (final teamId in sharedTeamIds) {
        // Get team info
        final teamInfo = await Supabase.instance.client
            .from('buddy_teams')
            .select('id, team_name, team_emoji, is_coach_max_team')
            .eq('id', teamId)
            .single();

        // Skip Coach Max teams
        if (teamInfo['is_coach_max_team'] == true) {
          print('⏭️ Skipping Coach Max team');
          continue;
        }

        // Get streak info
        final streakInfo = await Supabase.instance.client
            .from('team_streaks')
            .select('current_streak, is_active')
            .eq('team_id', teamId)
            .eq('is_active', true)
            .maybeSingle();

        if (streakInfo != null) {
          print('✅ Found shared streak: ${teamInfo['team_name']} with ${streakInfo['current_streak']} days');
          sharedStreaks.add({
            'team_id': teamId,
            'team_name': teamInfo['team_name'],
            'team_emoji': teamInfo['team_emoji'],
            'current_streak': streakInfo['current_streak'],
          });
        }
      }

      print('📊 Total shared streaks found: ${sharedStreaks.length}');

      setState(() {
        _sharedStreaks = sharedStreaks;
        _isLoadingStreaks = false;
      });
    } catch (e) {
      print('❌ Error loading shared streaks: $e');
      setState(() => _isLoadingStreaks = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final displayName = widget.friendProfile['display_name'] ?? 'Unknown User';
    final username = widget.friendProfile['username'] ?? '';
    final workoutFreq = widget.friendProfile['workout_frequency'] ?? 3;
    final fitnessLevel = widget.friendProfile['fitness_level'] ?? 'BEGINNER';

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 400),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header with gradient
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Colors.blue[600]!, Colors.purple[600]!],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(24),
                    topRight: Radius.circular(24),
                  ),
                ),
                child: Column(
                  children: [
                    // Large avatar
                    Hero(
                      tag: 'avatar_${widget.friendProfile['id']}',
                      child: UserAvatar(
                        avatarId: widget.friendProfile['avatar_id'],
                        size: 80,
                      ),
                    ),
                    const SizedBox(height: 16),
                    
                    // Name
                    Text(
                      displayName,
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    
                    // Username
                    if (username.isNotEmpty)
                      Text(
                        '@$username',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.white.withOpacity(0.8),
                        ),
                      ),
                  ],
                ),
              ),

              // Profile details
              Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Workout Frequency
                    _buildInfoRow(
                      icon: Icons.calendar_today,
                      label: 'Workout Frequency',
                      value: '$workoutFreq days/week',
                      color: Colors.blue,
                    ),
                    
                    const SizedBox(height: 16),
                    
                    // Fitness Level
                    _buildInfoRow(
                      icon: Icons.fitness_center,
                      label: 'Fitness Level',
                      value: _formatFitnessLevel(fitnessLevel),
                      color: Colors.purple,
                    ),
                    
                    const SizedBox(height: 24),
                    
                    // Shared Streaks Section
                    const Divider(),
                    const SizedBox(height: 16),
                    
                    Row(
                      children: [
                        Icon(Icons.emoji_events, color: Colors.orange[700], size: 24),
                        const SizedBox(width: 8),
                        const Text(
                          'Shared Streaks',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    
                    const SizedBox(height: 12),
                    
                    // Shared streaks list
                    _isLoadingStreaks
                        ? const Center(
                            child: Padding(
                              padding: EdgeInsets.all(16.0),
                              child: CircularProgressIndicator(),
                            ),
                          )
                        : _sharedStreaks.isEmpty
                            ? Center(
                                child: Padding(
                                  padding: const EdgeInsets.all(16.0),
                                  child: Text(
                                    'No shared streaks yet',
                                    style: TextStyle(
                                      color: Colors.grey[600],
                                      fontSize: 14,
                                    ),
                                  ),
                                ),
                              )
                            : Column(
                                children: _sharedStreaks.map((streak) {
                                  return _buildStreakCard(streak);
                                }).toList(),
                              ),
                  ],
                ),
              ),

              // Close button
              Padding(
                padding: const EdgeInsets.only(left: 24, right: 24, bottom: 24),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(context),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue[600],
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      'Close',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoRow({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: color.withOpacity(0.3),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStreakCard(dynamic streak) {
    final teamName = streak['team_name'] ?? 'Unknown Team';
    final currentStreak = streak['current_streak'] ?? 0;
    final emoji = streak['team_emoji'] ?? '💪';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.orange[50]!, Colors.yellow[50]!],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Colors.orange[200]!,
          width: 1.5,
        ),
      ),
      child: Row(
        children: [
          // Team emoji
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.orange.withOpacity(0.2),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Center(
              child: Text(
                emoji,
                style: const TextStyle(fontSize: 24),
              ),
            ),
          ),
          
          const SizedBox(width: 16),
          
          // Streak info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  teamName,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(Icons.local_fire_department, 
                      color: Colors.orange[700], 
                      size: 16,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '$currentStreak day streak',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey[700],
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatFitnessLevel(String level) {
    switch (level.toUpperCase()) {
      case 'BEGINNER':
        return 'Beginner';
      case 'INTERMEDIATE':
        return 'Intermediate';
      case 'ADVANCED':
        return 'Advanced';
      case 'EXPERT':
        return 'Expert';
      default:
        return level;
    }
  }
}