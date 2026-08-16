import 'dart:convert';
import 'dart:io';

import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import 'models.dart';
import 'providers/playlist_provider.dart';
import 'rate_limit.dart';
import 'resolver.dart';

/// Extracts a Spotify playlist id from a URL, URI or bare id.
///
/// Accepts:
///   https://open.spotify.com/playlist/{id}[?...]
///   https://open.spotify.com/intl-xx/playlist/{id}[?...]
///   https://play.spotify.com/playlist/{id}
///   spotify:playlist:{id}
///   a bare 22-char id
///
/// Rejects album/track/artist URLs and malformed input. Only recognized
/// Spotify playlist formats are ever forwarded to providers — there is no
/// generic URL-fetching endpoint (SSRF-safe by construction).
String? parseSpotifyPlaylistId(String input) {
  final trimmed = input.trim();
  if (trimmed.isEmpty) return null;
  final uriMatch =
      RegExp(r'^spotify:playlist:([A-Za-z0-9]{22})$').firstMatch(trimmed);
  if (uriMatch != null) return uriMatch.group(1);
  final urlMatch = RegExp(
          r'^https?://(?:open\.spotify\.com|play\.spotify\.com)/'
          r'(?:intl-[a-z-]+/)?playlist/([A-Za-z0-9]{22})(?:[/?].*)?$')
      .firstMatch(trimmed);
  if (urlMatch != null) return urlMatch.group(1);
  if (RegExp(r'^(?:https?://)?(?:open\.spotify\.com|play\.spotify\.com)/'
          r'(?:intl-[a-z-]+/)?(?:album|track|artist|episode|show)/')
      .hasMatch(trimmed)) {
    return null;
  }
  if (RegExp(r'^[A-Za-z0-9]{22}$').hasMatch(trimmed)) return trimmed;
  return null;
}

/// Structured rejection reason for a URL (for the error response).
ResolveError validatePlaylistUrl(String input) {
  final trimmed = input.trim();
  if (trimmed.isEmpty) {
    return const ResolveError(ResolveErrorCode.invalidUrl, 'No URL supplied');
  }
  if (parseSpotifyPlaylistId(trimmed) != null) {
    throw StateError('valid input passed to validator');
  }
  if (RegExp(r'^https?://').hasMatch(trimmed) ||
      trimmed.startsWith('spotify:')) {
    if (RegExp(r'(?:album|track|artist|episode|show)/').hasMatch(trimmed)) {
      final kind = RegExp(r'(?:album|track|artist|episode|show)')
          .firstMatch(trimmed)!
          .group(0);
      return ResolveError(ResolveErrorCode.unsupportedUrl,
          'The supplied URL is a Spotify $kind link, not a playlist');
    }
    return const ResolveError(ResolveErrorCode.unsupportedUrl,
        'The supplied URL is not a Spotify playlist');
  }
  return const ResolveError(
      ResolveErrorCode.invalidUrl, 'The supplied input is not a valid URL');
}

/// Builds the shelf handler. [clientIp] extracts the caller key from the
/// request for rate limiting.
Handler buildHandler({
  required PlaylistResolver resolver,
  RateLimiter? rateLimiter,
  String Function(Request request)? clientIp,
}) {
  final limiter = rateLimiter ??
      RateLimiter(maxRequests: 30, window: const Duration(minutes: 1));
  final ipOf = clientIp ??
      (Request r) => r.headers['x-forwarded-for']?.split(',').first.trim() ??
          (r.context['shelf.io.connection_info'] as HttpConnectionInfo?)
              ?.remoteAddress
              .address ??
          'unknown';

  final router = Router()
    ..get('/health', (Request request) async {
      return _json(200, {
        'ok': true,
        'service': 'synora-playlist-resolver',
        'configured': resolver.providers.any((p) {
          try {
            return p.canResolve(const PlaylistResolveInput(
                playlistId: 'x', url: 'https://open.spotify.com/playlist/x'));
          } catch (_) {
            return false;
          }
        }),
      });
    })
    ..post('/api/playlist/resolve', (Request request) async {
      final key = ipOf(request);
      if (!limiter.allow(key)) {
        return _json(429, {
          'success': false,
          'error': const ResolveError(
                  ResolveErrorCode.providerRateLimited,
                  'Too many requests — slow down and try again shortly')
              .toJson(),
        }, headers: {
          'retry-after': '${limiter.retryAfterSeconds(key)}',
        });
      }
      return _handleResolve(request, resolver);
    })
    ..get('/api/playlist/spotify/<playlistId>',
        (Request request, String playlistId) async {
      final key = ipOf(request);
      if (!limiter.allow(key)) {
        return _json(429, {
          'success': false,
          'error': const ResolveError(
                  ResolveErrorCode.providerRateLimited,
                  'Too many requests — slow down and try again shortly')
              .toJson(),
        }, headers: {
          'retry-after': '${limiter.retryAfterSeconds(key)}',
        });
      }
      return _handleResolve(request, resolver, idOverride: playlistId);
    });

  return const Pipeline()
      .addMiddleware(logRequests())
      .addHandler(router.call);
}

