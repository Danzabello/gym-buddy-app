import 'package:app_settings/app_settings.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';

import '../onboarding/onboarding_theme.dart' show ObPrimaryButton;
import '../services/notification_service.dart';
import '../theme/app_theme.dart';
import '../utils/run_once.dart';

typedef AskPermission = Future<AuthorizationStatus?> Function();

/// A dot on the bell only when the permission is known to be off; unknown
/// (not checked yet) shows nothing, so it never flickers on.
bool bellDotVisible(bool? osPermission) => osPermission == false;

enum BellTap { snackbar, sheet }

/// A granted permission, or a check that throws, keeps the bell's plain
/// snackbar; only a known "not granted" opens the sheet.
Future<BellTap> routeBellTap(Future<bool> Function() check) async {
  try {
    return await check() ? BellTap.snackbar : BellTap.sheet;
  } catch (_) {
    return BellTap.snackbar;
  }
}

/// Android answers at once, without a dialog, when the permission was denied
/// for good; the only way forward is the system settings page. The same rule
/// lives in notification_settings_page.dart (_enableNotifications).
bool dialogWasBlocked(Duration elapsed, AuthorizationStatus? status) =>
    elapsed < const Duration(milliseconds: 400) &&
    status != null &&
    status != AuthorizationStatus.authorized;

/// Opens the sheet. Closing it any way other than the main button writes
/// nothing and never asks.
Future<void> showNotificationPromptSheet(
  BuildContext context, {
  AskPermission? ask,
  Future<void> Function()? openSettings,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (_) => NotificationPromptSheet(
      ask: ask ?? NotificationService().requestPermissionFromUser,
      openSettings: openSettings ??
          () => AppSettings.openAppSettings(type: AppSettingsType.notification),
    ),
  );
}

class NotificationPromptSheet extends StatefulWidget {
  final AskPermission ask;
  final Future<void> Function() openSettings;
  const NotificationPromptSheet(
      {super.key, required this.ask, required this.openSettings});

  @override
  State<NotificationPromptSheet> createState() =>
      _NotificationPromptSheetState();
}

class _NotificationPromptSheetState extends State<NotificationPromptSheet> {
  final _once = RunOnce();
  bool _busy = false;

  @override
  void dispose() {
    _once.dispose();
    super.dispose();
  }

  Future<void> _turnOn() => _once.run(() async {
        final nav = Navigator.of(context);
        setState(() => _busy = true);
        final started = DateTime.now();
        final status = await widget.ask();
        if (dialogWasBlocked(DateTime.now().difference(started), status)) {
          await widget.openSettings();
        }
        if (mounted) nav.pop();
      });

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final cs = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: c.claySurface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        border: Border(top: BorderSide(color: c.claySurfaceLight, width: 1.5)),
      ),
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
            24, 12, 24, MediaQuery.of(context).padding.bottom + 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                  color: c.divider, borderRadius: BorderRadius.circular(2)),
            ),
            const SizedBox(height: 20),
            ExcludeSemantics(
              child: Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: c.claySurface,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    ...c.clayShadow(),
                    BoxShadow(
                        color: c.warn.withValues(alpha: 0.3),
                        blurRadius: 24,
                        spreadRadius: 1),
                  ],
                ),
                // The onboarding bell painter is file-private, so the stock
                // icon stands in.
                child: Icon(Icons.notifications_active_rounded,
                    size: 38, color: c.warn),
              ),
            ),
            const SizedBox(height: 20),
            Semantics(
              header: true,
              child: Text('Keep your streak alive',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      color: cs.onSurface)),
            ),
            const SizedBox(height: 12),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 320),
              child: Text(
                'Turn on notifications so Gym Buddy can reach you at the right moments. You pick which kinds in Settings.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 15, height: 1.4, color: c.subtleText),
              ),
            ),
            const SizedBox(height: 20),
            ObPrimaryButton(
              label: 'Turn on notifications',
              isLoading: _busy,
              onTap: _turnOn,
            ),
            const SizedBox(height: 4),
            SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed: _busy ? null : () => Navigator.of(context).pop(),
                style: TextButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                    foregroundColor: c.subtleText),
                child: const Text('Not now',
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              ),
            ),
            const SizedBox(height: 4),
            Text('You can change this any time in Settings.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: c.subtleText)),
          ],
        ),
      ),
    );
  }
}
