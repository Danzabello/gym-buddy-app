import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:gym_buddy_app/utils/crash_report.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  // The test host is not a phone, so Firebase is never started: reporting must
  // be a silent no-op for an unexpected error and for an expected one.
  test('reportNonFatal never throws without Firebase', () {
    reportNonFatal(const FormatException('bad'), StackTrace.current, 'test_label');
    reportNonFatal(TimeoutException('slow'), null, 'test_label');
  });

  test('a Postgrest error is sent as its type and code only', () {
    const e = PostgrestException(
        message: 'secret message', code: '42501', details: 'secret details', hint: 'secret hint');
    final sent = nonFatalPayload(e).toString();
    expect(sent, 'PostgrestException code=42501');
  });

  test('any other error is sent as is', () {
    const e = FormatException('bad');
    expect(nonFatalPayload(e), same(e));
  });
}
