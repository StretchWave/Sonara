# MetroFuse (Metrolist) Master Recreation & Architecture Prompt (Flutter Edition)

You are tasked with designing and implementing a state-of-the-art, full-featured, cross-platform music streaming client inspired by MetroFuse (Metrolist), built with **Flutter (Dart)**. The application must follow **Clean Architecture**, a robust state management pattern (**BLoC** or **Riverpod**), strict **Material 3 / Material You Design Guidelines**, and leverage high-performance audio engines (**`media_kit`** / **`just_audio`** with **`audio_service`**) for gapless, lossless, multi-provider playback.

Below is the complete, exhaustive feature specification, architecture blueprint, audio DSP pipeline, multi-provider engine, lyrics system, and UI details tailored for Flutter. Every single feature must be implemented without omission.

---

## 1. System Architecture & Tech Stack (Flutter)

### Core Technologies
* **Language & SDK**: Dart 3.x+ (strict null safety, pattern matching, records), Flutter 3.x+.
* **Architecture**: Clean Architecture with Feature-Driven folder structure (Data, Domain, Presentation layers).
* **State Management**: `flutter_bloc` (or `flutter_riverpod`) with immutable states and reactive event streams.
* **Dependency Injection / Service Locator**: `get_it` + `injectable` for compile-time dependency graph generation.
* **UI Framework & Theming**: Flutter Material 3 (`useMaterial3: true`), `dynamic_color` / `palette_generator` (extracting tonal palettes from album artwork), `flutter_animate` for micro-interactions, custom shaders (`flutter_shaders` / FragmentProgram) for moving blur meshes and particle fields.
* **Audio Playback Engine**: `media_kit` (libmpv backend for high-res 192kHz/24-bit bit-perfect FLAC, gapless playback, and hardware decoding) or `just_audio` paired with `audio_service` for background audio lifecycle and OS media session control.
* **Database & Persistence**: `drift` (type-safe SQLite with SQL migrations, relational queries, and reactive stream queries) + `shared_preferences` / `hydrated_bloc` for key-value settings.
* **Network & Serialization**: `dio` (with interceptors, connection pooling, cache interceptor, and proxy adapters), `freezed` & `json_serializable`, Protocol Buffers (`protobuf` package).

---

## 2. Multi-Provider Streaming & Audio Engine

### A. Supported Streaming Providers
1. **YouTube Music (InnerTube API)**:
   * Direct InnerTube reverse-engineered endpoint client in Dart (Search, Browse, Radio, Next Queue, Playlist, Artist, Lyrics, Automix).
   * **Multi-Client Player Race**: Concurrently race requests across multiple clients (`ANDROID_VR_NO_AUTH`, `ANDROID_MUSIC`, `TVHTML5_SIMPLY_EMBEDDED_PLAYER`, `WEB_REMIX`) via `Future.any()` / custom channel racing to bypass throttling, bot blocks, and IP bans.
   * Proof-of-Origin (PO) token generation and JavaScript signature cipher deobfuscation.
2. **Deezer**:
   * Direct and proxy-based track resolution by ISRC or title/artist metadata.
   * Stream qualities: MP3 128kbps, MP3 320kbps, Lossless FLAC 1411kbps.
3. **Tidal**:
   * High-fidelity streaming via custom resolver endpoints.
   * Stream qualities: AAC 320kbps, Lossless FLAC (16-bit / 44.1kHz), Hi-Res Lossless FLAC (24-bit up to 192kHz).
   * Tidal animated cover artwork support.
4. **Amazon Music**:
   * High-definition and spatial streaming with live stream decryption using FFmpeg bindings (`ffmpeg_kit_flutter`).
   * Stream qualities: Ultra HD Lossless FLAC, Dolby Atmos spatial streams.
5. **Qobuz**:
   * Hi-Res streaming with multi-region backend support (Kenny / custom instances).
6. **SoundCloud**:
   * High-quality streams in Opus, AAC (96 / 160kbps), and MP3 (128kbps) formats.
   * Home feed curation and user search integration.
7. **Apple Music**:
   * High-definition metadata, audio preview playback (Atmos, AC3, AAC Binaural, AAC HE), and full-motion artist video backgrounds.
8. **Local Music (Device Storage)**:
   * Native device storage scanning (`on_audio_query` / custom MediaStore & iOS MPMediaQuery bridges), ID3/Vorbis tag parsing, embedded artwork extraction, and BPM / Camelot key analysis.

### B. Cross-Provider ISRC Matching
* **Automated Lossless Upgrade**: When a user selects a song from YouTube Music or a playlist, query `IsrcResolver` to obtain its ISRC code via Deezer or Apple Music, then seamlessly match and stream the Lossless FLAC stream from Deezer or Tidal if available.
* **Fallback Priority Order**: Configurable priority chain (e.g., Tidal -> Deezer -> Amazon -> Qobuz -> SoundCloud -> YouTube Music) with user manual overrides.

