// lib/pages/notification_settings_page.dart
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import '../services/notification_service.dart';
import 'package:app_settings/app_settings.dart';
import '../theme/app_theme.dart';

class NotificationSettingsPage extends StatefulWidget {
  const NotificationSettingsPage({super.key});

  @override
  State<NotificationSettingsPage> createState() =>
      _NotificationSettingsPageState();
}

class _NotificationSettingsPageState
    extends State<NotificationSettingsPage> {
  final NotificationService _notificationService = NotificationService();

  bool _isLoading = true;
  bool _isSaving = false;
  bool _osPermissionGranted = true;

  bool _notifSocial = true;
  bool _notifWorkouts = true;
  bool _notifStreaks = true;
  bool _notifCoachMax = true;

  bool _quietHoursEnabled = true;
  int _quietHoursStart = 23;
  int _quietHoursEnd = 7;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final granted = await _notificationService.checkOsPermission();
    final settings = await _notificationService.getSettings();
    if (mounted) {
      setState(() {
        _osPermissionGranted = granted;
        _notifSocial = settings['notif_social'] ?? true;
        _notifWorkouts = settings['notif_workouts'] ?? true;
        _notifStreaks = settings['notif_streaks'] ?? true;
        _notifCoachMax = settings['notif_coach_max'] ?? true;
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
          backgroundColor: const Color(0xFF10B981),
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

  void _showHourPicker(bool isStart) {
    int tempHour = isStart ? _quietHoursStart : _quietHoursEnd;
    final appColors = AppColors.of(context);
    final cs = Theme.of(context).colorScheme;

    showModalBottomSheet(
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
                  child: const Text('Done',
                      style: TextStyle(
                          color: Color(0xFFF97316),
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
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.transparent,
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF1D4ED8), Color(0xFF7C3AED)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios,
              color: Colors.white, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Notifications',
          style: TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w800),
        ),
        actions: [
          if (_isSaving)
            const Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white)),
            )
          else
            TextButton(
              onPressed: _saveSettings,
              child: const Text('Save',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w700)),
            ),
        ],
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator(color: cs.primary))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // Hero banner
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFFF97316), Color(0xFFFB923C)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Row(children: [
                    Icon(Icons.notifications_active,
                        color: Colors.white, size: 28),
                    SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Stay in the Loop',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800)),
                          Text('Choose what notifications you receive',
                              style: TextStyle(
                                  color: Colors.white70,
                                  fontSize: 12)),
                        ],
                      ),
                    ),
                  ]),
                ),

                const SizedBox(height: 14),
                _buildOsPermissionBanner(appColors, cs),
                const SizedBox(height: 6),

                _buildSectionHeader('📬  Notification Categories',
                    appColors, cs),
                const SizedBox(height: 8),
                _buildCard([
                  _buildToggleTile(
                    icon: '👥',
                    title: 'Social',
                    subtitle: 'Friend requests & acceptances',
                    value: _notifSocial,
                    onChanged: _osPermissionGranted
                        ? (v) => setState(() => _notifSocial = v)
                        : null,
                    appColors: appColors,
                    cs: cs,
                  ),
                  _buildDivider(appColors),
                  _buildToggleTile(
                    icon: '🏋️',
                    title: 'Workouts',
                    subtitle: 'Invites, reminders & updates',
                    value: _notifWorkouts,
                    onChanged: _osPermissionGranted
                        ? (v) => setState(() => _notifWorkouts = v)
                        : null,
                    appColors: appColors,
                    cs: cs,
                  ),
                  _buildDivider(appColors),
                  _buildToggleTile(
                    icon: '🔥',
                    title: 'Streaks',
                    subtitle: 'Check-ins, milestones & warnings',
                    value: _notifStreaks,
                    onChanged: _osPermissionGranted
                        ? (v) => setState(() => _notifStreaks = v)
                        : null,
                    appColors: appColors,
                    cs: cs,
                  ),
                  _buildDivider(appColors),
                  _buildToggleTile(
                    icon: '🤖',
                    title: 'Coach Max',
                    subtitle: 'Motivational messages & check-ins',
                    value: _notifCoachMax,
                    onChanged: _osPermissionGranted
                        ? (v) => setState(() => _notifCoachMax = v)
                        : null,
                    appColors: appColors,
                    cs: cs,
                  ),
                ], appColors),

                const SizedBox(height: 22),
                _buildSectionHeader('🌙  Quiet Hours', appColors, cs),
                const SizedBox(height: 8),
                _buildCard([
                  _buildToggleTile(
                    icon: '🔕',
                    title: 'Enable Quiet Hours',
                    subtitle: 'Pause notifications during set hours',
                    value: _quietHoursEnabled,
                    onChanged: _osPermissionGranted
                        ? (v) =>
                            setState(() => _quietHoursEnabled = v)
                        : null,
                    appColors: appColors,
                    cs: cs,
                  ),
                  if (_quietHoursEnabled) ...[
                    _buildDivider(appColors),
                    _buildTimeTile(
                      icon: '🌆',
                      title: 'Start Time',
                      subtitle: 'Notifications pause at',
                      time: _formatHour(_quietHoursStart),
                      onTap: () => _showHourPicker(true),
                      appColors: appColors,
                      cs: cs,
                    ),
                    _buildDivider(appColors),
                    _buildTimeTile(
                      icon: '🌅',
                      title: 'End Time',
                      subtitle: 'Notifications resume at',
                      time: _formatHour(_quietHoursEnd),
                      onTap: () => _showHourPicker(false),
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
                      color: const Color(0xFF3B82F6).withOpacity(0.08),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color:
                              const Color(0xFF3B82F6).withOpacity(0.2),
                          width: 0.5),
                    ),
                    child: Row(children: [
                      const Icon(Icons.info_outline,
                          color: Color(0xFF3B82F6), size: 15),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Quiet hours: ${_formatHour(_quietHoursStart)} → ${_formatHour(_quietHoursEnd)}',
                          style: const TextStyle(
                              color: Color(0xFF3B82F6), fontSize: 12),
                        ),
                      ),
                    ]),
                  ),
                ],

                const SizedBox(height: 28),

                // Save button
                GestureDetector(
                  onTap: _isSaving ? null : _saveSettings,
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF97316),
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
    if (_osPermissionGranted) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFEF4444).withOpacity(0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: const Color(0xFFEF4444).withOpacity(0.25), width: 0.5),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.notifications_off,
              color: Color(0xFFEF4444), size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Notifications Blocked',
                    style: TextStyle(
                        color: cs.onSurface,
                        fontWeight: FontWeight.w700,
                        fontSize: 13)),
                const SizedBox(height: 4),
                Text(
                  'You\'ve blocked notifications at the system level. These settings won\'t take effect until you allow them.',
                  style: TextStyle(
                      color: appColors.subtleText, fontSize: 12),
                ),
                const SizedBox(height: 8),
                GestureDetector(
                  onTap: () => AppSettings.openAppSettings(
                      type: AppSettingsType.notification),
                  child: const Text('Open Phone Settings →',
                      style: TextStyle(
                          color: Color(0xFFEF4444),
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                          decoration: TextDecoration.underline)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(
      String title, AppColors appColors, ColorScheme cs) {
    return Text(title,
        style: TextStyle(
            color: cs.onSurface,
            fontSize: 14,
            fontWeight: FontWeight.w700));
  }

  Widget _buildCard(List<Widget> children, AppColors appColors) {
    return Container(
      decoration: BoxDecoration(
        color: appColors.cardBackground,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: appColors.cardBorder, width: 0.5),
      ),
      child: Column(children: children),
    );
  }

  Widget _buildToggleTile({
    required String icon,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool>? onChanged,
    required AppColors appColors,
    required ColorScheme cs,
  }) {
    final disabled = onChanged == null;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(children: [
        Text(icon,
            style: TextStyle(
                fontSize: 22,
                color: disabled
                    ? appColors.subtleText.withOpacity(0.4)
                    : null)),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: TextStyle(
                      color: disabled
                          ? appColors.subtleText
                          : cs.onSurface,
                      fontSize: 14,
                      fontWeight: FontWeight.w600)),
              Text(subtitle,
                  style: TextStyle(
                      color: disabled
                          ? appColors.subtleText.withOpacity(0.5)
                          : appColors.subtleText,
                      fontSize: 12)),
            ],
          ),
        ),
        CupertinoSwitch(
          value: value,
          onChanged: onChanged,
          activeColor: const Color(0xFFF97316),
        ),
      ]),
    );
  }

  Widget _buildTimeTile({
    required String icon,
    required String title,
    required String subtitle,
    required String time,
    required VoidCallback onTap,
    required AppColors appColors,
    required ColorScheme cs,
  }) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(children: [
          Text(icon, style: const TextStyle(fontSize: 22)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: TextStyle(
                        color: cs.onSurface,
                        fontSize: 14,
                        fontWeight: FontWeight.w600)),
                Text(subtitle,
                    style: TextStyle(
                        color: appColors.subtleText, fontSize: 12)),
              ],
            ),
          ),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: const Color(0xFFF97316).withOpacity(0.10),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                  color: const Color(0xFFF97316).withOpacity(0.25),
                  width: 0.5),
            ),
            child: Text(time,
                style: const TextStyle(
                    color: Color(0xFFF97316),
                    fontSize: 13,
                    fontWeight: FontWeight.w700)),
          ),
          const SizedBox(width: 6),
          Icon(Icons.chevron_right,
              color: appColors.subtleText, size: 18),
        ]),
      ),
    );
  }

  Widget _buildDivider(AppColors appColors) {
    return Divider(
        height: 1, color: appColors.divider, indent: 16, endIndent: 16);
  }
}