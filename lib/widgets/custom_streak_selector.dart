import 'package:flutter/material.dart';
import '../services/team_streak_service.dart';
import 'user_avatar.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class CustomStreakSelector extends StatefulWidget {
  final List<TeamStreak> availableStreaks;
  final List<TeamStreak>? currentSelection;
  
  const CustomStreakSelector({
    super.key,
    required this.availableStreaks,
    this.currentSelection,
  });
  
  @override
  State<CustomStreakSelector> createState() => _CustomStreakSelectorState();
}

class _CustomStreakSelectorState extends State<CustomStreakSelector> 
    with SingleTickerProviderStateMixin {
  late List<TeamStreak> _available;
  TeamStreak? _leftSlot;
  TeamStreak? _centerSlot;
  TeamStreak? _rightSlot;
  String _searchQuery = '';
  
  late AnimationController _animationController;
  late Animation<Offset> _slideAnimation;
  
  @override
  void initState() {
    super.initState();
    _available = List.from(widget.availableStreaks);
    
    // ✅ SMOOTH ENTRANCE ANIMATION
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 1),  // Start from bottom
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOutCubic,
    ));
    
    // Start animation
    _animationController.forward();
    
    // Load existing selection if provided
    if (widget.currentSelection != null && widget.currentSelection!.length == 3) {
      _leftSlot = widget.currentSelection![0];
      _centerSlot = widget.currentSelection![1];
      _rightSlot = widget.currentSelection![2];
      
      // Remove selected from available
      _available.removeWhere((s) => 
        s.teamId == _leftSlot?.teamId ||
        s.teamId == _centerSlot?.teamId ||
        s.teamId == _rightSlot?.teamId
      );
    }
  }
  
  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }
  
  List<TeamStreak> get _filteredStreaks {
    if (_searchQuery.isEmpty) return _available;
    return _available.where((s) => 
      s.teamName.toLowerCase().contains(_searchQuery.toLowerCase())
    ).toList();
  }
  
  bool get _allSlotsFilled => _leftSlot != null && _centerSlot != null && _rightSlot != null;
  
  // ✅ Get friend's display name and avatar
  String _getFriendName(TeamStreak streak) {
    final currentUserId = Supabase.instance.client.auth.currentUser?.id;
    final friendMember = streak.members.firstWhere(
      (member) => member.userId != currentUserId,
      orElse: () => streak.members.first,
    );
    return friendMember.displayName;
  }
  
  String _getFriendAvatar(TeamStreak streak) {
    final currentUserId = Supabase.instance.client.auth.currentUser?.id;
    final friendMember = streak.members.firstWhere(
      (member) => member.userId != currentUserId,
      orElse: () => streak.members.first,
    );
    return friendMember.avatarId ?? 'avatar_1';
  }
  
  @override
  Widget build(BuildContext context) {
    return SlideTransition(
      position: _slideAnimation,
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          title: const Text('Custom Streak Order'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.pop(context),  // ✅ BACK BUTTON
          ),
          actions: [
            if (_allSlotsFilled)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.pop(context, [_leftSlot!, _centerSlot!, _rightSlot!]);
                  },
                  icon: const Icon(Icons.check, size: 20),
                  label: const Text('SAVE'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green[600],
                    foregroundColor: Colors.white,
                    elevation: 0,
                  ),
                ),
              ),
          ],
        ),
        body: Column(
          children: [
            // Search Bar
            Padding(
              padding: const EdgeInsets.all(16),
              child: TextField(
                decoration: InputDecoration(
                  hintText: 'Search workout buddies...',
                  prefixIcon: const Icon(Icons.search),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  filled: true,
                  fillColor: Colors.grey[100],
                ),
                onChanged: (value) {
                  setState(() {
                    _searchQuery = value;
                  });
                },
              ),
            ),
            
            // Instruction Text
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                'Drag buddies into the 3 slots below',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey[700],
                ),
              ),
            ),
            const SizedBox(height: 16),
            
            // Slot Selector
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildSlot('Left', _leftSlot, (streak) {
                    setState(() {
                      if (_leftSlot != null) _available.add(_leftSlot!);
                      _leftSlot = streak;
                      _available.remove(streak);
                    });
                  }),
                  _buildSlot('Center', _centerSlot, (streak) {
                    setState(() {
                      if (_centerSlot != null) _available.add(_centerSlot!);
                      _centerSlot = streak;
                      _available.remove(streak);
                    });
                  }),
                  _buildSlot('Right', _rightSlot, (streak) {
                    setState(() {
                      if (_rightSlot != null) _available.add(_rightSlot!);
                      _rightSlot = streak;
                      _available.remove(streak);
                    });
                  }),
                ],
              ),
            ),
            
            const SizedBox(height: 24),
            
            // Divider
            Divider(color: Colors.grey[300], thickness: 1),
            
            // Available Buddies Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  Text(
                    'Available Buddies',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey[800],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.blue[100],
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${_filteredStreaks.length}',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Colors.blue[700],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            
            // Available Buddies List
            Expanded(
              child: _filteredStreaks.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            _searchQuery.isEmpty ? Icons.check_circle : Icons.search_off,
                            size: 64,
                            color: Colors.grey[400],
                          ),
                          const SizedBox(height: 16),
                          Text(
                            _searchQuery.isEmpty
                                ? 'All buddies assigned!'
                                : 'No matches found',
                            style: TextStyle(
                              fontSize: 16,
                              color: Colors.grey[600],
                            ),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: _filteredStreaks.length,
                      itemBuilder: (context, index) {
                        final streak = _filteredStreaks[index];
                        return _buildBuddyCard(streak);
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildSlot(String label, TeamStreak? streak, Function(TeamStreak) onAccept) {
    return Column(
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey[600],
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        DragTarget<TeamStreak>(
          onAccept: onAccept,
          builder: (context, candidateData, rejectedData) {
            final isHighlighted = candidateData.isNotEmpty;
            
            return Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: isHighlighted ? Colors.blue[100] : Colors.grey[200],
                shape: BoxShape.circle,
                border: Border.all(
                  color: isHighlighted ? Colors.blue[400]! : Colors.grey[400]!,
                  width: 2,
                ),
              ),
              child: streak != null
                  ? Stack(
                      children: [
                        // ✅ Show actual user avatar!
                        Center(
                          child: ClipOval(
                            child: UserAvatar(
                              avatarId: _getFriendAvatar(streak),
                              size: 70,
                            ),
                          ),
                        ),
                        // Remove button
                        Positioned(
                          top: 0,
                          right: 0,
                          child: GestureDetector(
                            onTap: () {
                              setState(() {
                                _available.add(streak);
                                if (label == 'Left') _leftSlot = null;
                                if (label == 'Center') _centerSlot = null;
                                if (label == 'Right') _rightSlot = null;
                              });
                            },
                            child: Container(
                              padding: const EdgeInsets.all(2),
                              decoration: const BoxDecoration(
                                color: Colors.red,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.close,
                                color: Colors.white,
                                size: 16,
                              ),
                            ),
                          ),
                        ),
                      ],
                    )
                  : Icon(
                      Icons.add,
                      color: Colors.grey[400],
                      size: 32,
                    ),
            );
          },
        ),
      ],
    );
  }
  
  Widget _buildBuddyCard(TeamStreak streak) {
    return Draggable<TeamStreak>(
      data: streak,
      feedback: Material(
        elevation: 8,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Container(
          width: 250,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ClipOval(
                child: UserAvatar(
                  avatarId: _getFriendAvatar(streak),
                  size: 40,
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _getFriendName(streak),
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    '${streak.currentStreak} day streak',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      childWhenDragging: Opacity(
        opacity: 0.3,
        child: _buildCardContent(streak),
      ),
      child: _buildCardContent(streak),
    );
  }
  
  Widget _buildCardContent(TeamStreak streak) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        leading: ClipOval(
          child: UserAvatar(
            avatarId: _getFriendAvatar(streak),
            size: 40,
          ),
        ),
        title: Text(
          _getFriendName(streak),
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text('${streak.currentStreak} day streak'),
        trailing: const Icon(Icons.drag_indicator),
      ),
    );
  }
}