### C. Playback Core & Audio DSP
* **Background Service (`audio_service`)**: Background audio lifecycle, foreground notification with custom media action buttons, lockscreen media controls, Apple CarPlay, and Android Auto.
* **Audio Normalization**: LUFS loudness leveling with selectable profiles (Aggressive: -7 LUFS, Loud: -11 LUFS, Balanced: -14 LUFS, Quiet: -19 LUFS).
* **Silence Skipping**: Instant silence skipping algorithm and threshold-based silence stripping at beginning/end of tracks.
* **Varispeed / Pitch**: Variable tempo and pitch adjustment (0.5x - 2.0x) with pitch preservation.
* **Parametric Equalizer**: Full 10-band Parametric Equalizer with custom Frequency Response Graph painter, filter types (Low Shelf, High Shelf, Peaking, Notch, Low Pass, High Pass), EQ Wizard, and import/export profiles.

---

## 3. MetroMix (Automix & DJ Transitions)

* **Harmonic Mixing**: Real-time track BPM calculation and Camelot Wheel key compatibility detection.
* **Beat-Phase Alignment**: Calculates phase offsets to align downbeats of incoming and outgoing tracks.
* **18 DJ Presets**: `Automix`, `Auto`, `Smart DJ`, `Beat Blend`, `Energy Match`, `Club Blend`, `Vocal Blend`, `Bass Swap`, `Radio Edit`, `Quick Cut`, `Loop Out`, `Fade`, `Rise`, `Blend`, `Drop`, `Echo Out`, `Smooth`, `Long Blend`.
* **Dynamic Curves**:
  * Volume Curves: `Auto`, `Balanced`, `Punchy`, `Melt`, `Wave`.
  * EQ Curves: `Auto`, `Clean`, `Bass Swap` (low-frequency crossover filter), `Vocal Space` (mid-range attenuation), `Full`.
  * Effect Curves: `Auto`, `None`, `Filter`, `Echo`, `Wave`.
* **Crossfade Settings**: Dual-player fading pipeline with adjustable transition duration (0.5s - 15s) and gapless playback toggle.

---

## 4. Multi-Source Synchronized Lyrics & AI Translation

### A. Providers & Parser
* **BetterLyrics / TTML Parser**: Word-by-word, syllable-by-syllable karaoke synchronization (Apple Music style).
* **LrcLib & KuGou**: Line-by-line synchronized LRC lyrics with fuzzy matching.
* **Paxsenix**: Apple Music, QQ Music, and Musixmatch lyrics extraction.
* **Spotify Lyrics & YouTube Subtitles**: Embedded subtitle and synced stream fallbacks.

### B. Display & Animations
* **Display Modes**: Inline player lyrics widget & fullscreen immersive lyrics view.
* **6 Animation Styles**: `Apple`, `Karaoke`, `Glow`, `Slide`, `Fade`, `None`.
* **Karaoke Glow Effect**: Dynamic CustomPainter radiant text glow on the currently active syllable.
* **Interactive Navigation**: Tap any lyric line to instantly seek audio playback to that exact timestamp.
* **Lyrics Resync Tool**: In-app offset editor (+/- ms) and manual lyrics source switcher.

### C. Phonetic Transliteration & AI Translation
* **Pronunciation / Romanization**: Automatic phonetic transliteration for Japanese Romaji, Korean Hangul to Revised Romanization, Chinese Pinyin (`lpinyin`), Cyrillic, Greek, Hindi, Arabic, Hebrew, Thai, etc.
* **On-the-Fly AI Translation**: Integration with OpenRouter (Gemini, DeepSeek, Claude) and DeepL API for real-time multilingual lyrical translation mapped line-for-line.

---

## 5. UI, Theming & Visual Aesthetics (Flutter)

### A. Material 3 / Material You Dynamic Theming
* **Dynamic Palette**: Extracted from album artwork using `palette_generator` / `material_color_utilities` with dark mode, light mode, and OLED Pure Black options.
* **Visual Effects**:
  * **Moving Blur Background**: Custom OpenGL/Skia shader or animating blurred canvas meshes reflecting the active track art.
  * **Galaxy Star Overlay**: Interactive particle starfield CustomPainter with touch reaction.
  * **Video Canvas Backgrounds**: Live looping video canvases (`media_kit_video` / `video_player`) from Spotify and Apple Music Artist Motion.
* **Customization**:
  * Slider Styles: Default, Squiggly / Wavy (CustomPainter), Slim.
  * Button Styles: Default, Primary, Tertiary.
  * MiniPlayer Background Styles: Default, Transparent, Blur (`BackdropFilter`), Galaxy Blur, Gradient, Pure Black.
  * Density Scaling: Native (100%), Slightly Compact (85%), Compact (75%), Very Compact (65%), Ultra Compact (55%), or Custom scaling factor.
  * High Refresh Rate support (120Hz ProMotion / smooth scroll physics).

