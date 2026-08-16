import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:synora_backend/synora_backend.dart';

void main() async {
  final parsedPort = int.tryParse(Platform.environment['PORT'] ?? '');
  final port = (parsedPort == null || parsedPort <= 0) ? 3000 : parsedPort;
  final host = Platform.environment['HOST'] ?? '0.0.0.0';

  final cacheTtl = Duration(
      minutes: int.tryParse(Platform.environment['CACHE_TTL_MINUTES'] ?? '') ??
          60);
  final rateLimit =
      int.tryParse(Platform.environment['RATE_LIMIT_PER_MINUTE'] ?? '') ?? 30;

  final spotifyClient = SpotifyClient(
    dio: Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 30),
    )),
    clientId: Platform.environment['SPOTIFY_CLIENT_ID'],
    clientSecret: Platform.environment['SPOTIFY_CLIENT_SECRET'],
  );

  final apifyInputOverride = Platform.environment['APIFY_ACTOR_INPUT_JSON'];
  final apifySettings = ApifySettings(
    token: Platform.environment['APIFY_API_TOKEN'],
    actorId: Platform.environment['APIFY_ACTOR_ID'],
    maxTracksPerPlaylist:
        int.tryParse(Platform.environment['APIFY_MAX_TRACKS_PER_PLAYLIST'] ?? '') ?? 0,
    inputOverride:
        (apifyInputOverride != null && apifyInputOverride.isNotEmpty)
            ? Map<String, dynamic>.from(jsonDecode(apifyInputOverride))
            : null,
    runTimeout: Duration(
        seconds: int.tryParse(
                Platform.environment['APIFY_RUN_TIMEOUT_SECONDS'] ?? '') ??
            120),
    pollInterval: Duration(
        seconds: int.tryParse(
                Platform.environment['APIFY_POLL_INTERVAL_SECONDS'] ?? '') ??
            3),
  );

  final cache = ResolutionCache(ttl: cacheTtl);
  final resolver = PlaylistResolver(
    providers: [
      CachedPlaylistProvider(cache),
      // Free anonymous path — resolves public playlists with no credentials.
      PublicSpotifyProvider(PublicSpotifyClient()),
      ApifyPlaylistProvider(ApifyClient(settings: apifySettings)),
      SpotifyOfficialProvider(spotifyClient),
      // Future third-party providers slot in here behind the same
      // PlaylistMetadataProvider interface.
    ],
    cache: cache,
  );

  final handler = buildHandler(
    resolver: resolver,
    rateLimiter: RateLimiter(
      maxRequests: rateLimit,
      window: const Duration(minutes: 1),
    ),
  );

  final server = await shelf_io.serve(handler, host, port);
  stdout.writeln('Synora playlist resolver listening on http://$host:${server.port}');
  stdout.writeln('Spotify credentials configured: ${spotifyClient.isConfigured}');
  stdout.writeln('Apify scraper configured: ${apifySettings.isConfigured}');
}
