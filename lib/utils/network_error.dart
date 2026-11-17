import 'dart:async';
import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';

/// Whether [e] is the network being unavailable rather than a bug or a
/// refusal: a dropped socket, a timeout, the http client's wrapper of those,
/// or the auth client giving up a token refresh for want of a network (every
/// request made with an expired token throws it, see supabase's
/// _getAccessToken).
bool isNetworkError(Object e) =>
    e is SocketException ||
    e is TimeoutException ||
    e is AuthRetryableFetchException ||
    // package:http's ClientException, which wraps a SocketException on a real
    // device. Matched by name: http is a dev dependency only, and adding it
    // to dependencies is a manifest change.
    e.runtimeType.toString() == 'ClientException';

/// Runs a read and answers null when the network was unavailable: "unknown,
/// ask again on the next show". Any other error still propagates, and a read
/// that succeeds returns exactly what it returned.
Future<T?> orUnknown<T>(Future<T> Function() read) async {
  try {
    return await read();
  } catch (e) {
    if (isNetworkError(e)) return null;
    rethrow;
  }
}
