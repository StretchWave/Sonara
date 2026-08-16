import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';

import 'models.dart';

/// Centralized Apify configuration. Everything about the third-party actor
/// lives here (and in the environment), so swapping the scraper later never
/// touches the resolver chain or the Flutter app.
///
/// Expected environment variables:
///
/// ```env
/// APIFY_API_TOKEN=               # required; never shipped to the client
/// APIFY_ACTOR_ID=                # default: axlymxp/spotify-playlist-track-extractor
/// APIFY_MAX_TRACKS_PER_PLAYLIST= # 0 = all tracks
/// APIFY_ACTOR_INPUT_JSON=        # optional raw input template; {{url}} is replaced
/// APIFY_RUN_TIMEOUT_SECONDS=     # default 120
/// APIFY_POLL_INTERVAL_SECONDS=   # default 3
/// ```
class ApifySettings {
  final String? token;
  final String? actorId;
  final int maxTracksPerPlaylist;

  /// Optional raw actor input JSON template (may contain `{{url}}`).
  final Map<String, dynamic>? inputOverride;
  final Duration runTimeout;
  final Duration pollInterval;

  const ApifySettings({
    this.token,
    this.actorId,
    this.maxTracksPerPlaylist = 0,
    this.inputOverride,
    this.runTimeout = const Duration(seconds: 120),
    this.pollInterval = const Duration(seconds: 3),
  });

  bool get isConfigured => (token?.isNotEmpty ?? false) &&
      (actorId?.isNotEmpty ?? false);

  /// Builds the actor input for a single playlist URL. The default shape
  /// matches the free `axlymxp/spotify-playlist-track-extractor` actor
  /// (playlistUrls + ISRC on by default); operators can override it fully
  /// with [inputOverride] without touching code.
  Map<String, dynamic> buildInput(String url) {
    if (inputOverride != null) {
      return _substituteUrl(inputOverride!, url);
    }
    return {
      'playlistUrls': [url],
      'maxTracksPerPlaylist': maxTracksPerPlaylist,
      'includeISRC': true,
      'market': 'US',
      'locale': 'en',
    };
  }

  static Map<String, dynamic> _substituteUrl(
      Map<String, dynamic> template, String url) {
    return template.map((key, value) => MapEntry(key, _substitute(value, url)));
  }

  static dynamic _substitute(dynamic value, String url) {
    if (value is String) return value.replaceAll('{{url}}', url);
    if (value is Map) {
      return value.map(
          (k, v) => MapEntry(k, _substitute(v, url)));
    }
    if (value is List) return value.map((v) => _substitute(v, url)).toList();
    return value;
  }
}

/// Raised when no Apify token/actor is configured.
class ApifyNotConfigured implements Exception {
  final String message;
  ApifyNotConfigured([this.message = 'Apify credentials not configured']);
}

/// Client for the Apify API v2.
///
/// Flow: start an actor run with the playlist URL as input, poll until the
/// run reaches a terminal state (or [ApifySettings.runTimeout] elapses),
/// then download the dataset items in pages. The API token is only ever
/// sent to api.apify.com and never logged.
class ApifyClient {
  final Dio _dio;
  final ApifySettings settings;
  final void Function(String message) _log;

  ApifyClient({
    Dio? dio,
    required this.settings,
    void Function(String message)? log,
  })  : _dio = dio ??
            Dio(BaseOptions(
              baseUrl: 'https://api.apify.com/v2',
              connectTimeout: const Duration(seconds: 15),
              receiveTimeout: const Duration(seconds: 30),
            )),
        _log = log ?? ((m) => stdout.writeln('[apify] $m'));

  bool get isConfigured => settings.isConfigured;

  /// Runs the configured actor to completion and returns its dataset items.
  /// Throws [ResolveError] with structured codes for every failure mode.
  Future<List<Map<String, dynamic>>> runActor(
      String actorId, Map<String, dynamic> input) async {
    if (!isConfigured) throw ApifyNotConfigured();

    _log('Apify run started (actor $actorId)');
    final runId = await _startRun(actorId, input);
    final finalStatus = await _waitForRun(runId);
    _log('Apify run $runId finished with status $finalStatus');
    if (finalStatus != 'SUCCEEDED') {
      throw const ResolveError(ResolveErrorCode.apifyActorError,
          'The playlist scraper could not complete the run');
    }
    final datasetId = await _datasetIdFor(runId);
    final items = await _fetchDatasetItems(datasetId);
    _log('Apify run $runId produced ${items.length} dataset items');
    return items;
  }

