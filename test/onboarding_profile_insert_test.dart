import 'package:flutter_test/flutter_test.dart';
import 'package:gym_buddy_app/onboarding/onboarding_basic_info_new.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  test('own-id duplicate is detected, username duplicate is not', () {
    expect(
        isOwnProfileDuplicate(const PostgrestException(
            code: '23505',
            message: 'duplicate key value violates unique constraint "user_profiles_pkey"')),
        isTrue);
    expect(
        isOwnProfileDuplicate(const PostgrestException(
            code: '23505',
            message: 'duplicate key value violates unique constraint "user_profiles_username_key"')),
        isFalse);
    expect(isOwnProfileDuplicate(Exception('network')), isFalse);
  });

  test('fallback update carries only discovery fields', () {
    final out = discoveryFieldsOf({
      'id': 'u1', 'display_name': 'D', 'username': 'd', 'age': 30,
      'gender': 'x', 'avatar_id': 'a', 'avatar_border': 'simple',
      'fitness_goals': ['s'], 'fitness_level': 'beginner',
      'looking_for_buddy': true, 'preferred_workout_style': 'gym',
      'onboarding_completed': true, 'updated_at': 'now',
    });
    expect(out.keys.toSet(), {
      'display_name', 'username', 'avatar_id', 'avatar_border',
      'fitness_level', 'looking_for_buddy',
    });
  });
}
