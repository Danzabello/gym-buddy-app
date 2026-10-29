// lib/pages/notification_settings_page.dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import '../services/notification_service.dart';
import 'package:app_settings/app_settings.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import '../theme/app_theme.dart';
import '../theme/accent_theme_provider.dart';
import 'package:provider/provider.dart';
import '../utils/run_once.dart';

class NotificationSettingsPage extends StatefulWidget {
  const NotificationSettingsPage({super.key});

  @override
  State<NotificationSettingsPage> createState() =>
      _NotificationSettingsPageState();
}

class _NotificationSettingsPageState extends State<NotificationSettingsPage>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  final NotificationService _notificationService = NotificationService();

  bool _isLoading = true;
  bool _isSaving = false;
  final _once = RunOnce();
  final _saveOnce = RunOnce();
  bool _osPermissionGranted = true;

  bool _notifSocial = true;
  bool _notifWorkouts = true;
  bool _notifStreaks = true;
  bool _notifCoachMax = true;

  bool _liveCheckinBanner = true;

  bool _quietHoursEnabled = true;
  int _quietHoursStart = 23;
  int _quietHoursEnd = 7;

  /// 1 = banner fully open, 0 = collapsed.
  late final AnimationController _banner =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 350), value: 1);
  Timer? _bannerTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadSettings();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _once.dispose();
    _saveOnce.dispose();
    _bannerTimer?.cancel();
    _banner.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !_isLoading) _refreshPermission();
  }

  Future<void> _refreshPermission() async {
    final granted = await _notificationService.checkOsPermission();
    if (!mounted || granted == _osPermissionGranted) return;
    setState(() => _osPermissionGranted = granted);
    _bannerTimer?.cancel();
    if (!granted) {
      _banner.value = 1;
    } else if (MediaQuery.disableAnimationsOf(context)) {
      _banner.value = 0;
    } else {
      _bannerTimer = Timer(const Duration(milliseconds: 120), () {
        if (mounted) _banner.reverse();
      });
    }
  }

  /// Banner button, and a tap on any switch while the OS permission is off.
  Future<void> _enableNotifications() async {
    final started = DateTime.now();
    final status = await _notificationService.requestPermissionFromUser();
    if (!mounted) return;
    // Android reports only authorized/denied, never "not determined". A denial
    // that comes back at once means no dialog was shown (permanently denied),
    // so the only way forward is the system settings page.
    final instant = DateTime.now().difference(started) < const Duration(milliseconds: 400);
    if (instant && status != null && status != AuthorizationStatus.authorized) {
      await AppSettings.openAppSettings(type: AppSettingsType.notification);
    }
    await _refreshPermission();
  }

  Future<void> _loadSettings() async {
    final granted = await _notificationService.checkOsPermission();
    final settings = await _notificationService.getSettings();
    if (mounted) {
      setState(() {
        _osPermissionGranted = granted;
        _banner.value = granted ? 0 : 1;
        _notifSocial = settings['notif_social'] ?? true;
        _notifWorkouts = settings['notif_workouts'] ?? true;
        _notifStreaks = settings['notif_streaks'] ?? true;
        _notifCoachMax = settings['notif_coach_max'] ?? true;
        _liveCheckinBanner = settings['live_checkin_banner'] ?? true;
        _quietHoursEnabled = settings['quiet_hours_enabled'] ?? true;
        _quietHoursStart = settings['quiet_hours_start'] ?? 23;
        _quietHoursEnd = settings['quiet_hours_end'] ?? 7;
        _isLoading = false;
      });
    }
  }

  Future<void> _saveSettings() async {
    setState(() => _isSaving = true);
    await _notificationService.updateSettings({
      'notif_social': _notifSocial,
      'notif_workouts': _notifWorkouts,
      'notif_streaks': _notifStreaks,
      'notif_coach_max': _notifCoachMax,
      'live_checkin_banner': _liveCheckinBanner,
      'quiet_hours_enabled': _quietHoursEnabled,
      'quiet_hours_start': _quietHoursStart,
      'quiet_hours_end': _quietHoursEnd,
    });
    if (mounted) {
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Row(children: [
            Icon(Icons.check_circle, color: Colors.white),
            SizedBox(width: 12),
            Text('Notification settings saved!'),
          ]),
          backgroundColor: AppColors.of(context).successGreen,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  String _formatHour(int hour) {
    if (hour == 0) return '12:00 AM';
    if (hour == 12) return '12:00 PM';
    if (hour < 12) return '$hour:00 AM';
    return '${hour - 12}:00 PM';
  }

  Future<void> _showHourPicker(bool isStart) {
    int tempHour = isStart ? _quietHoursStart : _quietHoursEnd;
    final appColors = AppColors.of(context);
    final cs = Theme.of(context).colorScheme;

    return showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        height: 300,
        decoration: BoxDecoration(
          color: appColors.cardBackground,
          borderRadius:
              const BorderRadius.vertical(top: Radius.circular(20)),
          border: Border.all(color: appColors.cardBorder, width: 0.5),
        ),
        child: Column(children: [
          // Handle
          Container(
            width: 36,
            height: 4,
            margin: const EdgeInsets.only(top: 10, bottom: 4),
            decoration: BoxDecoration(
              color: appColors.divider,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          // Header row
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text('Cancel',
                      style: TextStyle(color: appColors.subtleText)),
                ),
                Text(
                  isStart ? 'Start Time' : 'End Time',
                  style: TextStyle(
                      color: cs.onSurface,
                      fontSize: 15,
                      fontWeight: FontWeight.w700),
                ),
                TextButton(
                  onPressed: () {
                    setState(() {
                      if (isStart) {
                        _quietHoursStart = tempHour;
                      } else {
                        _quietHoursEnd = tempHour;
                      }
                    });
                    Navigator.pop(context);
                  },
                  child: Text('Done',
                      style: TextStyle(
                          color: AppColors.of(context).streakOrange,
                          fontWeight: FontWeight.w700)),
                ),
              ],
            ),
          ),
          Expanded(
            child: CupertinoPicker(
              scrollController:
                  FixedExtentScrollController(initialItem: tempHour),
              itemExtent: 44,
              onSelectedItemChanged: (index) => tempHour = index,
              children: List.generate(
                24,
                (i) => Center(
                  child: Text(
                    _formatHour(i),
                    style:
                        TextStyle(color: cs.onSurface, fontSize: 17),
                  ),
                ),
              ),
            ),
          ),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final appColors = AppColors.of(context);
    final palette = context.watch<AccentThemeProvider>().palette;
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        toolbarHeight: 72,
        leadingWidth: 72,
        leading: Padding(
          padding: const EdgeInsets.only(left: 16),
          child: Center(
            child: Semantics(
              button: true,
              label: 'Back',
              excludeSemantics: true,
              child: Material(
                color: appColors.claySurface,
                borderRadius: BorderRadius.circular(16),
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () => Navigator.pop(context),
                  child: SizedBox(
                    width: 48,
                    height: 48,
                    child: Icon(Icons.chevron_left_rounded,
                        size: 28, color: cs.onSurface),
                  ),
                ),
              ),
            ),
          ),
        ),
        title: const Text(
          'Notifications',
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
        ),
        actions: [
          if (_isSaving)
            const Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2)),
            )
          else
            TextButton(
              onPressed: () => _saveOnce.run(_saveSettings),
              child: const Text('Save',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
            ),
        ],
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator(color: cs.primary))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _buildOsPermissionBanner(appColors, cs),
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
                  child: Text('WHAT TO SEND',
                      style: TextStyle(
                          color: appColors.subtleText,
                          fontSize: 13,
                          letterSpacing: 0.8,
                          fontWeight: FontWeight.w700)),
                ),
                _buildCard([
                  _buildToggleTile(
                    icon: Icons.people_outline,
                    title: 'Buddy activity',
                    subtitle: 'Friend requests & acceptances',
                    saved: _notifSocial,
                    onSaved: (v) => setState(() => _notifSocial = v),
                    index: 0,
                  ),
                  _buildDivider(appColors),
                  _buildToggleTile(
                    icon: Icons.fitness_center,
                    title: 'Workouts',
                    subtitle: 'Invites, reminders & updates',
                    saved: _notifWorkouts,
                    onSaved: (v) => setState(() => _notifWorkouts = v),
                    index: 1,
                  ),
                  _buildDivider(appColors),
                  _buildToggleTile(
                    icon: Icons.local_fire_department_outlined,
                    title: 'Streaks',
                    subtitle: 'Check-ins, milestones & warnings',
                    saved: _notifStreaks,
                    onSaved: (v) => setState(() => _notifStreaks = v),
                    index: 2,
                  ),
                  _buildDivider(appColors),
                  _buildToggleTile(
                    icon: Icons.smart_toy_outlined,
                    title: 'Coach Max',
                    subtitle: 'Motivational messages & check-ins',
                    saved: _notifCoachMax,
                    onSaved: (v) => setState(() => _notifCoachMax = v),
                    index: 3,
                  ),
                  _buildDivider(appColors),
                  _buildToggleTile(
                    icon: Icons.bolt_outlined,
                    title: 'Live check-in banner',
                    subtitle: 'Show a banner when your buddy checks in while '
                        'you\'re on the dashboard',
                    saved: _liveCheckinBanner,
                    onSaved: (v) => setState(() => _liveCheckinBanner = v),
                    osGated: false,
                  ),
                ], appColors),

                const SizedBox(height: 16),
                _buildCard([
                  _buildToggleTile(
                    icon: Icons.bedtime_outlined,
                    title: 'Quiet hours',
                    subtitle: 'Pause notifications during set hours',
                    saved: _quietHoursEnabled,
                    onSaved: (v) => setState(() => _quietHoursEnabled = v),
                    index: 4,
                  ),
                  if (_quietHoursEnabled) ...[
                    _buildDivider(appColors),
                    _buildTimeTile(
                      icon: Icons.nights_stay_outlined,
                      title: 'Start Time',
                      subtitle: 'Notifications pause at',
                      time: _formatHour(_quietHoursStart),
                      onTap: () => _once.run(() => _showHourPicker(true)),
                      appColors: appColors,
                      cs: cs,
                    ),
                    _buildDivider(appColors),
                    _buildTimeTile(
                      icon: Icons.wb_sunny_outlined,
                      title: 'End Time',
                      subtitle: 'Notifications resume at',
                      time: _formatHour(_quietHoursEnd),
                      onTap: () => _once.run(() => _showHourPicker(false)),
                      appColors: appColors,
                      cs: cs,
                    ),
                  ],
                ], appColors),

                if (_quietHoursEnabled) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: appColors.tint(palette.statusInfo),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: palette.statusInfo.withValues(alpha: 0.2),
                          width: 0.5),
                    ),
                    child: Row(children: [
                      Icon(Icons.info_outline,
                          color: palette.statusInfo, size: 15),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Quiet hours: ${_formatHour(_quietHoursStart)} → ${_formatHour(_quietHoursEnd)}',
                          style: TextStyle(
                              color: palette.statusInfo, fontSize: 12),
                        ),
                      ),
                    ]),
                  ),
                ],

                const SizedBox(height: 28),

                // Save button
                GestureDetector(
                  onTap: _isSaving ? null : () => _saveOnce.run(_saveSettings),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    decoration: BoxDecoration(
                      color: appColors.streakOrange,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Center(
                      child: _isSaving
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white))
                          : const Text('Save Settings',
                              style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white)),
                    ),
                  ),
                ),

                const SizedBox(height: 32),
              ],
            ),
    );
  }

  Widget _buildOsPermissionBanner(AppColors appColors, ColorScheme cs) {
    return AnimatedBuilder(
      animation: _banner,
      builder: (context, _) {
        if (_banner.value == 0) return const SizedBox.shrink();
        return SizeTransition(
          sizeFactor: _banner,
          alignment: Alignment.topCenter,
          child: FadeTransition(
            opacity: _banner,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: appColors.claySurface,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: appColors.streakOrange, width: 1.5),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ExcludeSemantics(
                          child: Icon(Icons.notifications_off_outlined,
                              size: 28, color: appColors.streakOrange),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Notifications are off',
                                  style: TextStyle(
                                      color: cs.onSurface,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 17)),
                              const SizedBox(height: 4),
                              Text(
                                'Turn them on to get streak alerts and buddy check-ins.',
                                style: TextStyle(
                                    color: appColors.subtleText, fontSize: 14),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () => _once.run(_enableNotifications),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: appColors.streakOrange,
                          foregroundColor:
                              appColors.readableForeground(appColors.streakOrange),
                          elevation: 0,
                          minimumSize: const Size.fromHeight(52),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16)),
                        ),
                        child: const Text('Turn on notifications',
                            style: TextStyle(
                                fontSize: 16, fontWeight: FontWeight.w700)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildCard(List<Widget> children, AppColors appColors) {
    return Container(
      decoration: BoxDecoration(
        color: appColors.claySurface,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
              color: appColors.clayShadowDark,
              blurRadius: 12,
              offset: const Offset(0, 4)),
        ],
      ),
      child: Column(children: children),
    );
  }

  /// A switch row. Saved values are never touched by the OS state: while the
  /// permission is off the switch is only drawn off, and a tap asks for it.
  Widget _buildToggleTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool saved,
    required ValueChanged<bool> onSaved,
    bool osGated = true,
    int index = 0,
  }) {
    final appColors = AppColors.of(context);
    final cs = Theme.of(context).colorScheme;
    final on = saved && (!osGated || _osPermissionGranted);
    void tap() => osGated && !_osPermissionGranted
        ? _once.run(_enableNotifications)
        : onSaved(!saved);
    return Semantics(
      container: true,
      label: title,
      hint: subtitle,
      toggled: on,
      onTap: tap,
      excludeSemantics: true,
      child: InkWell(
        onTap: tap,
        borderRadius: BorderRadius.circular(20),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 64),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(children: [
              Icon(icon, size: 24, color: on ? cs.primary : appColors.subtleText),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: TextStyle(
                            color: cs.onSurface,
                            fontSize: 15,
                            fontWeight: FontWeight.w600)),
                    Text(subtitle,
                        style: TextStyle(
                            color: appColors.subtleText, fontSize: 13)),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              _EmeraldSwitch(
                on: on,
                delay: Duration(milliseconds: 90 * index),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _buildTimeTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required String time,
    required VoidCallback onTap,
    required AppColors appColors,
    required ColorScheme cs,
  }) {
    return InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 64),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(children: [
            Icon(icon, size: 24, color: appColors.subtleText),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: TextStyle(
                          color: cs.onSurface,
                          fontSize: 15,
                          fontWeight: FontWeight.w600)),
                  Text(subtitle,
                      style: TextStyle(
                          color: appColors.subtleText, fontSize: 13)),
                ],
              ),
            ),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: appColors.tint(appColors.streakOrange),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                    color: appColors.streakOrange.withValues(alpha: 0.25),
                    width: 0.5),
              ),
              child: Text(time,
                  style: TextStyle(
                      color: appColors.streakOrange,
                      fontSize: 13,
                      fontWeight: FontWeight.w700)),
            ),
            const SizedBox(width: 6),
            Icon(Icons.chevron_right,
                color: appColors.subtleText, size: 18),
          ]),
        ),
      ),
    );
  }

  Widget _buildDivider(AppColors appColors) {
    return Divider(
        height: 1, color: appColors.divider, indent: 16, endIndent: 16);
  }
}

