import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'dart:math' as math;
import 'onboarding_fitness_goals.dart';

class OnboardingAvatarSelection extends StatefulWidget {
  final Map<String, dynamic> userData;
  
  const OnboardingAvatarSelection({
    super.key,
    required this.userData,
  });

  @override
  State<OnboardingAvatarSelection> createState() => _OnboardingAvatarSelectionState();
}

class _OnboardingAvatarSelectionState extends State<OnboardingAvatarSelection> {
  final PageController _pageController = PageController(
    viewportFraction: 0.25,
    initialPage: 500 * 11, // Start at Lion (500 * 11 wraps to index 0)
  );
  final ImagePicker _picker = ImagePicker();
  
  int _currentAvatarIndex = 0;
  File? _selectedImage;
  bool _useCustomImage = false;
  
  // Avatar emojis that will scroll infinitely
  final List<Map<String, String>> _avatars = [
    {'id': 'lion', 'emoji': '🦁', 'name': 'Lion'},
    {'id': 'bear', 'emoji': '🐻', 'name': 'Bear'},
    {'id': 'eagle', 'emoji': '🦅', 'name': 'Eagle'},
    {'id': 'shark', 'emoji': '🦈', 'name': 'Shark'},
    {'id': 'wolf', 'emoji': '🐺', 'name': 'Wolf'},
    {'id': 'gorilla', 'emoji': '🦍', 'name': 'Gorilla'},
    {'id': 'buffalo', 'emoji': '🦬', 'name': 'Buffalo'},
    {'id': 'robot', 'emoji': '🤖', 'name': 'Robot'},
    {'id': 'flexed', 'emoji': '💪', 'name': 'Strength'},
    {'id': 'weightlifter', 'emoji': '🏋️', 'name': 'Lifter'},
    {'id': 'runner', 'emoji': '🏃', 'name': 'Runner'},
  ];

