import 'dart:convert';

import 'package:dio/dio.dart';

import 'playlist_metadata_provider.dart';
import '/services/spotify/public_spotify_client.dart';
import '/services/spotify/spotify_api_client.dart';
import '/services/spotify/spotify_source_track.dart';

/// Public metadata and track list provider that extracts playlist and album
/// data directly from Spotify's web embed pages (`open.spotify.com/embed/...`).
///
/// This does not require any Spotify sign-in, developer account, PKCE OAuth,
/// or external backend server. It parses the structured Next.js payload
/// (`<script id="__NEXT_DATA__">`) embedded in Spotify's public embed page,
/// yielding full track names, artist lists, track durations, explicit flags,
/// and artwork.
class SpotifyEmbedProvider implements PlaylistMetadataProvider {
  final Dio _dio;

  final PublicSpotifyClient _publicClient;

  SpotifyEmbedProvider({Dio? dio, PublicSpotifyClient? publicClient})
      : _dio = dio ??
            Dio(BaseOptions(
              baseUrl: 'https://open.spotify.com',
              connectTimeout: const Duration(seconds: 15),
              receiveTimeout: const Duration(seconds: 20),
              headers: {
                'User-Agent':
                    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
                'Accept':
                    'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
                'Accept-Language': 'en-US,en;q=0.9',
              },
            )),
        _publicClient = publicClient ??
            PublicSpotifyClient(
              embedDio: dio ??
                  Dio(BaseOptions(
                    baseUrl: 'https://open.spotify.com',
                    connectTimeout: const Duration(seconds: 15),
                    receiveTimeout: const Duration(seconds: 20),
                    headers: {
                      'User-Agent':
                          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
                      'Accept':
                          'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
                      'Accept-Language': 'en-US,en;q=0.9',
                    },
                  )),
            );

  @override
  String get id => 'spotify-embed';

  @override
  String get displayName => 'Spotify public';

