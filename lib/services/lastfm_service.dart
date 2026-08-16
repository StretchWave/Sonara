import 'dart:async';
import 'dart:convert';

import 'package:audio_service/audio_service.dart';
import 'package:crypto/crypto.dart' as crypto;
import 'package:dio/dio.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';
import 'package:url_launcher/url_launcher.dart';

import '../utils/helper.dart';

/// Last.fm scrobbler.
///
/// Requires the user to create a free API application at
/// https://www.last.fm/api/account/create and provide the API key + shared
/// secret in the settings. The app then walks through the standard
/// Last.fm authorization flow (token -> browser -> session key) and
/// scrobbles tracks that have been listened to for at least 50% of their
/// duration (or 4 minutes), per Last.fm scrobbling rules.
class LastFmService extends GetxService {
  static const String _baseUrl = 'https://ws.audioscrobbler.com/2.0/';
  static const String _authPageUrl = 'https://www.last.fm/api/auth/';

  final Dio _dio = Dio();

  final enabled = false.obs;
  final username = ''.obs;
  final sessionKey = ''.obs;
  final apiKey = ''.obs;
  final apiSecret = ''.obs;
  final isConnected = false.obs;
  final statusMessage = ''.obs;

  String? _pendingToken;
  MediaItem? _currentSong;
  bool _scrobblePending = false;
  bool _isPlaying = false;
  Duration? _lastPosition;
  int _currentListenMs = 0;
  StreamSubscription<MediaItem?>? _mediaItemSub;
  StreamSubscription<PlaybackState>? _playbackStateSub;
  StreamSubscription<Duration>? _positionSub;

  @override
  void onInit() {
    super.onInit();
    final prefs = Hive.box("AppPrefs");
    enabled.value = prefs.get("lastfmEnabled") ?? false;
    username.value = prefs.get("lastfmUsername") ?? "";
    sessionKey.value = prefs.get("lastfmSessionKey") ?? "";
    apiKey.value = prefs.get("lastfmApiKey") ?? "";
    apiSecret.value = prefs.get("lastfmApiSecret") ?? "";
    isConnected.value = sessionKey.value.isNotEmpty;
    if (enabled.value && isConnected.value) {
      _listen();
    }
  }

  Future<void> setCredentials({String? key, String? secret}) async {
    if (key != null) apiKey.value = key.trim();
    if (secret != null) apiSecret.value = secret.trim();
    final prefs = Hive.box("AppPrefs");
    await prefs.put("lastfmApiKey", apiKey.value);
    await prefs.put("lastfmApiSecret", apiSecret.value);
  }

  Future<void> toggleEnabled(bool value) async {
    enabled.value = value;
    await Hive.box("AppPrefs").put("lastfmEnabled", value);
    if (value && isConnected.value) {
      _listen();
    } else if (!value) {
      _cancelListeners();
    }
  }

  Future<void> disconnect() async {
    _cancelListeners();
    final prefs = Hive.box("AppPrefs");
    await prefs.put("lastfmSessionKey", "");
    await prefs.put("lastfmUsername", "");
    sessionKey.value = "";
    username.value = "";
    isConnected.value = false;
    _pendingToken = null;
    statusMessage.value = "";
  }

  /// Starts the Last.fm authorization flow: requests a token and opens the
  /// authorization page in the browser. After the user approves, call
  /// [completeAuthorization] to exchange the token for a session key.
  Future<bool> startAuthorization() async {
    statusMessage.value = "";
    if (apiKey.value.isEmpty || apiSecret.value.isEmpty) {
      statusMessage.value = "lastfmMissingCredentials".tr;
      return false;
    }
    try {
      final response = await _callApi('auth.getToken', {}, signed: false);
      final token = response['token']?.toString();
      if (token == null || token.isEmpty) {
        statusMessage.value = "lastfmAuthFailed".tr;
        return false;
      }
      _pendingToken = token;
      final url = Uri.parse('$_authPageUrl?api_key=${apiKey.value}&token=$token');
      await launchUrl(url, mode: LaunchMode.externalApplication);
      return true;
    } catch (e) {
      printERROR("Last.fm auth error: $e");
      statusMessage.value = "lastfmNetworkError".tr;
      return false;
    }
  }

  /// Exchanges the pending authorization token for a session key.
  Future<bool> completeAuthorization() async {
    final token = _pendingToken;
    if (token == null) {
      statusMessage.value = "lastfmNoPendingAuth".tr;
      return false;
    }
    try {
      final response =
          await _callApi('auth.getSession', {'token': token}, signed: true);
      final session = response['session'];
      if (session == null) {
        statusMessage.value = "lastfmAuthFailed".tr;
        return false;
      }
      sessionKey.value = session['key']?.toString() ?? "";
      username.value = session['name']?.toString() ?? "";
      final prefs = Hive.box("AppPrefs");
      await prefs.put("lastfmSessionKey", sessionKey.value);
      await prefs.put("lastfmUsername", username.value);
      isConnected.value = true;
      _pendingToken = null;
      statusMessage.value = "lastfmConnected".tr;
      if (enabled.value) {
        _listen();
      }
      return true;
    } catch (e) {
      printERROR("Last.fm session error: $e");
      statusMessage.value = "lastfmNetworkError".tr;
      return false;
    }
  }

