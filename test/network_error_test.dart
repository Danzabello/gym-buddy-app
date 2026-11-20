import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gym_buddy_app/services/break_day_service.dart';
import 'package:gym_buddy_app/services/checkin_history_service.dart';
import 'package:gym_buddy_app/utils/network_error.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import 'support/fake_supabase.dart';

const _me = '11111111-1111-4111-8111-111111111111';

// Not package:http's: only its name is the same. By-name matching would have counted it.
class ClientException implements Exception {}

void main() {
  group('isNetworkError', () {
    test('a dropped socket, a timeout, the http wrapper and a retryable auth failure are network errors', () {
      expect(isNetworkError(const SocketException('down')), isTrue);
      expect(isNetworkError(TimeoutException('slow')), isTrue);
      expect(isNetworkError(http.ClientException('Connection failed')), isTrue);
      expect(isNetworkError(AuthRetryableFetchException(message: 'offline')), isTrue);
    });

    test('the http ClientException is matched by its type', () {
      expect(isNetworkError(http.ClientException('Connection closed before full header was received')), isTrue);
    });

    test('an unrelated class that merely has the same name is not a network error', () {
      expect(isNetworkError(ClientException()), isFalse);
    });

    test('a refusal or a bug is not', () {
      expect(isNetworkError(const PostgrestException(message: 'denied', code: '42501')), isFalse);
      expect(isNetworkError(AuthApiException('bad token', statusCode: '400')), isFalse);
      expect(isNetworkError(StateError('bug')), isFalse);
      expect(isNetworkError(const FormatException('x')), isFalse);
    });
  });

  group('orUnknown', () {
    test('a read that succeeds returns exactly what it returned', () async {
      expect(await orUnknown(() async => 7), 7);
      expect(await orUnknown(() async => <String>[]), isEmpty);
      expect(await orUnknown(() async => false), isFalse);
    });

    test('a network error is unknown (null), whatever its kind', () async {
      expect(await orUnknown<int>(() async => throw const SocketException('down')), isNull);
      expect(await orUnknown<int>(() async => throw TimeoutException('slow')), isNull);
      expect(await orUnknown<int>(() async => throw http.ClientException('x')), isNull);
      expect(await orUnknown<int>(() async => throw AuthRetryableFetchException(message: 'x')), isNull);
    });

    test('any other error still propagates', () async {
      await expectLater(orUnknown<int>(() async => throw StateError('bug')), throwsStateError);
      await expectLater(
          orUnknown<int>(() async => throw const PostgrestException(message: 'denied')),
          throwsA(isA<PostgrestException>()));
    });
  });

  // A fake client whose connection is down throws SocketException from every
  // request (FakeSupabase.down). PostgREST retries a read three times first,
  // so each of these takes several seconds.
  group('the start-up reads with the connection down', () {
    test('the weekly plan read (_checkWeeklyPlan) is unknown, not thrown', () async {
      final server = FakeSupabase()..down = true;
      await server.signIn(_me);
      final svc = BreakDayService(client: server.client);
      expect(await orUnknown(svc.needsToSetWeeklyPlan), isNull);
      expect(server.calls, isNotEmpty);
      expect(server.target(0), 'weekly_break_plans');
    });

    test('the same read still answers when the connection is up', () async {
      final none = FakeSupabase()..reply = (_) => null;
      await none.signIn(_me);
      expect(await orUnknown(BreakDayService(client: none.client).needsToSetWeeklyPlan), isTrue);

      final planned = FakeSupabase()..reply = (_) => {'id': 'p1', 'max_break_days': 2};
      await planned.signIn(_me);
      expect(await orUnknown(BreakDayService(client: planned.client).needsToSetWeeklyPlan), isFalse);
    });

    test('a refused weekly plan read is still an error', () async {
      final refused = FakeSupabase()
        ..status = 403
        ..reply = (_) => {'message': 'permission denied', 'code': '42501'};
      await refused.signIn(_me);
      await expectLater(
          orUnknown(BreakDayService(client: refused.client).needsToSetWeeklyPlan),
          throwsA(isA<PostgrestException>()));
    });

    test('the heatmap check-in dates read (dashboard first load) is unknown', () async {
      final server = FakeSupabase()..down = true;
      await server.signIn(_me);
      final svc = CheckInHistoryService(client: server.client);
      expect(await orUnknown(() => svc.myCheckInDatesSince('2026-11-10')), isNull);
    });
  });
}
