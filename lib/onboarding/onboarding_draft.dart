import 'package:flutter/material.dart';

enum BuddyChoice { invite, coachMax }

/// What the user has typed and picked so far. Lives in the host so Back keeps
/// every field, and nothing is written until step 5.
class OnboardingDraft {
  final email = TextEditingController();
  final password = TextEditingController();
  final confirm = TextEditingController();
  final name = TextEditingController();
  final age = TextEditingController();
  final username = TextEditingController();

  String avatarId = 'bear';

  /// Ring colour picked on step 3; null is the default ring.
  Color? ringColor;
  String ringName = 'Classic';

  BuddyChoice buddy = BuddyChoice.coachMax;

  void dispose() {
    for (final c in [email, password, confirm, name, age, username]) {
      c.dispose();
    }
  }
}
