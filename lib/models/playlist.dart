import 'package:audio_service/audio_service.dart' show MediaItem;

import '../models/thumbnail.dart';

class PlaylistContent {
  PlaylistContent({required this.title, required this.playlistList});
  final String title;
  final List<Playlist> playlistList;

  factory PlaylistContent.fromJson(Map<dynamic, dynamic> json) =>
      PlaylistContent(
          title: json['title'],
          playlistList: (json['playlists'] as List)
              .map((e) => Playlist.fromJson(e))
              .toList());
  Map<String, dynamic> toJson() => {
        "type": "Playlist Content",
        "title": title,
        "playlists": playlistList.map((e) => e.toJson()).toList()
      };
}

class Playlist {
  Playlist(
      {required this.title,
      required this.playlistId,
      this.description,
      required this.thumbnailUrl,
      this.songCount,
      this.isPipedPlaylist = false,
      this.isCloudPlaylist = true,
      this.spotifyPlaylistId,
      this.lastSpotifySyncedAt});
  final String playlistId;
  String title;
  final bool isPipedPlaylist;
  final String? description;
  String thumbnailUrl;
  final String? songCount;
  final bool isCloudPlaylist;

  /// The Spotify playlist ID this local playlist is connected to (if any).
  /// When non-null, the playlist can be incrementally synced with Spotify.
  final String? spotifyPlaylistId;

  /// Epoch milliseconds of the last successful Spotify sync.
  final int? lastSpotifySyncedAt;

  /// Whether this playlist is connected to a Spotify playlist.
  bool get isSpotifyConnected =>
      spotifyPlaylistId != null && spotifyPlaylistId!.isNotEmpty;
  static const thumbPlaceholderUrl =
      "https://raw.githubusercontent.com/StretchWave/Sonara/refs/heads/main/playlist_placeholder.png";

  factory Playlist.fromJson(Map<dynamic, dynamic> json) => Playlist(
      title: json["title"],
      playlistId: json["playlistId"] ?? json["browseId"],
      thumbnailUrl: (json["thumbnails"][0]["url"]).isEmpty
          ? Thumbnail(thumbPlaceholderUrl).extraHigh
          : Thumbnail(json["thumbnails"][0]["url"]).extraHigh,
      description: json["description"] ?? "Playlist",
      songCount: json['itemCount'],
      isPipedPlaylist: json["isPipedPlaylist"] ?? false,
      isCloudPlaylist: json["isCloudPlaylist"] ?? true,
      spotifyPlaylistId: json["spotifyPlaylistId"] as String?,
      lastSpotifySyncedAt: (json["lastSpotifySyncedAt"] as num?)?.toInt());

  Map<String, dynamic> toJson() => {
        "title": title,
        "playlistId": playlistId,
        "description": description,
        'thumbnails': [
          {'url': thumbnailUrl}
        ],
        "itemCount": songCount,
        "isPipedPlaylist": isPipedPlaylist,
        "isCloudPlaylist": isCloudPlaylist,
        if (spotifyPlaylistId != null) "spotifyPlaylistId": spotifyPlaylistId,
        if (lastSpotifySyncedAt != null) "lastSpotifySyncedAt": lastSpotifySyncedAt,
      };

  Playlist copyWith({
    String? title,
    String? thumbnailUrl,
    String? spotifyPlaylistId,
    int? lastSpotifySyncedAt,
  }) {
    return Playlist(
        title: title ?? this.title,
        playlistId: playlistId,
        thumbnailUrl: thumbnailUrl ?? this.thumbnailUrl,
        description: description,
        songCount: songCount,
        isPipedPlaylist: isPipedPlaylist,
        isCloudPlaylist: isCloudPlaylist,
        spotifyPlaylistId: spotifyPlaylistId ?? this.spotifyPlaylistId,
        lastSpotifySyncedAt: lastSpotifySyncedAt ?? this.lastSpotifySyncedAt);
  }

  // Converts this object to a MediaItem object.
  // This is used to display the playlist in Android auto.
  MediaItem toMediaItem() {
    return MediaItem(
        id: playlistId,
        title: title,
        artUri: Uri.parse(thumbnailUrl),
        playable: false);
  }

  set newTitle(String title) {
    this.title = title;
  }
}
