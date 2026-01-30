import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';

/// Compact avatar selector with expandable grid and image upload
class AvatarSelector extends StatefulWidget {
  final String? selectedAvatarId;
  final File? selectedImage;
  final Function(String) onAvatarSelected;
  final Function(File)? onImageSelected;
  
  const AvatarSelector({
    super.key,
    this.selectedAvatarId,
    this.selectedImage,
    required this.onAvatarSelected,
    this.onImageSelected,
  });

  @override
  State<AvatarSelector> createState() => _AvatarSelectorState();
}

class _AvatarSelectorState extends State<AvatarSelector> with SingleTickerProviderStateMixin {
  String? _selectedAvatar;
  File? _selectedImage;
  bool _isExpanded = false;
  late AnimationController _animationController;
  late Animation<double> _rotationAnimation;
  
  final ImagePicker _picker = ImagePicker();
  
  // Available avatars
  final Map<String, Map<String, String>> avatars = {
    'lion': {'emoji': '🦁', 'name': 'Lion'},
    'bear': {'emoji': '🐻', 'name': 'Bear'},
    'eagle': {'emoji': '🦅', 'name': 'Eagle'},
    'shark': {'emoji': '🦈', 'name': 'Shark'},
    'wolf': {'emoji': '🐺', 'name': 'Wolf'},
    'gorilla': {'emoji': '🦍', 'name': 'Gorilla'},
    'tiger': {'emoji': '🐯', 'name': 'Tiger'},
    'buffalo': {'emoji': '🦬', 'name': 'Buffalo'},
    'robot': {'emoji': '🤖', 'name': 'Robot'},
    'flexed': {'emoji': '💪', 'name': 'Strength'},
    'weightlifter': {'emoji': '🏋️', 'name': 'Lifter'},
    'runner': {'emoji': '🏃', 'name': 'Runner'},
  };
  
  @override
  void initState() {
    super.initState();
    _selectedAvatar = widget.selectedAvatarId ?? 'lion';
    _selectedImage = widget.selectedImage;
    
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    
    _rotationAnimation = Tween<double>(begin: 0, end: 0.5).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );
  }
  
  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }
  
  Future<void> _pickImageFromGallery() async {
    try {
      final XFile? image = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 800,
        maxHeight: 800,
        imageQuality: 85,
      );
      
      if (image != null) {
        final File imageFile = File(image.path);
        setState(() {
          _selectedImage = imageFile;
          _selectedAvatar = null; // Clear emoji selection
        });
        
        if (widget.onImageSelected != null) {
          widget.onImageSelected!(imageFile);
        }
        
        HapticFeedback.mediumImpact();
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error picking image: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
  
  Future<void> _pickImageFromCamera() async {
    try {
      final XFile? image = await _picker.pickImage(
        source: ImageSource.camera,
        maxWidth: 800,
        maxHeight: 800,
        imageQuality: 85,
      );
      
      if (image != null) {
        final File imageFile = File(image.path);
        setState(() {
          _selectedImage = imageFile;
          _selectedAvatar = null;
        });
        
        if (widget.onImageSelected != null) {
          widget.onImageSelected!(imageFile);
        }
        
        HapticFeedback.mediumImpact();
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error taking photo: $e'),
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
              const Text(
                'Choose Photo Source',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 20),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.blue[50],
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.photo_library, color: Colors.blue[700]),
                ),
                title: const Text('Choose from Gallery'),
                onTap: () {
                  Navigator.pop(context);
                  _pickImageFromGallery();
                },
              ),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.green[50],
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.camera_alt, color: Colors.green[700]),
                ),
                title: const Text('Take a Photo'),
                onTap: () {
                  Navigator.pop(context);
                  _pickImageFromCamera();
                },
              ),
              if (_selectedImage != null)
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.red[50],
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.delete, color: Colors.red[700]),
                  ),
                  title: const Text('Remove Photo'),
                  onTap: () {
                    setState(() {
                      _selectedImage = null;
                      _selectedAvatar = 'lion';
                    });
                    widget.onAvatarSelected('lion');
                    Navigator.pop(context);
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }
  
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey[300]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Choose Your Avatar',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              RotationTransition(
                turns: _rotationAnimation,
                child: IconButton(
                  icon: Icon(
                    Icons.keyboard_arrow_down,
                    color: Colors.grey[700],
                  ),
                  onPressed: () {
                    setState(() {
                      _isExpanded = !_isExpanded;
                      if (_isExpanded) {
                        _animationController.forward();
                      } else {
                        _animationController.reverse();
                      }
                    });
                    HapticFeedback.selectionClick();
                  },
                ),
              ),
            ],
          ),
          
          const SizedBox(height: 12),
          
          // Current selection preview
          Row(
            children: [
              // Avatar preview
              GestureDetector(
                onTap: () {
                  setState(() {
                    _isExpanded = !_isExpanded;
                    if (_isExpanded) {
                      _animationController.forward();
                    } else {
                      _animationController.reverse();
                    }
                  });
                  HapticFeedback.selectionClick();
                },
                child: Container(
                  width: 70,
                  height: 70,
                  decoration: BoxDecoration(
                    color: Colors.blue[50],
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.blue, width: 3),
                  ),
                  child: _selectedImage != null
                      ? ClipOval(
                          child: Image.file(
                            _selectedImage!,
                            fit: BoxFit.cover,
                          ),
                        )
                      : Center(
                          child: Text(
                            avatars[_selectedAvatar]!['emoji']!,
                            style: const TextStyle(fontSize: 40),
                          ),
                        ),
                ),
              ),
              
              const SizedBox(width: 16),
              
              // Upload photo button
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _showImageSourceDialog,
                  icon: const Icon(Icons.camera_alt),
                  label: const Text('Upload Photo'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    side: BorderSide(color: Colors.grey[400]!),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ],
          ),
          
          // Expandable avatar grid
          AnimatedSize(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
            child: _isExpanded
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 16),
                      const Divider(),
                      const SizedBox(height: 12),
                      const Text(
                        'Or choose an emoji avatar:',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey,
                        ),
                      ),
                      const SizedBox(height: 12),
                      GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 6,
                          childAspectRatio: 1,
                          crossAxisSpacing: 8,
                          mainAxisSpacing: 8,
                        ),
                        itemCount: avatars.length,
                        itemBuilder: (context, index) {
                          final entry = avatars.entries.elementAt(index);
                          final avatarId = entry.key;
                          final avatarData = entry.value;
                          final emoji = avatarData['emoji']!;
                          final isSelected = _selectedAvatar == avatarId && _selectedImage == null;
                          
                          return GestureDetector(
                            onTap: () {
                              setState(() {
                                _selectedAvatar = avatarId;
                                _selectedImage = null; // Clear custom image
                              });
                              widget.onAvatarSelected(avatarId);
                              HapticFeedback.selectionClick();
                            },
                            child: Container(
                              decoration: BoxDecoration(
                                color: isSelected ? Colors.blue[100] : Colors.white,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: isSelected ? Colors.blue : Colors.grey[300]!,
                                  width: isSelected ? 2 : 1,
                                ),
                              ),
                              child: Center(
                                child: Text(
                                  emoji,
                                  style: const TextStyle(fontSize: 28),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ],
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}