import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';

/// A code_verifier / code_challenge pair for Spotify's Authorization Code
/// with PKCE flow.
class PkcePair {
  final String verifier;
  final String challenge;

  const PkcePair({required this.verifier, required this.challenge});
}

/// Generates a PKCE pair. [random] is injectable for deterministic tests.
PkcePair generatePkcePair({Random? random}) {
  final rng = random ?? Random.secure();
  final bytes = List<int>.generate(64, (_) => rng.nextInt(256));
  final verifier = base64UrlEncode(bytes).replaceAll('=', '');
  final challenge = base64UrlEncode(sha256.convert(utf8.encode(verifier)).bytes)
      .replaceAll('=', '');
  return PkcePair(verifier: verifier, challenge: challenge);
}

/// Builds the Spotify authorization URL for the PKCE flow.
Uri buildSpotifyAuthorizeUrl({
  required String clientId,
  required String redirectUri,
  required String codeChallenge,
  required String state,
  List<String> scopes = const [
    'playlist-read-private',
    'playlist-read-collaborative',
  ],
}) {
  return Uri.https('accounts.spotify.com', '/authorize', {
    'client_id': clientId,
    'response_type': 'code',
    'redirect_uri': redirectUri,
    'code_challenge_method': 'S256',
    'code_challenge': codeChallenge,
    'scope': scopes.join(' '),
    'state': state,
  });
}

/// Waits for the Spotify OAuth redirect on a loopback server and returns the
/// authorization code.
///
/// The browser is expected to redirect to
/// `http://localhost:<port>/callback?code=...&state=...`. The [state] must
/// match to prevent CSRF. Throws [SpotifyAuthCancelledException] when the
/// user closes the tab or the flow times out.
Future<String> awaitSpotifyCallback({
  required int port,
  required String state,
  Duration timeout = const Duration(minutes: 5),
}) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
  try {
    final future = server.first
        .timeout(timeout, onTimeout: () => throw const SpotifyAuthTimeoutException());
    final request = await future;
    final params = request.uri.queryParameters;
    if (params['state'] != state) {
      await _respond(request, 'State mismatch', 400);
      throw SpotifyAuthException(
          'Spotify authorization state mismatch — try again');
    }
    final code = params['code'];
    if (code == null || code.isEmpty) {
      final error = params['error'] ?? 'unknown error';
      await _respond(request, 'Authorization failed', 400);
      if (error == 'access_denied') {
        throw const SpotifyAuthCancelledException();
      }
      throw SpotifyAuthException(
          'Spotify authorization failed: $error');
    }
    await _respond(request, 'You can close this window and return to the app.');
    return code;
  } finally {
    await server.close(force: true);
  }
}

Future<void> _respond(HttpRequest request, String body, [int status = 200]) async {
  request.response
    ..statusCode = status
    ..headers.contentType = ContentType.html
    ..write('<!DOCTYPE html><html><body style="font-family:sans-serif;'
        'padding:2rem">$body</body></html>');
  await request.response.close();
}

/// Raised when Spotify credentials are missing, rejected or expired.
class SpotifyAuthException implements Exception {
  final String message;
  SpotifyAuthException([this.message = 'Spotify authentication failed']);
  @override
  String toString() => message;
}

/// Thrown when the user cancels or the callback times out.
class SpotifyAuthCancelledException implements Exception {
  final String message;
  const SpotifyAuthCancelledException([this.message = 'Spotify sign-in cancelled']);
  @override
  String toString() => message;
}

class SpotifyAuthTimeoutException implements Exception {
  const SpotifyAuthTimeoutException();
  @override
  String toString() => 'Spotify sign-in timed out';
}
