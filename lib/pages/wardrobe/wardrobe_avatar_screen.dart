import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import 'wardrobe_avatar_wheel.dart';
import 'wardrobe_preview_header.dart';

class WardrobeAvatarScreen extends StatelessWidget {
  const WardrobeAvatarScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final appColors = AppColors.of(context);

    return Scaffold(
      backgroundColor: appColors.sectionBackground,
      appBar: AppBar(title: const Text('Avatar')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
        children: const [
          WardrobePreviewHeader(),
          SizedBox(height: 16),
          WardrobeAvatarWheel(),
        ],
      ),
    );
  }
}
