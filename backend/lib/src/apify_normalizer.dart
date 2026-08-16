/// Normalizes raw scraper output rows into the backend's [NormalizedTrack].
///
/// Different Apify actors emit different property names (and even the same
/// actor changes shape over time), so every field is extracted through a
/// list of aliases and validated before use. Nothing from the scraper is
/// trusted blindly: strings are trimmed/capped, numbers are range-checked,
/// and malformed rows become unavailable placeholders instead of crashing
/// the import.
library;

import 'models.dart';

/// Max values applied to every scraper field (input-size protection).
const int _maxTitleLength = 500;
const int _maxArtistLength = 200;
const int _maxArtists = 100;
const int _maxAlbumLength = 500;
const int _maxIsrcLength = 24;
const int _maxPosition = 1000000;

/// First non-empty string found under any of [keys], probing nested maps
/// for dotted paths (e.g. `track.name`).
String? _string(Map<String, dynamic> raw, List<String> keys) {
  for (final key in keys) {
    final value = _lookup(raw, key);
    if (value is String && value.trim().isNotEmpty) {
      return value.trim();
    }
    if (value is num) return value.toString();
  }
  return null;
}

/// Looks up [path] in [raw], walking dotted segments and list-of-maps.
dynamic _lookup(dynamic container, String path) {
  final segments = path.split('.');
  dynamic current = container;
  for (var i = 0; i < segments.length; i++) {
    final segment = segments[i];
    if (current is Map) {
      current = current[segment];
    } else if (current is List && segment == 'first') {
      current = current.isEmpty ? null : current.first;
    } else {
      return null;
    }
  }
  return current;
}

int _firstInt(Map<String, dynamic> raw, List<String> keys, {int fallback = 0}) {
  for (final key in keys) {
    final value = _lookup(raw, key);
    if (value is num && value.isFinite) return value.toInt();
    if (value is String) {
      final parsed = int.tryParse(value.replaceAll(RegExp(r'[^0-9]'), ''));
      if (parsed != null) return parsed;
    }
  }
  return fallback;
}

bool _firstBool(Map<String, dynamic> raw, List<String> keys) {
  for (final key in keys) {
    final value = _lookup(raw, key);
    if (value is bool) return value;
    if (value is String) {
      final lowered = value.trim().toLowerCase();
      if (lowered == 'true' || lowered == 'yes' || lowered == '1') return true;
    }
    if (value is num && value == 1) return true;
  }
  return false;
}

/// Extracts an artist list from the common shapes:
///   artists: ["A"], artists: [{"name": "A"}], artistNames: "A, B",
///   artist: "A", track.artists: [...], artistsNames: ["A"]
List<String> _artists(Map<String, dynamic> raw) {
  final result = <String>[];
  void addName(String? name) {
    final trimmed = name?.trim() ?? '';
    if (trimmed.isEmpty || trimmed.length > _maxArtistLength) return;
    if (result.contains(trimmed)) return;
    if (result.length >= _maxArtists) return;
    result.add(trimmed);
  }

  final artistsValue = _lookup(raw, 'artists');
  if (artistsValue is List) {
    for (final a in artistsValue) {
      if (a is String) addName(a);
      if (a is Map) {
        addName(a['name'] as String?);
        addName(a['artist'] as String?);
      }
    }
  } else if (artistsValue is String) {
    addName(artistsValue);
  }
  for (final key in ['artistNames', 'artist_names', 'artistsNames']) {
    final v = _lookup(raw, key);
    if (v is List) {
      for (final a in v) {
        if (a is String) addName(a);
      }
    } else if (v is String) {
      // Some actors join artists with commas.
      for (final part in v.split(',')) {
        addName(part);
      }
    }
  }
  addName(_string(raw, ['artist', 'artistName', 'artist_name']));
  if (result.isEmpty) {
    // track.artists fallback.
    final nested = _lookup(raw, 'track.artists');
    if (nested is List) {
      for (final a in nested) {
        if (a is Map) addName(a['name'] as String?);
      }
    }
  }
  return result;
}

/// Duration in milliseconds from the common shapes:
///   durationMs: 213000, duration: 213000, length: 213 (seconds),
///   durationSec: 213, durationText: "3:33"
int _durationMs(Map<String, dynamic> raw) {
  final direct = _firstInt(raw, ['durationMs', 'duration_ms']);
  if (direct > 0) return direct.clamp(0, 86400000);

  for (final key in ['duration', 'length']) {
    final value = _lookup(raw, key);
    if (value is num && value.isFinite && value > 0) {
      // `length`/`duration` are seconds on some actors (< 60000 is not a
      // plausible millisecond value), milliseconds on others.
      final asSeconds = value < 60000;
      final ms = asSeconds ? (value * 1000).round() : value.round();
      return ms.clamp(0, 86400000);
    }
  }
  final secs = _firstInt(raw, ['durationSec', 'duration_sec', 'durationSeconds']);
  if (secs > 0) return (secs * 1000).clamp(0, 86400000);

  final text = _string(raw, ['durationText', 'duration_text']);
  if (text != null) {
    // Formats seen in the wild: "3:33" (m:ss) and "1:03:33" (h:mm:ss).
    final match = RegExp(r'(\d+):(\d{2})(?::(\d{2}))?').firstMatch(text);
    if (match != null) {
      final hours = match.group(3) != null ? int.parse(match.group(1)!) : 0;
      final minutes = int.parse(match.group(3) != null ? match.group(2)! : match.group(1)!);
      final seconds = int.parse(match.group(3) != null ? match.group(3)! : match.group(2)!);
      return ((hours * 3600) + (minutes * 60) + seconds) * 1000;
    }
  }
  return 0;
}

