import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../data/avatar_catalog.dart';
import '../../theme/app_theme.dart';
import 'wardrobe_avatar_render.dart';
import 'wardrobe_avatar_screen.dart';
import 'wardrobe_border_screen.dart';
import 'wardrobe_preview_header.dart';
import 'wardrobe_ring_screen.dart';
import 'wardrobe_selection_state.dart';

class WardrobeHubScreen extends StatefulWidget {
  const WardrobeHubScreen({super.key});

  @override
  State<WardrobeHubScreen> createState() => _WardrobeHubScreenState();
}

class _WardrobeHubScreenState extends State<WardrobeHubScreen> {
  bool _saving = false;

  Future<void> _save() async {
    final state = context.read<WardrobeSelectionState>();
    setState(() => _saving = true);
    try {
      await state.save();
      if (mounted) Navigator.of(context, rootNavigator: true).pop(true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to save — please try again')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<WardrobeSelectionState>();
    final appColors = AppColors.of(context);
    final avatar = avatarCatalogById(state.avatarId);
    final ringName = state.ringItem?.name.replaceAll(' Ring', '') ?? 'Default';

    return Scaffold(
      backgroundColor: appColors.sectionBackground,
      appBar: AppBar(
        title: const Text('Wardrobe'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context, rootNavigator: true).pop(false),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
        children: [
          const WardrobePreviewHeader(),
          const SizedBox(height: 8),
          _row(
            context,
            label: 'Avatar',
            value: avatar.name,
            onTap: () => Navigator.of(context)
                .push(MaterialPageRoute(builder: (_) => const WardrobeAvatarScreen())),
          ),
          const SizedBox(height: 12),
          _row(
            context,
            label: 'Border',
            value: borderStyleLabel(state.border),
            onTap: () => Navigator.of(context)
                .push(MaterialPageRoute(builder: (_) => const WardrobeBorderScreen())),
          ),
          const SizedBox(height: 12),
          _row(
            context,
            label: 'Ring colour',
            value: ringName,
            onTap: () => Navigator.of(context)
                .push(MaterialPageRoute(builder: (_) => const WardrobeRingScreen())),
          ),
          const SizedBox(height: 28),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: (!state.isDirty || _saving) ? null : _save,
              style: ElevatedButton.styleFrom(
                backgroundColor: appColors.streakOrange,
                foregroundColor: appColors.readableForeground(appColors.streakOrange),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                elevation: 0,
              ),
              child: _saving
                  ? SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: appColors.readableForeground(appColors.streakOrange),
                      ),
                    )
                  : const Text('Save changes',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _row(
    BuildContext context, {
    required String label,
    required String value,
    required VoidCallback onTap,
  }) {
    final appColors = AppColors.of(context);
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: appColors.cardBackground,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: appColors.cardBorder),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
              ),
            ),
            Text(value, style: TextStyle(fontSize: 14, color: appColors.subtleText)),
            const SizedBox(width: 6),
            Icon(Icons.chevron_right, color: appColors.subtleText),
          ],
        ),
      ),
    );
  }
}
