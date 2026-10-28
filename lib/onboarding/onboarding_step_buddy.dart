import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../services/invite_service.dart';
import '../theme/app_theme.dart';
import '../utils/debug_logger.dart';
import 'onboarding_account.dart';
import 'onboarding_draft.dart';
import 'onboarding_host.dart';
import 'onboarding_max.dart';
import 'onboarding_theme.dart';

/// Step 5: who to start with. The CTA writes the whole profile (the one
/// profile write of the flow), then either shares an invite link or leaves
/// Coach Max as the buddy; Coach Max is set up for everyone either way.
class BuddyStep extends StatefulWidget {
  const BuddyStep({super.key});

  @override
  State<BuddyStep> createState() => _BuddyStepState();
}

class _BuddyStepState extends State<BuddyStep> {
  bool _busy = false;

  Future<void> _share() async {
    try {
      final link = await InviteService().createInviteLink();
      if (link == null) {
        _toast('Could not create an invite link. You can send one from Friends any time.');
        return;
      }
      await SharePlus.instance.share(ShareParams(
        text:
            "Join me on Gym Buddy! We'll keep each other accountable and build streaks together.\n\n$link",
        subject: 'Join me on Gym Buddy!',
      ));
    } catch (e) {
      debugLog('Onboarding invite share failed: $e');
      _toast('Could not open the share sheet. You can send an invite from Friends any time.');
    }
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message),
      behavior: SnackBarBehavior.floating,
    ));
  }

  Future<void> _continue() async {
    if (_busy) return;
    final host = OnbScope.of(context);
    final c = AppColors.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      await saveOnboardingProfile(
        host.draft,
        pendingInvites: host.widget.pendingInvites,
        messenger: messenger,
        successColor: c.success,
        warnColor: c.warn,
      );
    } catch (e) {
      debugLog('Onboarding profile save failed: $e');
      messenger.showSnackBar(SnackBar(
          content: const Text('Could not save profile. Please try again.'),
          backgroundColor: c.danger));
      if (mounted) setState(() => _busy = false);
      return;
    }
    if (host.draft.buddy == BuddyChoice.invite) await _share();
    if (!mounted) return;
    setState(() => _busy = false);
    host.go(5);
  }

  @override
  Widget build(BuildContext context) {
    final host = OnbScope.of(context);
    final draft = host.draft;
    final c = AppColors.of(context);
    final cs = Theme.of(context).colorScheme;
    final invite = draft.buddy == BuddyChoice.invite;
    return OnbStepFrame(
      footer: ObPrimaryButton(
        label: invite ? 'Send invite link' : 'Start with Coach Max',
        isLoading: _busy,
        onTap: _continue,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          MaxStrip(
            anchor: host.anchors[MaxSpot.buddy]!,
            spot: MaxSpot.buddy,
            text:
                "That's me. I'm an AI, so I never miss a day. Invite a friend any time.",
            bubbleVisible: host.bubbleVisible,
          ),
          const SizedBox(height: 20),
          Semantics(
            header: true,
            child: Text("Who's your buddy?",
                style: TextStyle(
                    fontSize: 30, fontWeight: FontWeight.w800, color: cs.onSurface)),
          ),
          const SizedBox(height: 18),
          _BuddyCard(
            title: 'Invite a friend',
            body: 'Send a link. Your streak starts when they join.',
            selected: invite,
            onTap: () => setState(() => draft.buddy = BuddyChoice.invite),
          ),
          const SizedBox(height: 12),
          _BuddyCard(
            title: 'Coach Max',
            body: 'Always on, never misses a day.',
            ai: true,
            selected: !invite,
            onTap: () => setState(() => draft.buddy = BuddyChoice.coachMax),
          ),
          const SizedBox(height: 14),
          Text(
              'Coach Max is an AI, not a person. You can pair with a real friend any time later.',
              style: TextStyle(fontSize: 13, height: 1.35, color: c.subtleText)),
        ],
      ),
    );
  }
}

class _BuddyCard extends StatelessWidget {
  final String title;
  final String body;
  final bool ai;
  final bool selected;
  final VoidCallback onTap;
  const _BuddyCard({
    required this.title,
    required this.body,
    required this.selected,
    required this.onTap,
    this.ai = false,
  });

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final cs = Theme.of(context).colorScheme;
    final ink = Theme.of(context).scaffoldBackgroundColor;
    return Semantics(
      button: true,
      inMutuallyExclusiveGroup: true,
      checked: selected,
      label: ai ? '$title, AI. $body' : '$title. $body',
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: c.claySurface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
                color: selected ? cs.primary : c.info,
                width: selected ? 2 : 1.5),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(title,
                              style: TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w700,
                                  color: cs.onSurface)),
                        ),
                        if (ai) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                                color: c.aqua,
                                borderRadius: BorderRadius.circular(8)),
                            child: Text('AI',
                                textScaler: TextScaler.noScaling,
                                style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 0.8,
                                    color: ink)),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(body,
                        style: TextStyle(fontSize: 14, color: c.subtleText)),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                      color: selected ? cs.primary : c.info, width: 2),
                ),
                child: selected
                    ? Center(
                        child: Container(
                          width: 12,
                          height: 12,
                          decoration: BoxDecoration(
                              shape: BoxShape.circle, color: cs.primary),
                        ),
                      )
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