/// The track's Spotify id, from the common shapes:
///   trackId/id/spotifyId: "4cOdK2wGLETKBW3PvgPWqT"
///   trackUri/uri: "spotify:track:4cOdK2wGLETKBW3PvgPWqT"
///   trackUrl/url: "https://open.spotify.com/track/4cOdK2wGLETKBW3PvgPWqT"
String _spotifyId(Map<String, dynamic> raw) {
  final rawId = _string(raw, ['trackId', 'track_id', 'id', 'spotifyId']);
  final uri = _string(raw, ['trackUri', 'track_uri', 'uri']);
  final url = _string(raw, [
    'trackUrl',
    'track_url',
    'spotifyUrl',
    'spotify_url',
    'url',
    'track.url',
  ]);
  final value = rawId ?? uri ?? url;
  if (value == null) return '';
  final cleaned = value.startsWith('spotify:track:')
      ? value.substring('spotify:track:'.length)
      : value;
  final idMatch = RegExp(r'/([A-Za-z0-9]{22})(?:[/?]|$)').firstMatch(cleaned);
  if (idMatch != null) return idMatch.group(1)!;
  return RegExp(r'^[A-Za-z0-9]{22}$').hasMatch(cleaned) ? cleaned : '';
}

String? _artwork(Map<String, dynamic> raw) {
  final direct = _string(raw, [
    'imageUrl',
    'image_url',
    'albumArt',
    'album_art',
    'artworkUrl',
    'artwork_url',
    'coverUrl',
    'cover_url',
    'thumbnailUrl',
    'image',
    'album.imageUrl',
    'album.image_url',
  ]);
  if (direct != null && direct.startsWith('http')) return direct;
  final images = _lookup(raw, 'images');
  if (images is List && images.isNotEmpty) {
    final first = images.first;
    if (first is String && first.startsWith('http')) return first;
    if (first is Map) {
      final u = first['url'];
      if (u is String && u.startsWith('http')) return u;
    }
  }
  final albumImages = _lookup(raw, 'album.images');
  if (albumImages is List && albumImages.isNotEmpty) {
    final first = albumImages.first;
    if (first is Map) {
      final u = first['url'];
      if (u is String && u.startsWith('http')) return u;
    }
  }
  return null;
}

/// Normalizes one scraper row. Rows with neither a title nor an id become
/// unavailable placeholders (empty fields) so partial playlists keep their
/// positions and counts.
NormalizedTrack normalizeApifyTrack(Map<String, dynamic> raw, int index) {
  final title = _string(raw, ['trackName', 'track_name', 'title', 'name', 'track.name']) ?? '';
  final id = _spotifyId(raw);
  if (title.isEmpty && id.isEmpty) {
    return NormalizedTrack(
      sourceTrackId: '',
      position: index,
      title: '',
      artists: const [],
      durationMs: 0,
    );
  }

  final album = _string(raw, [
    'albumName',
    'album_name',
    'album',
    'album.name',
    'track.album',
    'track.album.name',
  ]);
  final albumArtist = _string(raw, [
    'albumArtist',
    'album_artist',
    'album.artists.first.name',
    'track.album.artists.first.name',
  ]);
  final rawPosition = _firstInt(raw, ['position', 'index', 'order'], fallback: index + 1);
  // Actors report 1-based positions; the backend's normalized model is 0-based.
  final position =
      (rawPosition > 0 ? rawPosition - 1 : index).clamp(0, _maxPosition);
  final releaseDate = _string(raw, [
    'releaseDate',
    'release_date',
    'album.release_date',
    'album.releaseDate',
    'track.album.release_date',
    'track.album.releaseDate',
  ]);
  final isrc = _string(raw, ['isrc', 'ISRC', 'external_ids.isrc', 'externalIds.isrc']);
  final artwork = _artwork(raw);

  return NormalizedTrack(
    sourceTrackId: id,
    position: position,
    title: title.length > _maxTitleLength ? title.substring(0, _maxTitleLength) : title,
    artists: _artists(raw),
    album: (album != null && album.length <= _maxAlbumLength) ? album : null,
    albumArtist: albumArtist,
    durationMs: _durationMs(raw),
    isrc: (isrc != null && isrc.length <= _maxIsrcLength) ? isrc : null,
    releaseDate: releaseDate,
    explicit: _firstBool(raw, ['explicit', 'isExplicit', 'is_explicit']),
    artworkUrl: artwork,
  );
}

/// Best-effort playlist-level metadata from the scraper rows (many actors
/// stamp every row with playlist context).
NormalizedPlaylist playlistMetaFromItems(
    List<Map<String, dynamic>> items, String fallbackId) {
  String? name;
  String? artworkUrl;
  var trackCount = 0;
  for (final item in items) {
    name ??= _string(item, ['playlistName', 'playlist_name']);
    artworkUrl ??= _artworkForPlaylist(item);
    final total = _firstInt(item, ['playlistTotalTracks', 'playlist_total_tracks']);
    if (total > trackCount) trackCount = total;
  }
  return NormalizedPlaylist(
    id: fallbackId,
    name: name ?? 'Spotify Playlist',
    artworkUrl: artworkUrl,
    trackCount: trackCount,
  );
}

String? _artworkForPlaylist(Map<String, dynamic> item) {
  final direct = _string(item, ['playlistImage', 'playlistImageUrl', 'playlist_image_url']);
  if (direct != null && direct.startsWith('http')) return direct;
  return _artwork(item);
}
