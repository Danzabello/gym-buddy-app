import 'package:flutter/material.dart';
import '../services/coach_max_service.dart';
import 'dart:async';

class CoachMaxWidget extends StatefulWidget {
  final int currentStreak;
  final bool hasCheckedInToday;
  final bool showSpeechBubble;
  
  const CoachMaxWidget({
    super.key,
    required this.currentStreak,
    required this.hasCheckedInToday,
    this.showSpeechBubble = true,
  });

  @override
  State<CoachMaxWidget> createState() => _CoachMaxWidgetState();
}

class _CoachMaxWidgetState extends State<CoachMaxWidget> with SingleTickerProviderStateMixin {
  final CoachMaxService _coachMaxService = CoachMaxService();
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  String? _fullMessage;
  String _displayedMessage = '';
  bool _isTyping = false;

  @override
  void initState() {
    super.initState();
    
    // Generate random motivational message (mix all personalities)
    _fullMessage = _coachMaxService.getMotivationalMessage(
      currentStreak: widget.currentStreak,
      hasCheckedInToday: widget.hasCheckedInToday,
      messageType: null, // null = random mix of all personalities
    );
    
    // Setup pulse animation for the avatar (breathing effect)
    _pulseController = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    )..repeat(reverse: true);
    
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.1).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    
    // Start typing animation
    if (widget.showSpeechBubble && _fullMessage != null) {
      _startTypingAnimation();
    }
  }

  void _startTypingAnimation() async {
    setState(() {
      _isTyping = true;
      _displayedMessage = '';
    });

    // Convert string to runes (handles emojis properly)
    final runes = _fullMessage!.runes.toList();
    
    // Type out the message rune by rune (character by character, emoji-safe)
    for (int i = 0; i < runes.length; i++) {
      if (!mounted) return;
      
      await Future.delayed(const Duration(milliseconds: 30)); // Typing speed
      
      if (!mounted) return;
      setState(() {
        // Build string from runes up to current position
        _displayedMessage = String.fromCharCodes(runes.sublist(0, i + 1));
      });
    }

    setState(() {
      _isTyping = false;
    });
  }

  void _regenerateMessage() {
    // Generate a new random message
    _fullMessage = _coachMaxService.getMotivationalMessage(
      currentStreak: widget.currentStreak,
      hasCheckedInToday: widget.hasCheckedInToday,
      messageType: null, // Random from all personalities
    );
    _startTypingAnimation();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Colors.blue[50]!,
              Colors.purple[50]!,
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          children: [
            // Header
            Row(
              children: [
                // Animated Avatar (breathing effect)
                ScaleTransition(
                  scale: _pulseAnimation,
                  child: Container(
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        colors: [
                          Colors.blue[400]!,
                          Colors.purple[400]!,
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.blue.withOpacity(0.3),
                          blurRadius: 10,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: const Center(
                      child: Text(
                        '🤖',
                        style: TextStyle(fontSize: 32),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                
                // Coach Max Info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Text(
                            'Coach Max',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.green,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Text(
                              'AI Coach',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          if (_isTyping) ...[
                            SizedBox(
                              width: 12,
                              height: 12,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  Colors.blue[400]!,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                          ],
                          Expanded(
                            child: Text(
                              _isTyping
                                  ? 'typing...'
                                  : (widget.hasCheckedInToday 
                                      ? '✅ Already trained today!'
                                      : 'Ready when you are!'),
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey[700],
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                
                // Refresh button for new quote
                IconButton(
                  icon: Icon(
                    Icons.refresh,
                    color: Colors.grey[600],
                  ),
                  tooltip: 'Get new quote',
                  onPressed: _regenerateMessage,
                ),
              ],
            ),
            
            // Speech Bubble with Typing Animation
            if (widget.showSpeechBubble && _displayedMessage.isNotEmpty) ...[
              const SizedBox(height: 16),
              _buildSpeechBubble(_displayedMessage),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSpeechBubble(String message) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Speech bubble pointer
          Row(
            children: [
              Container(
                width: 0,
                height: 0,
                decoration: const BoxDecoration(
                  border: Border(
                    right: BorderSide(
                      width: 10,
                      color: Colors.transparent,
                    ),
                    bottom: BorderSide(
                      width: 10,
                      color: Colors.white,
                    ),
                    left: BorderSide(
                      width: 10,
                      color: Colors.transparent,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          
          // Message with typing cursor
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.format_quote,
                color: Colors.blue[400],
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Text(
                        message,
                        style: TextStyle(
                          fontSize: 16,
                          color: Colors.grey[800],
                          height: 1.4,
                        ),
                      ),
                    ),
                    if (_isTyping)
                      Container(
                        width: 2,
                        height: 20,
                        margin: const EdgeInsets.only(left: 2, bottom: 2),
                        decoration: BoxDecoration(
                          color: Colors.blue[400],
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                Icons.format_quote,
                color: Colors.blue[400],
                size: 20,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// Compact version for list items
class CoachMaxAvatar extends StatelessWidget {
  final double size;
  final bool showBadge;
  
  const CoachMaxAvatar({
    super.key,
    this.size = 40,
    this.showBadge = false,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              colors: [
                Colors.blue[400]!,
                Colors.purple[400]!,
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.blue.withOpacity(0.3),
                blurRadius: 8,
                spreadRadius: 1,
              ),
            ],
          ),
          child: Center(
            child: Text(
              '🤖',
              style: TextStyle(fontSize: size * 0.6),
            ),
          ),
        ),
        if (showBadge)
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                color: Colors.green,
                shape: BoxShape.circle,
                border: Border.all(
                  color: Colors.white,
                  width: 2,
                ),
              ),
              child: const Icon(
                Icons.check,
                color: Colors.white,
                size: 12,
              ),
            ),
          ),
      ],
    );
  }
}