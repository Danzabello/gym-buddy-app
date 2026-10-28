import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

String _seenKey() =>
    'notif_rationale_seen_${Supabase.instance.client.auth.currentUser?.id}';

/// Records that the notification step was answered (either button).
Future<void> markNotificationRationaleSeen() async {
  try {
    await (await SharedPreferences.getInstance()).setBool(_seenKey(), true);
  } catch (_) {}
}
