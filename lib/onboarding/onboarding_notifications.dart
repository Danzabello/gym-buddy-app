import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/notification_service.dart';
import '../theme/app_theme.dart';
import 'onboarding_theme.dart';

String _seenKey() =>
    'notif_rationale_seen_${Supabase.instance.client.auth.currentUser?.id}';

Future<bool> notificationRationaleSeen() async {
  try {
    return (await SharedPreferences.getInstance()).getBool(_seenKey()) ?? false;
  } catch (_) {
    return false;
  }
}

/// Last onboarding step. Never reachable from login or app start.
class OnboardingNotifications extends StatefulWidget {
  final VoidCallback onContinue;
  const OnboardingNotifications({super.key, required this.onContinue});

  @override
  State<OnboardingNotifications> createState() =>
      _OnboardingNotificationsState();
}

class _OnboardingNotificationsState extends State<OnboardingNotifications> {
  bool _busy = false;

  Future<void> _finish({required bool ask}) async {
    if (_busy) return;
    setState(() => _busy = true);
    if (ask) await NotificationService().requestPermissionFromUser();
    try {
      await (await SharedPreferences.getInstance()).setBool(_seenKey(), true);
    } catch (_) {}
    if (mounted) widget.onContinue();
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 32, 24, 16),
                child: Column(
                  children: [
                    ExcludeSemantics(
                      child: Container(
                        width: 104,
                        height: 104,
                        decoration: BoxDecoration(
                          color: c.claySurface,
                          borderRadius: BorderRadius.circular(32),
                          boxShadow: [
                            BoxShadow(
                                color: c.clayShadowDark,
                                blurRadius: 18,
                                offset: const Offset(0, 8)),
                          ],
                        ),
                        child: Icon(Icons.notifications_none_rounded,
                            size: 52, color: cs.primary),
                      ),
                    ),
                    const SizedBox(height: 24),
                    Semantics(
                      header: true,
                      child: Text('Keep your streak alive',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.w700,
                              color: cs.onSurface)),
                    ),
                    const SizedBox(height: 12),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 320),
                      child: Text(
                        'Turn on notifications so Gym Buddy can reach you at the right moments. You pick which kinds in Settings.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: 16, height: 1.4, color: c.subtleText),
                      ),
                    ),
                    const SizedBox(height: 28),
                    const _Row(Icons.people_outline, 'Buddy check-ins',
                        'Know when your buddy has trained today.'),
                    const SizedBox(height: 12),
                    const _Row(Icons.local_fire_department_outlined,
                        'Streak at risk', 'A heads-up before the day resets.'),
                    const SizedBox(height: 12),
                    const _Row(Icons.alarm_outlined, 'Workout reminders',
                        'Reminders for sessions you plan with your buddy.'),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ObPrimaryButton(
                    label: 'Turn on notifications',
                    isLoading: _busy,
                    onTap: () => _finish(ask: true),
                  ),
                  const SizedBox(height: 4),
                  SizedBox(
                    width: double.infinity,
                    child: TextButton(
                      onPressed: _busy ? null : () => _finish(ask: false),
                      style: TextButton.styleFrom(
                          minimumSize: const Size.fromHeight(56),
                          foregroundColor: c.subtleText),
                      child: const Text('Not now',
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w600)),
                    ),
                  ),
                  Text('You can change this any time in Settings.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 13, color: c.subtleText)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  final IconData icon;
  final String title;
  final String caption;
  const _Row(this.icon, this.title, this.caption);

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final cs = Theme.of(context).colorScheme;
    return Semantics(
      container: true,
      label: '$title. $caption',
      excludeSemantics: true,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: c.claySurface,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
                color: c.clayShadowDark,
                blurRadius: 12,
                offset: const Offset(0, 4)),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 28, color: cs.primary),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: cs.onSurface)),
                  const SizedBox(height: 2),
                  Text(caption,
                      style: TextStyle(fontSize: 14, color: c.subtleText)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
