/// Transport models for resolved streams.
///
/// Stream resolution itself lives in `providers/` — see
/// [StreamRouter] and [YouTubeAudioProvider].
library;

class StreamProvider {
  final bool playable;
  final List<Audio>? audioFormats;
  final String statusMSG;

  /// Stable id of the provider that produced this stream
  /// (`qobuz`, `tidal`, `youtube_music`, ...). Empty when unknown.
  final String providerId;
  StreamProvider(
      {required this.playable,
      this.audioFormats,
      this.statusMSG = "",
      this.providerId = ""});

  Audio? get highestQualityAudio =>
      audioFormats?.lastWhere((item) => item.itag == 251 || item.itag == 140,
          orElse: () => audioFormats!.first);

  Audio? get highestBitrateMp4aAudio =>
      audioFormats?.lastWhere((item) => item.itag == 140 || item.itag == 139,
          orElse: () => audioFormats!.first);

  Audio? get highestBitrateOpusAudio =>
      audioFormats?.lastWhere((item) => item.itag == 251 || item.itag == 250,
          orElse: () => audioFormats!.first);

  Audio? get lowQualityAudio =>
      audioFormats?.lastWhere((item) => item.itag == 249 || item.itag == 139,
          orElse: () => audioFormats!.first);

  Map<String, dynamic> get hmStreamingData {
    return {
      "playable": playable,
      "statusMSG": statusMSG,
      "providerId": providerId,
      "lowQualityAudio": lowQualityAudio?.toJson(),
      "highQualityAudio": highestQualityAudio?.toJson()
    };
  }

  Map<String, dynamic> toJson() => hmStreamingData;
}

class Audio {
  final int itag;
  final Codec audioCodec;
  final int bitrate;
  final int duration;
  final int size;
  final double loudnessDb;
  final String url;

  /// Optional format metadata from lossless providers, e.g. "Qobuz Hi-Res
  /// FLAC 24-bit/192 kHz". Null for YouTube streams.
  final String? label;
  final String? mimeType;
  final int? sampleRate;
  final int? bitDepth;

  /// Optional HTTP headers required for streaming/downloading (e.g. User-Agent).
  final Map<String, String>? headers;

  Audio(
      {required this.itag,
      required this.audioCodec,
      required this.bitrate,
      required this.duration,
      required this.loudnessDb,
      required this.url,
      required this.size,
      this.label,
      this.mimeType,
      this.sampleRate,
      this.bitDepth,
      this.headers});

  Map<String, dynamic> toJson() => {
        "itag": itag,
        "audioCodec": audioCodec.toString(),
        "bitrate": bitrate,
        "loudnessDb": loudnessDb,
        "url": url,
        "approxDurationMs": duration,
        "size": size,
        if (label != null) "label": label,
        if (mimeType != null) "mimeType": mimeType,
        if (sampleRate != null) "sampleRate": sampleRate,
        if (bitDepth != null) "bitDepth": bitDepth,
        if (headers != null) "headers": headers,
      };

  factory Audio.fromJson(json) => Audio(
      audioCodec: Codec.fromName((json["audioCodec"] as String?) ?? ""),
      itag: json['itag'],
      duration: json["approxDurationMs"] ?? 0,
      bitrate: json["bitrate"] ?? 0,
      loudnessDb: (json['loudnessDb'])?.toDouble() ?? 0.0,
      url: json['url'],
      size: json["size"] ?? 0,
      label: json['label'] as String?,
      mimeType: json['mimeType'] as String?,
      sampleRate: json['sampleRate'] is int ? json['sampleRate'] as int : null,
      bitDepth: json['bitDepth'] is int ? json['bitDepth'] as int : null,
      headers: json['headers'] != null
          ? Map<String, String>.from(json['headers'] as Map)
          : null);
}

enum Codec {
  mp4a,
  opus,
  flac,
  mp3;

  /// Maps a codec name (as produced by [Audio.toJson]) back to a [Codec].
  /// Unknown names fall back to [Codec.opus] for backward compatibility
  /// with old cached entries.
  static Codec fromName(String name) {
    if (name.contains('flac')) return Codec.flac;
    if (name.contains('mp3')) return Codec.mp3;
    if (name.contains('mp4a') || name.contains('aac')) return Codec.mp4a;
    return Codec.opus;
  }
}