Future<Response> _handleResolve(Request request, PlaylistResolver resolver,
    {String? idOverride}) async {
  String playlistId;
  try {
    if (idOverride != null) {
      final raw = Uri.decodeComponent(idOverride);
      final parsed = parseSpotifyPlaylistId(raw);
      if (parsed == null) {
        return _error(validatePlaylistUrl(raw));
      }
      playlistId = parsed;
    } else {
      final body = await request.readAsString();
      if (body.length > 16 * 1024) {
        return _error(const ResolveError(
            ResolveErrorCode.invalidUrl, 'Request body too large'));
      }
      Map<String, dynamic> json;
      try {
        json = jsonDecode(body) as Map<String, dynamic>;
      } catch (_) {
        return _error(
            const ResolveError(ResolveErrorCode.invalidUrl, 'Invalid JSON body'));
      }
      final url = json['url'];
      if (url is! String) {
        return _error(const ResolveError(
            ResolveErrorCode.invalidUrl, 'A "url" field is required'));
      }
      final parsed = parseSpotifyPlaylistId(url);
      if (parsed == null) {
        return _error(validatePlaylistUrl(url));
      }
      playlistId = parsed;
    }
  } on ResolveError catch (e) {
    return _error(e);
  } catch (_) {
    return _error(const ResolveError(
        ResolveErrorCode.invalidUrl, 'Could not read the request'));
  }

  final refresh = request.url.queryParameters['refresh'] == 'true';
  try {
    final result = await resolver.resolve(
      PlaylistResolveInput(
        playlistId: playlistId,
        url: 'https://open.spotify.com/playlist/$playlistId',
      ),
      refresh: refresh,
    );
    return _json(200, result.toJson());
  } on ResolveError catch (e) {
    return _error(e);
  } catch (_) {
    return _error(const ResolveError(
        ResolveErrorCode.internalError, 'Internal resolver error'));
  }
}

Response _error(ResolveError e) {
  final status = switch (e.code) {
    ResolveErrorCode.invalidUrl ||
    ResolveErrorCode.unsupportedUrl => 400,
    ResolveErrorCode.playlistNotFound => 404,
    ResolveErrorCode.playlistPrivate ||
    ResolveErrorCode.permissionDenied => 403,
    ResolveErrorCode.authenticationRequired => 401,
    ResolveErrorCode.providerRateLimited => 429,
    ResolveErrorCode.noMetadataSource ||
    ResolveErrorCode.apifyActorError ||
    ResolveErrorCode.invalidScraperResponse => 502,
    ResolveErrorCode.providerUnavailable ||
    ResolveErrorCode.networkError ||
    ResolveErrorCode.apifyTimeout => 503,
    ResolveErrorCode.apifyAuth => 502,
    ResolveErrorCode.playlistEmpty => 404,
    ResolveErrorCode.internalError => 500,
  };
  return _json(status, {
    'success': false,
    'error': e.toJson(),
  });
}

Response _json(int status, Object body, {Map<String, String>? headers}) =>
    Response(status,
        body: jsonEncode(body),
        headers: {
          'content-type': 'application/json; charset=utf-8',
          ...?headers,
        });