### B. Player & Navigation Architecture
* **Navigation**: `go_router` with nested shell routes for tab preservation and deep linking.
* **Fullscreen Player Sheet**: Draggable bottom sheet (`sliding_up_panel` or custom physics gesture detector) with album art carousel, audio visualizer, inline lyrics, audio quality badges, and provider match dialog.
* **MiniPlayer**: Persistent bottom bar with swipe-to-skip, swipe-to-remove, and play/pause controls.
* **Reorderable Queue**: Drag-and-drop song reordering (`ReorderableListView`), swipe-to-delete, queue edit lock, shuffle persistence across sessions, and duplicate prevention.

---

## 6. Social, Cloud & External Integrations

1. **"Listen Together" (Real-Time Collaborative Sessions)**:
   * Multi-user synchronized listening over `web_socket_channel` and binary Protobuf packets.
   * Host controls, room codes, participant suggestions, auto-approval, volume sync, and network jitter/latency compensation.
2. **Discord Rich Presence (RPC)**:
   * Native Discord RPC integration (`dart_discord_rpc`) displaying live song title, artist, album art, elapsed/remaining time, provider badges, and custom buttons ("Listen on YouTube", "Join Listen Together").
   * **Discord Animated Canvas**: Streams live animated GIF/MP4 loop canvases directly into Discord RPC.
3. **Last.fm Scrobbler**:
   * Scrobbles tracks with custom delay percentage/duration, real-time "Now Playing" updates, and automatic "Send Like" synchronization.
4. **Spotify Integration**:
   * Spotify Canvas background fetching, Spotify listening history tracking, and playlist importing.
5. **Google Cast (Chromecast) & AirPlay**:
   * Cast sender and AirPlay stream casting support.

---

## 7. Library, Discovery & Offline Capabilities

### A. Discovery & Home Feed
* **Multi-Source Home Feed**: Switch feed source between YouTube Music, Tidal, Spotify, SoundCloud, Deezer, or Offline Local Music.
* **Sections**: Speed Dial (pinned favorites), Quick Picks, Moods & Genres (Workout, Focus, Chill, Party, Romance, etc.), Charts (Global & 100+ countries), New Releases, and Curated Radios.
* **Audio Recognition (Shazam)**: Built-in microphone audio fingerprinting to identify songs from ambient sound with recognition history.

### B. Library & Smart Playlists
* Tabs for Songs, Artists, Albums, Playlists, Podcasts, and Mixes.
* **Smart Auto Playlists**: Liked Songs, Downloaded, Local Files, Top Played, Cached Songs, Uploaded Songs.
* **Statistics & Metrolist Wrapped**: In-depth listening analytics (time, top songs, top artists, play counts) and interactive yearly "Wrapped" recap story with shareable cards.
* **2-Way Cloud Sync**: Syncs liked songs, albums, and playlists with YouTube Music.

### C. Downloads & File Management
* **Background Downloader**: Multi-threaded offline song downloads with notification progress.
* **Auto-Download on Like**: Automatically saves favorited songs to offline storage.
* **Public Download Exporter**: Exports tracks to device storage with high-quality embedded album art, ID3v2.4 / Vorbis tags (Title, Artist, Album, Year, Track Number, ISRC, BPM) using `audiotags` or custom byte writers.
* **Storage Manager**: Granular control over audio cache size, image cache size, and downloaded files.

### D. Alarms, Sleep Timer & System Features
* **Music Alarm**: Multi-entry alarm system with customizable day schedules, volume ramps, and playlist/random song selection.
* **Sleep Timer**: Countdown timer with audio fade-out and "stop after current song" option.
* **Android Auto & Apple CarPlay**: Full automotive template navigation with voice search, liked playlists, and car queue management.
* **Widgets**: Material 3 home screen widgets (`home_widget` package).
* **Network & Privacy**: SOCKS5 / HTTP Proxy support with authentication, screenshot prevention mode (`flutter_windowmanager`), and full SQLite database backup & restore.

---

## 8. Recommended Flutter Package Ecosystem

| Subsystem | Recommended Flutter Package(s) |
|---|---|
| **Audio Core & Background** | `media_kit` (or `just_audio`), `audio_service`, `audio_session` |
| **State Management** | `flutter_bloc` / `bloc` (or `flutter_riverpod`) |
| **Service Locator / DI** | `get_it`, `injectable` |
| **Database & Cache** | `drift` (SQLite), `shared_preferences`, `flutter_cache_manager` |
| **Networking & APIs** | `dio`, `web_socket_channel`, `protobuf` |
| **UI & Theming** | `dynamic_color`, `palette_generator`, `flutter_animate` |
| **Video Canvas** | `media_kit_video` / `video_player` |
| **Audio Tagging & Local Files** | `audiotags`, `on_audio_query`, `path_provider` |
| **Cross-Platform Bridge** | `home_widget` (Widgets), `flutter_windowmanager` |