  @override
  void initState() {
    super.initState();
    _pageController.addListener(_onPageScroll);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _onPageScroll() {
    final page = _pageController.page ?? 0;
    final newIndex = page.round() % _avatars.length;
    
    if (newIndex != _currentAvatarIndex) {
      setState(() {
        _currentAvatarIndex = newIndex;
        _useCustomImage = false; // Deselect custom image when scrolling
      });
      HapticFeedback.selectionClick();
    }
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final XFile? image = await _picker.pickImage(
        source: source,
        maxWidth: 800,
        maxHeight: 800,
        imageQuality: 85,
      );
      
      if (image != null) {
        setState(() {
          _selectedImage = File(image.path);
          _useCustomImage = true;
        });
        HapticFeedback.mediumImpact();
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _showImageSourceDialog() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'Add Your Photo',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 24),
              _ImageSourceOption(
                icon: Icons.photo_library,
                label: 'Choose from Gallery',
                color: Colors.blue,
                onTap: () {
                  Navigator.pop(context);
                  _pickImage(ImageSource.gallery);
                },
              ),
              const SizedBox(height: 12),
              _ImageSourceOption(
                icon: Icons.camera_alt,
                label: 'Take a Photo',
                color: Colors.green,
                onTap: () {
                  Navigator.pop(context);
                  _pickImage(ImageSource.camera);
                },
              ),
              if (_selectedImage != null) ...[
                const SizedBox(height: 12),
                _ImageSourceOption(
                  icon: Icons.delete_outline,
                  label: 'Remove Photo',
                  color: Colors.red,
                  onTap: () {
                    setState(() {
                      _selectedImage = null;
                      _useCustomImage = false;
                    });
                    Navigator.pop(context);
                  },
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  void _nextPage() {
    // Save avatar selection to userData
    if (_useCustomImage && _selectedImage != null) {
      widget.userData['custom_image'] = _selectedImage;
      widget.userData['avatar_id'] = null;
    } else {
      widget.userData['avatar_id'] = _avatars[_currentAvatarIndex]['id'];
      widget.userData['custom_image'] = null;
    }

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => OnboardingFitnessGoals(userData: widget.userData),
      ),
    );
  }

  void _previousPage() {
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            // Progress indicator
            Padding(
              padding: const EdgeInsets.all(24.0),
              child: LinearProgressIndicator(
                value: 0.4, // 40% through onboarding
                backgroundColor: Colors.grey[300],
                valueColor: AlwaysStoppedAnimation<Color>(
                  Theme.of(context).colorScheme.primary,
                ),
              ),
            ),
            
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  children: [
                    const SizedBox(height: 20),
                    
                    // Title
                    const Text(
                      'Choose Your Avatar',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Pick an avatar or upload your own photo',
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.grey[600],
                      ),
                      textAlign: TextAlign.center,
                    ),
                    
                    const SizedBox(height: 48),
                    
                    // Upload Photo Card (top center)
                    GestureDetector(
                      onTap: _showImageSourceDialog,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        width: 140,
                        height: 140,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: _useCustomImage && _selectedImage != null
                              ? null
                              : LinearGradient(
                                  colors: [Colors.blue[400]!, Colors.purple[400]!],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                          border: Border.all(
                            color: _useCustomImage 
                                ? Colors.green 
                                : Colors.grey[300]!,
                            width: _useCustomImage ? 4 : 2,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: (_useCustomImage ? Colors.green : Colors.blue)
                                  .withOpacity(0.3),
                              blurRadius: 20,
                              spreadRadius: _useCustomImage ? 5 : 2,
                            ),
                          ],
                        ),
                        child: _selectedImage != null
                            ? ClipOval(
                                child: Stack(
                                  fit: StackFit.expand,
                                  children: [
                                    Image.file(
                                      _selectedImage!,
                                      fit: BoxFit.cover,
                                    ),
                                    if (_useCustomImage)
                                      Positioned(
                                        top: 8,
                                        right: 8,
                                        child: Container(
                                          padding: const EdgeInsets.all(4),
                                          decoration: const BoxDecoration(
                                            color: Colors.green,
                                            shape: BoxShape.circle,
                                          ),
                                          child: const Icon(
                                            Icons.check,
                                            color: Colors.white,
                                            size: 20,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              )
                            : Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.add_a_photo,
                                    size: 40,
                                    color: Colors.white,
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'Upload\nPhoto',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                      ),
                    ),
                    
                    const SizedBox(height: 40),
                    
                    // "Or" divider
                    Row(
                      children: [
                        Expanded(child: Divider(color: Colors.grey[400])),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Text(
                            'OR',
                            style: TextStyle(
                              color: Colors.grey[600],
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        Expanded(child: Divider(color: Colors.grey[400])),
                      ],
                    ),
                    
                    const SizedBox(height: 40),
                    
                    // Selected avatar name
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 200),
                      child: Text(
                        _useCustomImage 
                            ? 'Custom Photo Selected'
                            : _avatars[_currentAvatarIndex]['name']!,
                        key: ValueKey(_useCustomImage ? 'custom' : _currentAvatarIndex),
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.grey[800],
                        ),
                      ),
                    ),
                    
                    const SizedBox(height: 24),
                    
                    // Horizontal scrolling carousel
                    SizedBox(
                      height: 120,
                      child: PageView.builder(
                        controller: _pageController,
                        itemCount: _avatars.length * 1000, // Infinite scroll
                        onPageChanged: (index) {
                          setState(() {
                            _useCustomImage = false;
                          });
                        },
                        itemBuilder: (context, index) {
                          final avatarIndex = index % _avatars.length;
                          final avatar = _avatars[avatarIndex];
                          
                          return AnimatedBuilder(
                            animation: _pageController,
                            builder: (context, child) {
                              double value = 1.0;
                              if (_pageController.position.haveDimensions) {
                                value = _pageController.page! - index;
                                value = (1 - (value.abs() * 0.5)).clamp(0.5, 1.0);
                              }
                              
                              final isCenter = avatarIndex == _currentAvatarIndex && !_useCustomImage;
                              
                              return Center(
                                child: Transform.scale(
                                  scale: value,
                                  child: Opacity(
                                    opacity: value,
                                    child: GestureDetector(
                                      onTap: () {
                                        _pageController.animateToPage(
                                          index,
                                          duration: const Duration(milliseconds: 300),
                                          curve: Curves.easeInOut,
                                        );
                                        setState(() {
                                          _useCustomImage = false;
                                        });
                                        HapticFeedback.selectionClick();
                                      },
                                      child: Container(
                                        width: 100,
                                        height: 100,
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: isCenter 
                                              ? Colors.blue[50]
                                              : Colors.grey[100],
                                          border: Border.all(
                                            color: isCenter 
                                                ? Colors.blue 
                                                : Colors.transparent,
                                            width: 3,
                                          ),
                                          boxShadow: isCenter
                                              ? [
                                                  BoxShadow(
                                                    color: Colors.blue.withOpacity(0.3),
                                                    blurRadius: 15,
                                                    spreadRadius: 2,
                                                  ),
                                                ]
                                              : [],
                                        ),
                                        child: Center(
                                          child: Text(
                                            avatar['emoji']!,
                                            style: TextStyle(
                                              fontSize: isCenter ? 50 : 40,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            },
                          );
                        },
                      ),
                    ),
                    
                    const SizedBox(height: 24),
                    
                    // Scroll hint
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.swipe, size: 16, color: Colors.grey[500]),
                        const SizedBox(width: 8),
                        Text(
                          'Swipe to browse avatars',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[500],
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ],
                    ),
                    
                    const SizedBox(height: 60),
                  ],
                ),
              ),
            ),
            
            // Navigation buttons
            Padding(
              padding: const EdgeInsets.all(24.0),
              child: Row(
                children: [
                  TextButton(
                    onPressed: _previousPage,
                    child: const Text('Back'),
                  ),
                  const Spacer(),
                  ElevatedButton(
                    onPressed: _nextPage,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 32,
                        vertical: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('Next'),
                        SizedBox(width: 8),
                        Icon(Icons.arrow_forward, size: 18),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Helper widget for image source options
class _ImageSourceOption extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _ImageSourceOption({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey[300]!),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: color, size: 24),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey[400]),
            ],
          ),
        ),
      ),
    );
  }
}
