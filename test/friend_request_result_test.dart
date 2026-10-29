import 'package:flutter_test/flutter_test.dart';
import 'package:gym_buddy_app/services/friend_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  test('too_many_requests from the friendships trigger maps to tooManyRequests', () {
    expect(
        friendRequestErrorResult(
            const PostgrestException(code: 'P0001', message: 'too_many_requests')),
        FriendRequestResult.tooManyRequests);
  });

  test('every other failure stays a retryable error', () {
    expect(
        friendRequestErrorResult(const PostgrestException(
            code: '23505', message: 'duplicate key value violates unique constraint "unique_friendship"')),
        FriendRequestResult.error);
    expect(
        friendRequestErrorResult(
            const PostgrestException(code: 'P0001', message: 'too_many_attempts')),
        FriendRequestResult.error);
    expect(friendRequestErrorResult(Exception('too_many_requests')), FriendRequestResult.error);
  });
}
