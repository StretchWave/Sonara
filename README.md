<div align="center">

# 🎵 Sonara

A free, open-source, cross-platform music streaming app for **Android, Windows and Linux**.

Stream from YouTube / YouTube Music. No login. No ads.

</div>

## About

Sonara is a free, open-source, Flutter-based music streaming app with its own improvements:

- **Spotify playlist import** without needing a Spotify Developer App — powered by an optional bundled [server-side resolver backend](backend/README.md)
- **Multi-source playback** — optional Qobuz & Tidal FLAC/Hi-Res streaming through user-configured resolvers (no login, no credentials in the app), with YouTube as the automatic fallback
- **Last.fm scrobbling** so your listening history follows you
- **Listening statistics** — see what you actually play
- **Richer metadata** — MusicBrainz, LRCLIB and Spotify oEmbed enrichment for imported playlists
- **Playlist export** to JSON, CSV or directly to a YouTube Music playlist

## Features

* Play songs from YouTube / YouTube Music
* Song caching while playing
* Radio feature
* Background music playback
* Playlist creation & bookmarking
* Artist & Album bookmarking
* Import songs, playlists, albums and artists by sharing from YouTube / YouTube Music
* Spotify playlist import (with optional server-side resolution, no credentials needed)
* Streaming quality control
* Song downloading support (including external storage on Android)
* Language support (50+ translations)
* Skip silence
* Dynamic theme
* Bottom or Side navigation bar (switchable)
* Equalizer support (Android)
* Android Auto support
* Synced & plain lyrics support (LRCLIB)
* Sleep timer
* Last.fm scrobbling
* Listening statistics
* Piped playlist integration
* Optional multi-source playback: Qobuz & Tidal (Hi-Res FLAC / FLAC / AAC / MP3) via resolver instances, before YouTube
* Resolver health screen to verify each configured source
* Manual match correction when automatic cross-catalog matching picks the wrong version
* Format display (codec, bitrate, sample rate, bit depth) in the player and song info
* No advertisements
* No login required

## Building from source

Requires the [Flutter SDK](https://docs.flutter.dev/get-started/install) (stable channel).

```bash
flutter pub get

# Android
flutter build apk

# Windows
flutter build windows

# Linux
flutter build linux
```

### Optional: backend for Spotify playlist imports

Spotify playlist imports can optionally use the bundled server-side resolver in [`backend/`](backend/README.md). It lets users import public Spotify playlists without configuring their own Spotify Developer App. Build the app with `--dart-define=BACKEND_URL=<deployed-url>` to enable it, or run it locally:

```bash
cd backend
dart pub get
dart run bin/server.dart
```

### Optional: Qobuz & Tidal sources

To stream or download lossless FLAC from Qobuz/Tidal, enable them in **Settings → Sources** and paste the base URLs of **resolver instances** (Qobuz) or **resolver endpoints** (Tidal) — one per line. Resolvers are community/self-hosted servers that hold the provider access, so the app itself never stores credentials. If none are configured or reachable, playback automatically falls back to YouTube. Use **Settings → Sources → Resolver health** to verify that a URL works.

## Localization

Translations live in [`localization/`](localization/). After editing a language file, regenerate the Dart translations:

```bash
dart localization/generator.dart
```

## Troubleshooting

* If you face notification control issues or music playback stops due to system optimization, enable **"Ignore battery optimization"** from the app settings.

## License

Sonara is free software licensed under the **GNU General Public License v3.0** (see [`LICENSE`](LICENSE)). As a fork, it also carries the conditions stated by the upstream Harmony Music project:

```
- Copied/Modified version of this software can not be used for 'non-free' and profit purposes.
- You can not publish copied/modified version of this app on closed source app repository
  like PlayStore/AppStore.
```

## Disclaimer

```
This project has been created while learning & learning is the main intention.
This project is not sponsored or affiliated with, funded, authorized, endorsed by any content provider.
Any Song, content, trademark used in this app are intellectual property of their respective owners.
Sonara is not responsible for any infringement of copyright or other intellectual property rights
that may result from the use of the songs and other content available through this app.

This Software is released "as-is", without any warranty, responsibility or liability.
In no event shall the Author of this Software be liable for any special, consequential,
incidental or indirect damages whatsoever (including, without limitation, any other pecuniary loss)
arising out of the use of or inability to use this product, even if the Author of this Software is
aware of the possibility of such damages and known defect.
```

## Credits

This project is a fork of [**Harmony Music**](https://github.com/anandnet/Harmony-Music) — all credit for the original app goes to its author and contributors.

* [Flutter documentation](https://docs.flutter.dev/) — the best guide to cross-platform UI development
* [youtube_explode_dart](https://github.com/anandnet/youtube_explode_dart) — unofficial YouTube/YouTube Music API
* App UI inspired by [ViMusic](https://github.com/vfsfitvnm/ViMusic)
* Synced lyrics provided by [LRCLIB](https://lrclib.net)
* [Piped](https://piped.video) for playlist integration
* [MusicBrainz](https://musicbrainz.org) for metadata enrichment

#### Major packages used

* `just_audio` — audio player for Android
* `media_kit` — audio player for Linux and Windows
* `audio_service` — background music & platform audio services
* `get` — state management, dependency injection and route management
* `youtube_explode_dart` — third-party package to provide song URLs
* `hive` / `hive_flutter` — offline database
