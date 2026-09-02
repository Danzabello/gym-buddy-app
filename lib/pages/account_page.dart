import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../login_screen.dart';
import '../services/notification_service.dart';
import '../theme/accent_theme_provider.dart';
import '../theme/app_theme.dart';
import '../utils/debug_logger.dart';
import '../utils/input_validators.dart';
import '../widgets/menu_card.dart';

class AccountPage extends StatefulWidget {
  const AccountPage({super.key});

  @override
  State<AccountPage> createState() => _AccountPageState();
}

class _AccountPageState extends State<AccountPage> {
  String? _username;

  @override
  void initState() {
    super.initState();
    _loadUsername();
  }

  Future<void> _loadUsername() async {
    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid == null) return;
    final profile = await Supabase.instance.client
        .from('user_profiles')
        .select('username')
        .eq('id', uid)
        .single();
    if (mounted) setState(() => _username = profile['username'] as String?);
  }

  // ══════════════════════════════════════════════════════════════
  // ACCOUNT
  // ══════════════════════════════════════════════════════════════
  Future<void> _showEditUsernameDialog() async {
    final controller = TextEditingController(text: _username ?? '');
    final appColors = AppColors.of(context);
    String? errorText;
    bool isSaving = false;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          backgroundColor: appColors.cardBackground,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text(
            'Change Username',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: Theme.of(dialogContext).colorScheme.onSurface,
            ),
          ),
          content: TextField(
            controller: controller,
            autofocus: true,
            inputFormatters: InputFormatters.username,
            decoration: InputDecoration(
              hintText: 'username',
              errorText: errorText,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
          actions: [
            TextButton(
              onPressed: isSaving ? null : () => Navigator.pop(dialogContext),
              child: Text('Cancel', style: TextStyle(color: appColors.subtleText)),
            ),
            TextButton(
              onPressed: isSaving
                  ? null
                  : () async {
                      final value = controller.text.trim().toLowerCase();
                      final err = InputValidators.username(value);
                      if (err != null) {
                        setDialogState(() => errorText = err);
                        return;
                      }
                      if (value == _username) {
                        Navigator.pop(dialogContext);
                        return;
                      }
                      setDialogState(() {
                        isSaving = true;
                        errorText = null;
                      });
                      final saveError = await _saveUsername(value);
                      if (saveError != null) {
                        setDialogState(() {
                          isSaving = false;
                          errorText = saveError;
                        });
                        return;
                      }
                      if (dialogContext.mounted) Navigator.pop(dialogContext);
                    },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  /// Returns null on success, or a user-facing error to show inline in the
  /// dialog's errorText -- never a SnackBar, since the dialog stays open.
  Future<String?> _saveUsername(String newUsername) async {
    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid == null) return 'Failed to update username.';
    try {
      await Supabase.instance.client
          .from('user_profiles')
          .update({'username': newUsername})
          .eq('id', uid);
      if (mounted) setState(() => _username = newUsername);
      return null;
    } on PostgrestException catch (e) {
      return e.code == '23505' ? 'That username is taken.' : 'Failed to update username.';
    }
  }

  void _showDeleteAccountSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _DeleteAccountSheet(onConfirmed: _deleteAccount),
    );
  }

  /// Same shape as AuthWrapper._cleanupOrphanedAccount in main.dart, minus
  /// the retry-signup step -- but signs out only on success, since a failed
  /// delete must leave the account (and session) intact.
  Future<bool> _deleteAccount() async {
    await NotificationService().removeToken();
    try {
      await Supabase.instance.client.functions.invoke('delete-account');
    } catch (e) {
      if (kDebugMode) debugLog('❌ AccountPage._deleteAccount: $e');
      return false;
    }
    await Supabase.instance.client.auth.signOut();
    if (!mounted) return true;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => LoginScreen()),
      (route) => false,
    );
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final appColors = AppColors.of(context);
    final palette = context.watch<AccentThemeProvider>().palette;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        // Inherits transparent bg + foreground from appBarTheme
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Account',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          buildMenuCard(context, [
            MenuItem(
              icon: Icons.email_outlined,
              iconColor: appColors.subtleText,
              color: appColors.sectionBackground,
              label: 'Email',
              sub: Supabase.instance.client.auth.currentUser?.email ?? '',
              showChevron: false,
            ),
            MenuItem(
              icon: Icons.person_outline,
              iconColor: appColors.subtleText,
              color: appColors.sectionBackground,
              label: 'Username',
              sub: _username ?? '',
              onTap: _showEditUsernameDialog,
            ),
          ]),
          const SizedBox(height: 14),
          buildMenuCard(context, [
            MenuItem(
              icon: Icons.delete_outline,
              iconColor: palette.statusDanger,
              color: palette.statusDanger.withOpacity(0.10),
              label: 'Delete Account',
              labelColor: palette.statusDanger,
              onTap: _showDeleteAccountSheet,
            ),
          ]),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════