  // ---------------------------------------------------------------------------
  // Playback wiring
  // ---------------------------------------------------------------------------

  void _listen() {
    _cancelListeners();
    final handler = Get.find<AudioHandler>();
    _mediaItemSub = handler.mediaItem.listen((song) {
      _currentSong = null;
      _scrobblePending = false;
      _lastPosition = Duration.zero;
      _currentListenMs = 0;
      if (song == null) return;
      _currentSong = song;
      final durationSec = song.duration?.inSeconds ?? 0;
      // Tracks shorter than 30 seconds are never scrobbled.
      _scrobblePending = durationSec >= 30;
      if (_scrobblePending) {
        _sendNowPlaying(song);
      }
    });
    _playbackStateSub = handler.playbackState.listen((state) {
      _isPlaying = state.playing;
      if (!_isPlaying) {
        _lastPosition = null;
      }
    });
    _positionSub = AudioService.position.listen((position) {
      if (!_isPlaying || _currentSong == null || !_scrobblePending) {
        _lastPosition = null;
        return;
      }
      final last = _lastPosition;
      _lastPosition = position;
      if (last != null && position > last) {
        _currentListenMs += position.inMilliseconds - last.inMilliseconds;
        _maybeScrobble();
      }
    });
  }

  void _cancelListeners() {
    _mediaItemSub?.cancel();
    _playbackStateSub?.cancel();
    _positionSub?.cancel();
    _mediaItemSub = null;
    _playbackStateSub = null;
    _positionSub = null;
  }

  void _maybeScrobble() {
    final song = _currentSong;
    if (song == null || !_scrobblePending) return;
    final durationSec = song.duration?.inSeconds ?? 0;
    final listenedSec = _currentListenMs ~/ 1000;
    final thresholdSec =
        durationSec >= 480 ? 240 : (durationSec / 2).round();
    if (listenedSec >= thresholdSec) {
      _scrobblePending = false;
      final startedAt =
          DateTime.now().millisecondsSinceEpoch ~/ 1000 - listenedSec;
      _sendScrobble(song, startedAt);
    }
  }

  Future<void> _sendNowPlaying(MediaItem song) async {
    if (!enabled.value || !isConnected.value) return;
    try {
      await _callApi('track.updateNowPlaying', {
        'artist': song.artist ?? "Unknown Artist",
        'track': song.title,
        'album': song.album ?? "",
        'duration': (song.duration?.inSeconds ?? 0).toString(),
      }, signed: true);
    } catch (e) {
      printERROR("Last.fm now playing failed: $e");
    }
  }

  Future<void> _sendScrobble(MediaItem song, int timestamp) async {
    if (!enabled.value || !isConnected.value) return;
    try {
      await _callApi('track.scrobble', {
        'artist': song.artist ?? "Unknown Artist",
        'track': song.title,
        'album': song.album ?? "",
        'timestamp': timestamp.toString(),
      }, signed: true);
      printINFO("Scrobbled: ${song.title} - ${song.artist}");
    } catch (e) {
      printERROR("Last.fm scrobble failed: $e");
    }
  }

  // ---------------------------------------------------------------------------
  // API plumbing
  // ---------------------------------------------------------------------------

  Future<Map<String, dynamic>> _callApi(String method,
      Map<String, String> params,
      {required bool signed}) async {
    final requestParams = <String, String>{
      'method': method,
      'api_key': apiKey.value,
      ...params,
    };
    if (signed) {
      requestParams['sk'] = sessionKey.value;
      requestParams['api_sig'] = _sign(requestParams);
    }
    requestParams['format'] = 'json';

    final response = await _dio.post<Map<String, dynamic>>(
      _baseUrl,
      data: requestParams,
      options: Options(contentType: Headers.formUrlEncodedContentType),
    );
    final data = response.data ?? {};
    if (data['error'] != null) {
      throw LastFmApiException(data['error'].toString(),
          data['message']?.toString() ?? "Last.fm error");
    }
    return data;
  }

  /// Last.fm API signature: md5 of sorted "name+value" pairs concatenated
  /// with the shared secret.
  String _sign(Map<String, String> params) {
    final keys = params.keys.toList()..sort();
    final buffer = StringBuffer();
    for (final key in keys) {
      buffer.write('$key${params[key]}');
    }
    buffer.write(apiSecret.value);
    final digest = crypto.md5.convert(utf8.encode(buffer.toString()));
    return digest.toString();
  }

  @override
  void onClose() {
    _cancelListeners();
    super.onClose();
  }
}

class LastFmApiException implements Exception {
  final String code;
  final String message;
  LastFmApiException(this.code, this.message);

  @override
  String toString() => 'Last.fm API error $code: $message';
}
