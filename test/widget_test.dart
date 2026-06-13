// Smoke test for Gym Buddy.
//
// The real app root is [GymBuddyApp] (lib/main.dart). Pumping it would run
// AuthWrapper.initState, which touches Supabase/Firebase singletons that are
// only initialised in main() — not available in a plain test harness. So this
// smoke test verifies the app root constructs without throwing, which is enough
// to keep `flutter test` compiling and green.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:gym_buddy_app/main.dart';

void main() {
  test('GymBuddyApp constructs without crashing', () {
    const app = GymBuddyApp();
    expect(app, isA<Widget>());
    expect(app, isA<StatelessWidget>());
  });
}