// DELETE ACCOUNT confirmation sheet
// ══════════════════════════════════════════════════════════════
class _DeleteAccountSheet extends StatefulWidget {
  final Future<bool> Function() onConfirmed;
  const _DeleteAccountSheet({required this.onConfirmed});

  @override
  State<_DeleteAccountSheet> createState() => _DeleteAccountSheetState();
}

class _DeleteAccountSheetState extends State<_DeleteAccountSheet> {
  final _controller = TextEditingController();
  bool _matches = false;
  bool _isDeleting = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _handleConfirm() async {
    setState(() {
      _isDeleting = true;
      _error = null;
    });
    final success = await widget.onConfirmed();
    // On success the whole nav stack (including this sheet) was already
    // replaced, so `mounted` is false and there's nothing left to update.
    if (!mounted) return;
    if (!success) {
      setState(() {
        _isDeleting = false;
        _error = 'Something went wrong. Please try again.';
      });
    }
  }

  Widget _consequenceRow(Color color, IconData icon, String text) {
    return Row(children: [
      Icon(icon, size: 14, color: color),
      const SizedBox(width: 8),
      Expanded(child: Text(text, style: TextStyle(fontSize: 12, color: color))),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final appColors = AppColors.of(context);
    final palette = context.watch<AccentThemeProvider>().palette;
    final cs = Theme.of(context).colorScheme;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: BoxDecoration(
          color: appColors.cardBackground,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: EdgeInsets.fromLTRB(24, 16, 24, MediaQuery.of(context).padding.bottom + 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40, height: 4,
                decoration: BoxDecoration(
                  color: appColors.divider,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Center(
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: palette.statusDanger.withOpacity(0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.warning_amber_rounded, color: palette.statusDanger, size: 28),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Delete your account?',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: cs.onSurface),
            ),
            const SizedBox(height: 8),
            Text(
              "This permanently deletes your profile, streaks, workout history, "
              "achievements, and coins. Your buddies keep their own data. This "
              "can't be undone.",
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: appColors.subtleText),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: palette.statusDanger.withOpacity(0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: palette.statusDanger.withOpacity(0.2), width: 0.5),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _consequenceRow(palette.statusDanger, Icons.person_outline,
                      'Delete your profile, XP, and coin balance'),
                  const SizedBox(height: 5),
                  _consequenceRow(palette.statusDanger, Icons.groups_outlined,
                      'Remove you from all buddy teams and streaks'),
                  const SizedBox(height: 5),
                  _consequenceRow(palette.statusDanger, Icons.history,
                      'Delete your workout and check-in history'),
                  const SizedBox(height: 5),
                  _consequenceRow(
                      palette.statusDanger, Icons.logout, 'Sign you out immediately'),
                ],
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _controller,
              autocorrect: false,
              textCapitalization: TextCapitalization.characters,
              decoration: InputDecoration(
                hintText: 'DELETE',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onChanged: (v) => setState(() => _matches = v == 'DELETE'),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: TextStyle(color: palette.statusDanger, fontSize: 12)),
            ],
            const SizedBox(height: 16),
            GestureDetector(
              onTap: (_matches && !_isDeleting) ? _handleConfirm : null,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(
                  color: _matches
                      ? palette.statusDanger
                      : palette.statusDanger.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Center(
                  child: _isDeleting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Text(
                          'Delete My Account',
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
                        ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            GestureDetector(
              onTap: _isDeleting ? null : () => Navigator.pop(context),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: appColors.cardBorder, width: 0.5),
                ),
                child: Center(
                  child: Text(
                    'Cancel',
                    style: TextStyle(color: appColors.subtleText, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