  /// Matches Spotify album URLs/URIs if not already matched as a playlist.
  static String? parseAlbumId(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) return null;
    final uriMatch =
        RegExp(r'^spotify:album:([A-Za-z0-9]{22})$').firstMatch(trimmed);
    if (uriMatch != null) return uriMatch.group(1);
    final urlMatch = RegExp(
            r'^https?://(?:open\.spotify\.com|play\.spotify\.com|spotify\.link)/'
            r'(?:intl-[a-z-]+/)?album/([A-Za-z0-9]{22})(?:[/?].*)?$')
        .firstMatch(trimmed);
    return urlMatch?.group(1);
  }

  @override
  bool canHandle(Uri url) {
    final str = url.toString();
    return SpotifyApiClient.parsePlaylistId(str) != null ||
        parseAlbumId(str) != null;
  }

  @override
  Future<PlaylistMetadataResult> fetchPlaylist(Uri url) async {
    final str = url.toString();
    final playlistId = SpotifyApiClient.parsePlaylistId(str);
    final albumId = playlistId == null ? parseAlbumId(str) : null;
    final targetId = playlistId ?? albumId;

    if (targetId == null) {
      return PlaylistMetadataResult(
        status: PlaylistMetadataStatus.unsupported,
        message: SpotifyApiClient.invalidPlaylistReason(str),
      );
    }

    final isAlbum = albumId != null;

    // For playlists, try full pagination first through the anonymous GraphQL client.
    if (!isAlbum) {
      try {
        final result = await _publicClient.fetchPlaylist(targetId);
        if (result.tracks.isNotEmpty) {
          return PlaylistMetadataResult(
            status: PlaylistMetadataStatus.success,
            playlistId: targetId,
            name: result.name,
            description: result.description,
            artworkUrl: result.artworkUrl,
            tracks: result.tracks,
            message: 'Spotify public (${result.tracks.length} tracks)',
          );
        }
      } catch (_) {
        // Fall through to embed page HTML scraping on any GraphQL failure.
      }
    }

    final endpoint = isAlbum ? '/embed/album/$targetId' : '/embed/playlist/$targetId';

    try {
      final res = await _dio.get<String>(
        endpoint,
        options: Options(responseType: ResponseType.plain),
      );

      final html = res.data ?? '';
      if (html.isEmpty) {
        return PlaylistMetadataResult(
          status: PlaylistMetadataStatus.networkError,
          playlistId: targetId,
          message: 'Received empty response from Spotify embed',
        );
      }

      return _parseEmbedHtml(targetId, html, isAlbum: isAlbum);
    } on DioException catch (e) {
      // If a playlist URL failed with 404, attempt album endpoint as a fallback.
      if (!isAlbum && e.response?.statusCode == 404) {
        try {
          final albumRes = await _dio.get<String>(
            '/embed/album/$targetId',
            options: Options(responseType: ResponseType.plain),
          );
          final html = albumRes.data ?? '';
          if (html.isNotEmpty) {
            return _parseEmbedHtml(targetId, html, isAlbum: true);
          }
        } catch (_) {
          // Fall through to primary error.
        }
      }
      return _mapError(targetId, e);
    } catch (e) {
      return PlaylistMetadataResult(
        status: PlaylistMetadataStatus.networkError,
        playlistId: targetId,
        message: e.toString(),
      );
    }
  }

  PlaylistMetadataResult _parseEmbedHtml(String targetId, String html,
      {required bool isAlbum}) {
    final match = RegExp(
      r'<script id="__NEXT_DATA__" type="application/json">(.*?)</script>',
      dotAll: true,
    ).firstMatch(html);

    if (match == null) {
      return PlaylistMetadataResult(
        status: PlaylistMetadataStatus.networkError,
        playlistId: targetId,
        message: 'Could not extract playlist data from Spotify embed page',
      );
    }

    final Map<String, dynamic> json;
    try {
      json = jsonDecode(match.group(1)!) as Map<String, dynamic>;
    } catch (e) {
      return PlaylistMetadataResult(
        status: PlaylistMetadataStatus.networkError,
        playlistId: targetId,
        message: 'Could not parse Spotify embed JSON payload: $e',
      );
    }

    final entity = (json['props']?['pageProps']?['state']?['data']?['entity']
        as Map?) ??
        const {};

    final title = (entity['title'] ?? entity['name']) as String?;
    final subtitle = entity['subtitle'] as String?;
    final description = entity['description'] as String? ?? subtitle;

    // Highest-resolution artwork.
    String? artworkUrl;
    final images = (entity['visualIdentity']?['image'] as List?)
        ?.whereType<Map>()
        .toList();
    if (images != null && images.isNotEmpty) {
      artworkUrl = images.last['url'] as String?;
    }
    artworkUrl ??= (entity['coverArt']?['sources'] as List?)
        ?.whereType<Map>()
        .firstOrNull?['url'] as String?;

    final rawTrackList = (entity['trackList'] as List?)?.whereType<Map>() ?? [];
    final tracks = <SpotifySourceTrack>[];

    for (final raw in rawTrackList) {
      final uri = raw['uri'] as String? ?? '';
      final spotifyId = uri.startsWith('spotify:track:')
          ? uri.substring('spotify:track:'.length)
          : (raw['id'] as String? ?? raw['uid'] as String? ?? '');
      final trackTitle =
          (raw['title'] as String? ?? raw['name'] as String? ?? '').trim();
      if (trackTitle.isEmpty) continue;

      // Extract artists list: prefer raw['artists'] list if present, otherwise
      // parse the comma-separated subtitle string provided by Spotify embed.
      final rawArtists = (raw['artists'] as List?)
          ?.whereType<Map>()
          .map((a) => a['name'] as String?)
          .whereType<String>()
          .toList();

      final List<String> artists;
      if (rawArtists != null && rawArtists.isNotEmpty) {
        artists = rawArtists;
      } else {
        final trackSubtitle = raw['subtitle'] as String?;
        if (trackSubtitle != null && trackSubtitle.trim().isNotEmpty) {
          artists = trackSubtitle
              .split(RegExp(r',\s*'))
              .map((s) => s.trim())
              .where((s) => s.isNotEmpty)
              .toList();
        } else {
          artists = const [];
        }
      }

      final durationMs = (raw['duration'] as num?)?.toInt() ?? 0;
      final explicit = (raw['isExplicit'] as bool?) ?? false;

      // Track artwork: use track visual identity if present, otherwise fallback
      // to playlist/album artwork.
      final trackImages = (raw['visualIdentity']?['image'] as List?)
          ?.whereType<Map>()
          .toList();
      final trackArtwork = trackImages != null && trackImages.isNotEmpty
          ? trackImages.last['url'] as String?
          : (raw['coverArt']?['sources'] as List?)
                  ?.whereType<Map>()
                  .firstOrNull?['url'] as String? ??
              artworkUrl;

      tracks.add(SpotifySourceTrack(
        spotifyId: spotifyId,
        title: trackTitle,
        artists: artists,
        album: title,
        durationMs: durationMs,
        explicit: explicit,
        artworkUrl: trackArtwork,
        trackNumber: tracks.length + 1,
      ));
    }

    if (tracks.isEmpty) {
      if (title != null || artworkUrl != null) {
        return PlaylistMetadataResult(
          status: PlaylistMetadataStatus.partialSuccess,
          playlistId: targetId,
          name: title,
          description: description,
          artworkUrl: artworkUrl,
          message: 'Spotify embed identified this playlist but found no tracks',
        );
      }
      return PlaylistMetadataResult(
        status: PlaylistMetadataStatus.notFound,
        playlistId: targetId,
        message: 'Could not find any playlist details',
      );
    }

    return PlaylistMetadataResult(
      status: PlaylistMetadataStatus.success,
      playlistId: targetId,
      name: title,
      description: description,
      artworkUrl: artworkUrl,
      tracks: tracks,
      message: 'Spotify Web Embed',
    );
  }

  PlaylistMetadataResult _mapError(String playlistId, DioException e) {
    final statusCode = e.response?.statusCode;
    if (statusCode == 404) {
      return PlaylistMetadataResult(
        status: PlaylistMetadataStatus.notFound,
        playlistId: playlistId,
        message: 'Playlist not found on Spotify — it may be private or deleted',
      );
    }
    if (statusCode == 429) {
      return PlaylistMetadataResult(
        status: PlaylistMetadataStatus.rateLimited,
        playlistId: playlistId,
        message: 'Rate limited by Spotify — wait a moment and try again',
      );
    }
    if (e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.receiveTimeout ||
        e.type == DioExceptionType.connectionError) {
      return PlaylistMetadataResult(
        status: PlaylistMetadataStatus.networkError,
        playlistId: playlistId,
        message: 'Could not reach Spotify embed service: ${e.message}',
      );
    }
    return PlaylistMetadataResult(
      status: PlaylistMetadataStatus.networkError,
      playlistId: playlistId,
      message: 'Spotify embed error (${statusCode ?? e.type}): ${e.message}',
    );
  }
}