  // ---------------------------------------------------------------------
  // Apify API calls
  // ---------------------------------------------------------------------

  Future<String> _startRun(String actorId, Map<String, dynamic> input) async {
    try {
      final res = await _dio.post(
        '/acts/$actorId/runs',
        data: {'input': input},
        options: Options(headers: _authHeaders()),
      );
      final data = (res.data as Map?)?['data'] as Map?;
      final runId = data?['id'] as String?;
      if (runId == null || runId.isEmpty) {
        throw const ResolveError(ResolveErrorCode.invalidScraperResponse,
            'Apify did not return a run id');
      }
      return runId;
    } on DioException catch (e) {
      throw _mapDioError(e, 'Could not start the Apify actor run');
    }
  }

  /// Polls the run until it is terminal or the timeout elapses.
  Future<String> _waitForRun(String runId) async {
    final deadline =
        DateTime.now().add(settings.runTimeout).millisecondsSinceEpoch;
    while (true) {
      final status = await _pollRun(runId);
      const terminal = {'SUCCEEDED', 'FAILED', 'ABORTED', 'TIMED-OUT'};
      if (terminal.contains(status)) return status;
      if (DateTime.now().millisecondsSinceEpoch > deadline) {
        throw const ResolveError(ResolveErrorCode.apifyTimeout,
            'The playlist scraper took too long to finish');
      }
      await Future.delayed(settings.pollInterval);
    }
  }

  Future<String> _pollRun(String runId) async {
    try {
      final res = await _dio.get('/actor-runs/$runId',
          options: Options(headers: _authHeaders()));
      final data = (res.data as Map?)?['data'] as Map?;
      final status = data?['status'] as String?;
      if (status == null || status.isEmpty) {
        throw const ResolveError(ResolveErrorCode.invalidScraperResponse,
            'Apify returned an invalid run status');
      }
      return status;
    } on DioException catch (e) {
      throw _mapDioError(e, 'Could not poll the Apify run');
    }
  }

  Future<String> _datasetIdFor(String runId) async {
    try {
      final res = await _dio.get('/actor-runs/$runId',
          options: Options(headers: _authHeaders()));
      final data = (res.data as Map?)?['data'] as Map?;
      final datasetId = data?['defaultDatasetId'] as String?;
      if (datasetId == null || datasetId.isEmpty) {
        throw const ResolveError(ResolveErrorCode.invalidScraperResponse,
            'Apify did not return a dataset for the run');
      }
      return datasetId;
    } on DioException catch (e) {
      throw _mapDioError(e, 'Could not read the Apify run dataset');
    }
  }

  Future<List<Map<String, dynamic>>> _fetchDatasetItems(
      String datasetId) async {
    final items = <Map<String, dynamic>>[];
    var offset = 0;
    const limit = 1000;
    while (true) {
      try {
        final res = await _dio.get(
          '/datasets/$datasetId/items',
          queryParameters: {
            'format': 'json',
            'clean': 'true',
            'limit': '$limit',
            'offset': '$offset',
          },
          options: Options(headers: _authHeaders()),
        );
        final data = res.data;
        if (data is! List) {
          throw const ResolveError(ResolveErrorCode.invalidScraperResponse,
              'Apify returned a malformed dataset');
        }
        final page = data.whereType<Map>().map((m) => Map<String, dynamic>.from(m)).toList();
        items.addAll(page);
        if (page.length < limit) break;
        offset += limit;
      } on DioException catch (e) {
        throw _mapDioError(e, 'Could not download the Apify dataset');
      }
    }
    return items;
  }

  Map<String, String> _authHeaders() =>
      {'Authorization': 'Bearer ${settings.token}'};

  ResolveError _mapDioError(DioException e, String fallback) {
    final status = e.response?.statusCode;
    if (status == 401 || status == 403) {
      return const ResolveError(ResolveErrorCode.apifyAuth,
          'The playlist scraper rejected the server credentials');
    }
    if (status == 429) {
      return const ResolveError(ResolveErrorCode.providerRateLimited,
          'The playlist scraper rate limit was reached');
    }
    if (e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.receiveTimeout ||
        e.type == DioExceptionType.sendTimeout) {
      return const ResolveError(
          ResolveErrorCode.apifyTimeout, 'The playlist scraper timed out');
    }
    return ResolveError(
        ResolveErrorCode.providerUnavailable, '$fallback: ${e.message}');
  }
}
