import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// A Supabase client whose HTTP goes to [reply]. Every request is kept.
class FakeSupabase {
  final calls = <http.Request>[];
  Object? Function(http.Request) reply = (_) => [];
  int status = 200;
  bool down = false;

  late final SupabaseClient client = SupabaseClient(
    'https://example.supabase.co',
    'anon',
    httpClient: MockClient((req) async {
      calls.add(req);
      if (down) throw const SocketException('down');
      return http.Response(jsonEncode(reply(req)), status,
          request: req, headers: {'content-type': 'application/json; charset=utf-8'});
    }),
  );

  /// Signs [client] in as [userId] with a session that never reaches the
  /// network: an unsigned token that expires in 2100.
  Future<void> signIn(String userId) async {
    String part(Map<String, dynamic> m) =>
        base64Url.encode(utf8.encode(jsonEncode(m))).replaceAll('=', '');
    final token =
        '${part({'alg': 'HS256', 'typ': 'JWT'})}.${part({'sub': userId, 'exp': 4102444800, 'role': 'authenticated'})}.x';
    await client.auth.recoverSession(jsonEncode({
      'access_token': token,
      'token_type': 'bearer',
      'expires_in': 3600,
      'refresh_token': 'r',
      'user': {
        'id': userId,
        'aud': 'authenticated',
        'app_metadata': <String, dynamic>{},
        'user_metadata': <String, dynamic>{},
        'created_at': '2026-01-01T00:00:00Z',
      },
    }));
  }

  /// The last path segment of call [i]: the table or RPC name.
  String target(int i) => calls[i].url.pathSegments.last;

  /// The JSON body of call [i].
  dynamic body(int i) => jsonDecode(calls[i].body);

  /// The query parameters of call [i] (filters, `limit`, `order`).
  Map<String, String> query(int i) => calls[i].url.queryParameters;
}
