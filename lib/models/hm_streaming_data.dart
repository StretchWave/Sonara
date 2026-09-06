import 'package:sonara/services/stream_service.dart'show Audio;

class HMStreamingData {
  final bool playable;
  final String statusMSG;
  final Audio? lowQualityAudio;
  final Audio? highQualityAudio;

  /// Stable id of the provider that produced this stream
  /// (`qobuz`, `tidal`, `youtube_music`, ...). Empty when unknown.
  final String providerId;
  int qualityIndex = 1;
  HMStreamingData({
    required this.playable,
    required this.statusMSG,
    this.lowQualityAudio,
    this.highQualityAudio,
    this.providerId = '',
  });

  setQualityIndex(int index) {
    qualityIndex = index;
  }

  Audio? get audio {
    if (qualityIndex == 0 && lowQualityAudio != null) return lowQualityAudio;
    // Fall back to whichever format is present so a missing "low" or "high"
    // entry never leaves playback with a null URL.
    return highQualityAudio ?? lowQualityAudio;
  }

  factory HMStreamingData.fromJson(json) {
    if(!json['playable']) {
      return HMStreamingData(
        playable: false,
        statusMSG: json['statusMSG'],
        providerId: (json['providerId'] as String?) ?? '',
      );
    }
    final lowQualityAudio = Audio.fromJson(json['lowQualityAudio']);
    final highQualityAudio = Audio.fromJson(json['highQualityAudio']);
    return HMStreamingData(
        playable: json['playable'],
        statusMSG: json['statusMSG'],
        providerId: (json['providerId'] as String?) ?? '',
        lowQualityAudio: lowQualityAudio,
        highQualityAudio: highQualityAudio);
  }

  Map<String, dynamic> toJson() => {
        "playable": playable,
        "statusMSG": statusMSG,
        "providerId": providerId,
        "lowQualityAudio": lowQualityAudio?.toJson(),
        "highQualityAudio": highQualityAudio?.toJson(),
      };
}
