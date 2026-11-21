import 'dart:async';
import 'dart:io';

import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:supabase_flutter/supabase_flutter.dart';

import 'network_error.dart';

final _reported = <String>{};

/// What is sent for [error]. A Postgrest message, details and hint can carry
/// row values, so only its type and code go; any other error goes as is.
@visibleForTesting
Object nonFatalPayload(Object error) =>
    error is PostgrestException ? 'PostgrestException code=${error.code}' : error;

/// Whether an error is worth reporting: not the network being unavailable and
/// not an expired session.
bool isReportableError(Object error) =>
    !isNetworkError(error) &&
    error is! AuthException &&
    !(error is PostgrestException && error.code == 'PGRST301'); // JWT expired

/// Sends an error the app swallowed to Crashlytics as a non-fatal, so a bug
/// that fails quietly is still seen. [reason] is a fixed label per call site
/// (no user data). Expected failures are skipped: the network being
/// unavailable, and an expired session. Each label is sent once per app run,
/// so a failure that repeats on every refresh does not flood. Never throws,
/// never waits, and does nothing off a phone (tests, desktop) where Firebase
/// is not started. Debug builds follow the collection setting in main.dart.
void reportNonFatal(Object error, StackTrace? stack, String reason) {
  if (!isReportableError(error)) return;
  if (!(Platform.isAndroid || Platform.isIOS)) return;
  if (!_reported.add(reason)) return;
  try {
    unawaited(FirebaseCrashlytics.instance
        .recordError(nonFatalPayload(error), stack, reason: reason)
        .catchError((Object _) {}));
  } catch (_) {}
}
