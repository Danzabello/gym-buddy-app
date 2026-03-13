import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import '../services/notification_service.dart';
import 'package:app_settings/app_settings.dart';


class NotificationSettingsPage extends StatefulWidget {
  const NotificationSettingsPage({super.key});

  @override
  State<NotificationSettingsPage> createState() =>
      _NotificationSettingsPageState();
}

class _NotificationSettingsPageState extends State<NotificationSettingsPage> {
  final NotificationService _notificationService = NotificationService();

  bool _isLoading = true;
  bool _isSaving = false;

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
          content: const Row(
            children: [
              Icon(Icons.check_circle, color: Colors.white),
              SizedBox(width: 12),
              Text('Notification settings saved!'),
            ],
          ),
          backgroundColor: Colors.green[600],
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SizedBox(
        height: 300,
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.grey[50],
                borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text('Cancel', style: TextStyle(color: Colors.grey[600])),
                  ),
                  Text(
                    isStart ? 'Start Time' : 'End Time',
                    style: const TextStyle(
                        color: Colors.black87,
                        fontSize: 16,
                        fontWeight: FontWeight.bold),
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
                            color: Colors.orange[700],
                            fontWeight: FontWeight.bold)),
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
                      style: const TextStyle(color: Colors.black87, fontSize: 18),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Notification Settings',
          style: TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Colors.blue[700]!, Colors.purple[600]!],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        actions: [
          if (_isSaving)
            const Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.white),
              ),
            )
          else
            TextButton(
              onPressed: _saveSettings,
              child: const Text(
                'Save',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // Header banner
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Colors.orange[600]!, Colors.orange[400]!],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.orange.withOpacity(0.3),
                        blurRadius: 8,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.notifications_active,
                          color: Colors.white, size: 32),
                      SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Stay in the Loop',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              'Choose what notifications you receive',
                              style: TextStyle(
                                  color: Colors.white70, fontSize: 13),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 24),

                _buildSectionHeader('📬 Notification Categories'),
                const SizedBox(height: 8),
                _buildSettingsCard([
                  _buildToggleTile(
                    icon: '👥',
                    title: 'Social',
                    subtitle: 'Friend requests & acceptances',
                    value: _notifSocial,
                    onChanged: (v) => setState(() => _notifSocial = v),
                  ),
                  _buildDivider(),
                  _buildToggleTile(
                    icon: '🏋️',
                    title: 'Workouts',
                    subtitle: 'Invites, reminders & updates',
                    value: _notifWorkouts,
                    onChanged: (v) => setState(() => _notifWorkouts = v),
                  ),
                  _buildDivider(),
                  _buildToggleTile(
                    icon: '🔥',
                    title: 'Streaks',
                    subtitle: 'Check-ins, milestones & warnings',
                    value: _notifStreaks,
                    onChanged: (v) => setState(() => _notifStreaks = v),
                  ),
                  _buildDivider(),
                  _buildToggleTile(
                    icon: '🤖',
                    title: 'Coach Max',
                    subtitle: 'Motivational messages & check-ins',
                    value: _notifCoachMax,
                    onChanged: (v) => setState(() => _notifCoachMax = v),
                  ),
                ]),

                const SizedBox(height: 24),

                _buildSectionHeader('🌙 Quiet Hours'),
                const SizedBox(height: 8),
                _buildSettingsCard([
                  _buildToggleTile(
                    icon: '🔕',
                    title: 'Enable Quiet Hours',
                    subtitle: 'Pause notifications during set hours',
                    value: _quietHoursEnabled,
                    onChanged: (v) =>
                        setState(() => _quietHoursEnabled = v),
                  ),
                  if (_quietHoursEnabled) ...[
                    _buildDivider(),
                    _buildTimeTile(
                      icon: '🌆',
                      title: 'Start Time',
                      subtitle: 'Notifications pause at',
                      time: _formatHour(_quietHoursStart),
                      onTap: () => _showHourPicker(true),
                    ),
                    _buildDivider(),
                    _buildTimeTile(
                      icon: '🌅',
                      title: 'End Time',
                      subtitle: 'Notifications resume at',
                      time: _formatHour(_quietHoursEnd),
                      onTap: () => _showHourPicker(false),
                    ),
                  ],
                ]),

                if (_quietHoursEnabled) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.blue[50],
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: Colors.blue.withOpacity(0.3), width: 1),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.info_outline,
                            color: Colors.blue[700], size: 16),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Quiet hours: ${_formatHour(_quietHoursStart)} → ${_formatHour(_quietHoursEnd)}',
                            style: TextStyle(
                                color: Colors.blue[700], fontSize: 13),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: 32),

                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _isSaving ? null : _saveSettings,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange[600],
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 4,
                    ),
                    child: _isSaving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        : const Text(
                            'Save Settings',
                            style: TextStyle(
                                fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                  ),
                ),

                const SizedBox(height: 32),
              ],
            ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Text(
      title,
      style: const TextStyle(
        color: Color(0xFF2C3E50),
        fontSize: 16,
        fontWeight: FontWeight.bold,
      ),
    );
  }

  Widget _buildOsPermissionBanner() {
    if (_osPermissionGranted) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.red[50],
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.red[300]!),
      ),
      child: Row(
        children: [
          Icon(Icons.notifications_off, color: Colors.red[700], size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Notifications Blocked',
                  style: TextStyle(
                    color: Colors.red[800],
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'You\'ve blocked notifications at the system level. These settings won\'t take effect until you allow them.',
                  style: TextStyle(color: Colors.red[700], fontSize: 12),
                ),
                const SizedBox(height: 8),
                GestureDetector(
                  onTap: () => AppSettings.openAppSettings(type: AppSettingsType.notification),
                  child: Text(
                    'Open Settings →',
                    style: TextStyle(
                      color: Colors.red[800],
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      decoration: TextDecoration.underline,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSettingsCard(List<Widget> children) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(children: children),
    );
  }

  Widget _buildToggleTile({
    required String icon,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Text(icon, style: const TextStyle(fontSize: 24)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        color: Color(0xFF2C3E50),
                        fontSize: 15,
                        fontWeight: FontWeight.w600)),
                Text(subtitle,
                    style: TextStyle(color: Colors.grey[600], fontSize: 12)),
              ],
            ),
          ),
          CupertinoSwitch(
            value: value,
            onChanged: onChanged,
            activeColor: Colors.orange[600],
          ),
        ],
      ),
    );
  }

  Widget _buildTimeTile({
    required String icon,
    required String title,
    required String subtitle,
    required String time,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Text(icon, style: const TextStyle(fontSize: 24)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          color: Color(0xFF2C3E50),
                          fontSize: 15,
                          fontWeight: FontWeight.w600)),
                  Text(subtitle,
                      style: TextStyle(color: Colors.grey[600], fontSize: 12)),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.orange[50],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange[300]!),
              ),
              child: Text(
                time,
                style: TextStyle(
                  color: Colors.orange[700],
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Icon(Icons.chevron_right, color: Colors.grey[400], size: 18),
          ],
        ),
      ),
    );
  }

  Widget _buildDivider() {
    return Divider(
      height: 1,
      color: Colors.grey[200],
      indent: 16,
      endIndent: 16,
    );
  }
}