/// 52x32 track. ON: accent fill, dark knob. OFF: 2px outline, subtle knob.
/// A switch that turns on after a delay (the staggered flip on grant) is just
/// this widget receiving `on: true` with a later start; the state, not the
/// caller, owns the timer. Colour and transform only.
class _EmeraldSwitch extends StatefulWidget {
  final bool on;
  final Duration delay;
  const _EmeraldSwitch({required this.on, required this.delay});

  @override
  State<_EmeraldSwitch> createState() => _EmeraldSwitchState();
}

class _EmeraldSwitchState extends State<_EmeraldSwitch>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
      value: widget.on ? 1 : 0);
  Timer? _timer;

  @override
  void didUpdateWidget(_EmeraldSwitch old) {
    super.didUpdateWidget(old);
    if (old.on == widget.on) return;
    _timer?.cancel();
    if (MediaQuery.disableAnimationsOf(context)) {
      _c.value = widget.on ? 1 : 0;
    } else if (widget.on) {
      _timer = Timer(widget.delay, () {
        if (mounted) _c.forward();
      });
    } else {
      _c.reverse();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final c = AppColors.of(context);
    // No dedicated outline token yet; statusInfo (info) is the closest hue.
    final outline = c.info;
    final knobOff = c.subtleText;
    final knobOn = Theme.of(context).scaffoldBackgroundColor;
    return ExcludeSemantics(
      child: SizedBox(
        width: 52,
        height: 48,
        child: Center(
          child: AnimatedBuilder(
            animation: _c,
            builder: (context, _) {
              final t = Curves.easeOut.transform(_c.value);
              final slide = Curves.easeOutBack.transform(_c.value);
              return Container(
                width: 52,
                height: 32,
                decoration: BoxDecoration(
                  color: Color.lerp(Colors.transparent, cs.primary, t),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                      color: Color.lerp(outline, cs.primary, t)!, width: 2),
                ),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Transform.translate(
                    offset: Offset(2 + 20 * slide, 0),
                    child: Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        color: Color.lerp(knobOff, knobOn, t),
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
