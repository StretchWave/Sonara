import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

/// Dio adapter that serves canned responses per request and records how
/// many requests hit the network.
class FakeDioAdapter implements HttpClientAdapter {
  FutureOr<ResponseBody> Function(RequestOptions options)? handler;
  int requestCount = 0;

  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    requestCount++;
    final h = handler;
    if (h == null) {
      return ResponseBody.fromString('{}', 500);
    }
    return h(options);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody jsonResponse(Object body,
        {int status = 200, Map<String, String>? headers}) =>
    ResponseBody.fromString(
      jsonEncode(body),
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
        if (headers != null)
          for (final e in headers.entries) e.key: [e.value],
      },
    );

/// A typical LRCLIB /get payload.
Map<String, dynamic> lrcJson({
  int? id = 1,
  String? synced = '[00:01.00]Line one\n[00:03.00]Line two',
  String? plain = 'Line one\nLine two',
  bool instrumental = false,
  String? trackName = 'Blinding Lights',
  String? artistName = 'The Weeknd',
  String? albumName = 'After Hours',
  int? duration = 200,
}) =>
    {
      'id': id,
      'syncedLyrics': synced,
      'plainLyrics': plain,
      'instrumental': instrumental,
      'trackName': trackName,
      'artistName': artistName,
      'albumName': albumName,
      'duration': duration,
    };
