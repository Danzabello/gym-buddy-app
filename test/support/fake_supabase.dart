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

  /// The last path segment of call [i]: the table or RPC name.
  String target(int i) => calls[i].url.pathSegments.last;

  /// The JSON body of call [i].
  dynamic body(int i) => jsonDecode(calls[i].body);

  /// The query parameters of call [i] (filters, `limit`, `order`).
  Map<String, String> query(int i) => calls[i].url.queryParameters;
}
