import 'package:flutter/material.dart';

import '../data/avatar_catalog.dart';
import '../theme/app_theme.dart';
import '../widgets/user_avatar.dart';
import 'onboarding_host.dart';
import 'onboarding_max.dart';
import 'onboarding_theme.dart';

/// The starter avatars, in the order the picker row shows them.
const _kStarterIds = ['wolf', 'bear', 'lion'];

/// Step 2: pick the starter avatar. The choice stays in the draft.
class AvatarStep extends StatefulWidget {
  const AvatarStep({super.key});

  @override
  State<AvatarStep> createState() => _AvatarStepState();
}

class _AvatarStepState extends State<AvatarStep> {
  @override
  Widget build(BuildContext context) {
    final host = OnbScope.of(context);
    final draft = host.draft;
    final c = AppColors.of(context);
    final cs = Theme.of(context).colorScheme;
    final chosen = avatarCatalogById(draft.avatarId);
    return OnbStepFrame(
      footer: ObPrimaryButton(
          label: 'Choose ${chosen.name}', onTap: () => host.go(2)),
      child: Column(
        children: [
          MaxStrip(
            anchor: host.anchors[MaxSpot.avatar]!,
            spot: MaxSpot.avatar,
            text: 'First, pick your avatar. ${chosen.name} is a great start.',
            bubbleVisible: host.bubbleVisible,
          ),
          const SizedBox(height: 20),
          Semantics(
            header: true,
            child: Text('Pick your buddy',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 30, fontWeight: FontWeight.w800, color: cs.onSurface)),
          ),
          const SizedBox(height: 20),
          Container(
            width: 184,
            height: 184,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: c.claySurface,
              border: Border.all(color: cs.primary, width: 4),
            ),
            child: Center(
              child: UserAvatar(
                avatarId: chosen.id,
                size: 150,
                animated: true,
                bare: true,
                semanticLabel: chosen.name,
              ),
            ),
          ),
          const SizedBox(height: 14),
          Text(chosen.name,
              style: TextStyle(
                  fontSize: 22, fontWeight: FontWeight.w800, color: cs.onSurface)),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: cs.primary, width: 1.5),
            ),
            child: Text('STARTER · FREE',
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1,
                    color: cs.primary)),
          ),
          const SizedBox(height: 22),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (final id in _kStarterIds) ...[
                if (id != _kStarterIds.first) const SizedBox(width: 16),
                _Option(
                  entry: avatarCatalogById(id),
                  selected: draft.avatarId == id,
                  onTap: () => setState(() => draft.avatarId = id),
                ),
              ],
            ],
          ),
          const SizedBox(height: 12),
          Text('Unlock more as you level up',
              style: TextStyle(fontSize: 13, color: c.subtleText)),
        ],
      ),
    );
  }
}

class _Option extends StatelessWidget {
  final AvatarCatalogEntry entry;
  final bool selected;
  final VoidCallback onTap;
  const _Option(
      {required this.entry, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final cs = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      inMutuallyExclusiveGroup: true,
      selected: selected,
      label: entry.name,
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: c.claySurface,
            border: selected
                ? Border.all(color: cs.primary, width: 3)
                : Border.all(color: c.info, width: 1.5),
          ),
          child: Center(
              child: UserAvatar(avatarId: entry.id, size: 52, bare: true)),
        ),
      ),
    );
  }
}
