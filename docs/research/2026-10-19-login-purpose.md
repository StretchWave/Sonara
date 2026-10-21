# Research log — 2026-10-19 — Purpose of "login" in Sonara

Findings from a read-only pass over the codebase. Question: what does
logging in exist for in this app?

## TL;DR

Sonara has one primary login system (Supabase) and a few unrelated
secondary credentials that are sometimes confused with it. The Supabase
login exists for exactly one user-facing purpose: **cloud playlist
backup and two-way cross-device sync**, plus persistence of onboarding
preferences. It is not required to use the app; most features work
signed out.

## 1. Supabase login — cloud backup & sync (the main one)

- User-facing copy: "Sign in to back up and sync your playlists across
  devices" (Settings tile) — `lib/ui/screens/Settings/components/cloud_sync_tile.dart:25-27`
  and the auth dialog `lib/ui/screens/Settings/components/supabase_auth_dialog.dart:217-226`.
- What is synced:
  - `public.playlists` / `public.playlist_tracks` (ordered track IDs,
    plus full `MediaItemBuilder.toJson()` payload in `track_data` for
    1:1 restore) — `supabase/schema.sql:12-42`.
  - `public.user_preferences` (`music_languages`, `favorite_artists`,
    `onboarding_completed`) — `lib/services/supabase/user_preferences_service.dart:48-57`.
  - Only user playlists sync (Liked Songs / LIBFAV included). System
    playlists (LIBRP, SongsCache, SongDownloads, LIBTP) and Piped
    playlists are deliberately excluded — `lib/services/playlist_sync_service.dart:33-70`.
- Model: background two-way sync, newest `updated_at` wins; logging
  out never deletes local data — `cloud_sync_tile.dart:153-154`,
  README.md:129-134. All rows RLS-scoped per user — `supabase/schema.sql:47-71`.
- Anonymous guest accounts inactive > 5 days are auto-purged (RPC
  `delete_inactive_anonymous_users` + CASCADE) —
  `lib/services/supabase/supabase_service.dart:160-161,410-430`.
- Auth methods supported, all in `supabase_service.dart`:
  - Email + password sign-in (:189) and sign-up (:221)
  - Magic link / OTP (:253-264)
  - Google OAuth (:282-347)
  - Anonymous guest (:162)
- After login, the app completes (or short-circuits) onboarding and
  merges cloud preferences — `lib/services/onboarding_controller.dart:124-172`.
  Preferences feed the recommendation/taste engine (README.md:53).

## 2. Onboarding "login-or-skip" flow

- State machine `welcome → loginOrSkip → musicLanguageSelection →
  artistSelection → complete`, persisted in Hive `AppPrefs` —
  `lib/services/onboarding_controller.dart:9-24,60-83`.
- Welcome screen offers: Continue with Google, Sign In with Email
  (opens `SupabaseAuthDialog`), Continue as Guest (= `signInAnonymously()`
  + `skipLogin()`) — `lib/ui/screens/Onboarding/welcome_step.dart:181-295`.
- "Login later" from Settings: syncs playlists, merges cloud→local,
  uploads local→cloud (best-effort), then reopens onboarding if steps
  remain — `supabase_auth_dialog.dart:55-72`,
  `onboarding_controller.dart:223-285`.

## 3. How the OAuth callback arrives

- Mobile: deep link `io.supabase.sonara://login-callback/`. Must be
  allow-listed in the Supabase dashboard — `supabase_service.dart:263,96-98`.
- `AppLinksController.filterLinks()` prioritizes auth callbacks before
  any player/URI UI handling — `lib/utils/app_link_controller.dart:50-89`.
- `supabase_flutter` usually self-exchanges `?code=`; the manual
  fallback path (`handleAuthDeeplink()`, waits 800 ms, idempotent,
  swallows benign double-exchange races) fires only if no session yet —
  `app_link_controller.dart:71-89`, `supabase_service.dart:73-138`.
- Desktop Google OAuth instead runs a local loopback HTTP server
  (port 54321 or ephemeral) at `/auth/callback`, exchanges the code and
  renders a "Sign In Successful" page, 90 s timeout —
  `supabase_service.dart:290-394`.

## 4. Secondary logins (different systems, different purposes)

- **Piped**: username/password against a chosen Piped instance API;
  Bearer token stored in Hive `AppPrefs['piped']`. Used to link/import
  playlists from a Piped (YouTube Music mirror) account —
  `lib/services/piped_service.dart:27-54`, `lib/ui/widgets/link_piped.dart:146-181`.
  Not part of Supabase sync (excluded in `playlist_sync_service.dart:66-70`).
- **Spotify**: Authorization Code + PKCE OAuth with public Client ID
  only, loopback `http://localhost:53178/callback` —
  `lib/services/spotify/spotify_api_client.dart:39-87`,
  `lib/services/spotify/spotify_oauth.dart:32-40`. Optional provider
  for importing private/collaborative playlists; without a session it
  reports `authenticationRequired` instead of blocking —
  `lib/services/spotify/providers/spotify_official_provider.dart`.
  Note: `connectWithPkce()` has no UI caller yet; the current default
  Spotify ingestion is credential-free (anonymous embed token +
  partner GraphQL) — `lib/services/spotify/public_spotify_client.dart:34-42`.
- Incidental, unrelated: YouTube credential/cookie for private audio
  (`lib/ui/screens/Settings/components/configure_sources_screen.dart:475`)
  and Last.fm scrobbling auth (`lib/services/lastfm_service.dart`).

## Sources

README.md:16,52,129-134,240; `supabase/schema.sql`; services and UI
files cited inline above. `docs/` contains only screenshots; this note
is the first research log for this topic.

---

# Follow-up — 2026-10-20 — Login/sync bugfix + YT Music playlist import

## Bug report

"Sign-in asks for languages and favourite artists, and no playlist is
exported." Root-caused and fixed.

## 3.1 Root cause — observable update order race

`_updateUserFromSession` set `isLoggedIn` **before** `userId`
(`supabase_service.dart:145,148` pre-fix). GetX notifies workers
synchronously, so every `ever(isLoggedIn)` observer fired while
`userId` was still `''`:

- `PlaylistSyncService.syncAll()` (login listener, playlist_sync_service.dart:44-48)
  bailed on `_canSync()`'s `userId.isEmpty` check → **no playlist export ever**.
- `SupabaseAuthDialog._onSuccessfulAuth` →
  `resumeOnboardingAfterLateLogin()` loaded prefs with
  `userId=''`, found nothing, re-asked languages/artists on every
  sign-in (onboarding_controller.dart:223-285).

Secondary gap: sessions restored during `SupabaseService.onInit` run
**before** `PlaylistSyncService` registers its listener, so app start
with an existing session never synced at all.

## 3.2 Fixes shipped

1. `lib/services/supabase/supabase_service.dart` —
   `_updateUserFromSession` now sets `isAnonymous`/`userEmail`/`userId`
   first and flips `isLoggedIn` last, so login listeners always observe
   a complete identity. Fixes export + onboarding re-ask for every auth
   path (password, Google mobile deep link via `onAuthStateChange`,
   desktop loopback, anonymous).
2. `lib/services/supabase/playlist_sync_service.dart` — `onInit` now
   also calls `syncAll()` when `_canSync()` is already true at
   construction (restored-session startup case). Startup sync now
   actually runs.

## 3.3 Feature — YouTube Music playlist import

Reuses the existing innertube fetch (`getPlaylistOrAlbumSongs`,
music_service.dart:386) that powers the playlist screen:

- `lib/ui/screens/Library/library_controller.dart` — new
  `importPlaylistFromYtMusic()`: URL/ID prompt dialog →
  `parseYtPlaylistIdFromInput()` (accepts `?list=`/`&list=` URLs,
  bare `PL…`/`VLPL…`/`OLAK5uy_…` IDs; OLAK5uy routes through the album
  endpoint) → creates a **local** playlist (`LIB{ms}`, `isCloudPlaylist:
  false`) in `LibraryPlaylists` + track box via `MediaItemBuilder.toJson`,
  reuses `isImporting`/`importProgress` dialog, uploads to cloud backup
  via `PlaylistSyncService.uploadNewPlaylist()`.
- `lib/ui/widgets/sort_widget.dart` — "Import from YouTube Music"
  button next to the JSON import in the Library import dialog (single
  pop + prompt, instead of the sibling JSON button's risky double pop).
- `lib/utils/get_localization.dart` — new EN keys: `importPlaylistYt`,
  `importPlaylistYtDesc`, `importPlaylistYtUrlHint` (other locales fall
  back to English).

Existing affinity (no change): remote YT playlists already support
"Add to Library" via `addNremoveFromLibrary` — the bookmark button was
gated on `isCloudPlaylist` defaulting to true
(`models/playlist.dart:31`), which imports-from-screen already handle.

## 3.4 Observations (not fixed, flagged)

- The sibling JSON import button double-pop
  (`sort_widget.dart:126-128`) can pop the progress dialog it just
  opened — legacy quirk, kept as-is.
- `flutter analyze` from the repo root reports 576 pre-existing errors,
  all inside `backend/` (sub-package can't resolve its own imports in
  root-context analysis; untouched).
- `syncTracks()` lacks the `isSyncablePlaylist` guard (only checks
  system IDs) — piped-flagged playlists may slip through on track edits;
  separate follow-up candidate.

## 3.5 Verification

- `flutter analyze`: zero new issues in touched files (all errors
  confined to pre-existing `backend/` noise).
- `flutter test`: 379 tests, all pass (1 pre-existing skip), including
  `test/supabase_sync_test.dart`.

Manual check list for the reporter: sign in (email/Google) from
Settings → onboarding should not reappear when cloud prefs exist and
playlists should upload within seconds of login; cold-start with an
existing session should also sync; Settings → Library → Import →
"Import from YouTube Music" for the URL import path.

---

# 2026-10-21 — Ryotunes scan: how a logged-in YT Music library is fetched

Question: `/home/naji/Codes/ryotunes/` fetches the YT feed, library
playlists, albums, artists and liked songs into its UI. How, and can
Sonara do the same?

## 4.1 How Ryotunes (Rust) does it

One mechanism powers every authenticated surface — **a real Google
sign-in plus two headers**:

1. **Login + cookie harvest** — a hidden WebKitGTK window opens
   `accounts.google.com/ServiceLogin?service=youtube&continue=https://music.youtube.com/`
   (`crates/core/src/session.rs`), navigation allow-listed to
   Google/YouTube domains; on completion the `.youtube.com` cookie jar
   (`SID/HSID/SSID/SAPISID` + secure 1P/3P variants,
   `VISITOR_INFO1_LIVE`) is harvested as a plain `Cookie:` string and
   `SAPISID` is validated (`ryotunesd/src/login.rs`, transport
   `cookie_sapisid`). Manual cookie paste is also supported and
   validated the same way.
2. **Auth headers on every InnerTube call** — `Cookie: …` plus
   `Authorization: SAPISIDHASH <epoch>_<sha1("<epoch> <sapisid>
   https://music.youtube.com")>` whenever the client identity
   supports login (`innertube/src/transport.rs`; `sapisid_hash` at :349).
   `onBehalfOfUser` is only sent when a credential exists — without
   one Google *requires* one (transport.rs note).
3. **Same browse endpoints, now personalized** (`innertube/src/endpoints.rs`):
   - Feed: `browse FEmusic_home` + continuations + mood-chip params
   - Library playlists: `FEmusic_liked_playlists`; Albums:
     `FEmusic_liked_albums`; Artists:
     `FEmusic_library_corpus_track_artists` — each fetched through
     `library_grid` paged to the end because browse silently truncates
     around 25 items per page (issue #72 comment)
   - Liked songs = the personal `LM` playlist, same playlist parser
4. Client identities live in a data file (`clients.json`, copied from
   Metrolist) — rotatable without recompiling; logged-in state also
   unlocks privately-owned uploads via `TVHTML5`/`WEB_CREATOR`.

## 4.2 Sonara vs Ryotunes (YouTube fetch designs)

| Aspect | Sonara (Dart/Flutter) | Ryotunes (Rust) |
|---|---|---|
| Catalog client | WEB_REMIX constants in `music_service.dart` | WEB_REMIX from rotatable `clients.json` |
| Stream primary | VISIONOS `/player`, no PoToken/cipher | WEB_REMIX + BotGuard PoToken (`api/jnn`) + cipher/n-transform (own base.js decipherer) |
| Stream fallbacks | YoutubeExplode only | `VISIONOS → ANDROID_VR_1_65_10 → ANDROID_VR_1_43_32` + rustypipe last-ditch, per-videoId 403 memory, 10-min self-heal |
| Auth | anonymous guest only | real Google login via webview with cookie harvest (+ paste path) |
| Player | just_audio `AudioSource.uri`/LockCaching | libmpv with per-stream headers + expiry |
| Downloads | in-app HLS/progressive fetch | yt-dlp subprocess, staging + metadata embed |
| Library surfaces | local playlists + Supabase backup; YT content by browseId links | full YT account mirror: home feed, liked playlists/albums/artists, LM liked songs, ratings |

## 4.3 Feasibility in Sonara — YES

`MusicServices` already posts to `youtubei/v1` as WEB_REMIX with
`nav_parser` + `getContinuations`, and **already browses
`FEmusic_home` anonymously** (`getHome`, music_service.dart:164-190).
The personalized endpoints are the same calls + credentials; liked
songs resolves via existing `getPlaylistOrAlbumSongs(playlistId:"LM")`.
`crypto` is already a direct dependency, so SAPISIDHASH needs no new
auth dep.

## 4.4 Approved implementation plan

Scope decided with the user: **full login + all surfaces**, library
integration as **mirror views** (read-only sections; copy into local
library on demand).

1. **Auth session** — new `lib/services/ytaccount/yt_account_service.dart`:
   Hive `AppPrefs['ytm']` = `{cookie, exp, label}`; `sapisidHash()`
   (crypto SHA1); `signIn()` mobile (flutter_inappwebview Google
   window, allow-listed navigation, cookie pull on music.youtube.com
   landing) + desktop paste-cookies dialog with SAPISID validation;
   `signOut()`.
2. **Header plumbing** — `MusicServices` attaches `Cookie` +
   freshly-epoch-stamped `Authorization: SAPISIDHASH …` on each
   `_sendRequest` when logged in; no `onBehalfOfUser` (single account
   v1); login change rehydrates.
3. **Surfaces** — `getLibraryPlaylists()` (`FEmusic_liked_playlists`),
   `getLibraryAlbums()` (`FEmusic_liked_albums`),
   `getLibraryArtists()` (`FEmusic_library_corpus_track_artists`),
   paged to end via `getContinuations`; new `nav_parser::parseLibraryGrid`
   (musicTwoRowItemRenderer); `getLikedSongs()` → `LM` playlist.
   Home personalizes with zero code change.
4. **UI (mirrors)** — Settings "YT Music Account" tile beside the
   Piped tile; Library YT sections via `content_list_widget_item`, taps
   open the existing playlist/album/artist screens by browseId; Liked
   songs section with "Import to Favorites" → merge into `LIBFAV` +
   cloud `syncAllFavoritesFromLocal()`.
5. **Verification** — unit tests for `sapisidHash` shape and
   `parseLibraryGrid` fixtures; `flutter analyze` + existing suites.

Risks (flagged, not blocking): unofficial API / ToS caveat; response
shape drift → fail-through-empty; cookie expiry → re-login prompt;
desktop webview availability handled by the paste path.

---

## Implementation record (2026-10-21, YT Music account shipped)

Built the approved plan end to end. All work on `main`, uncommitted.

### Auth pipeline
- `lib/services/ytaccount/yt_account_service.dart` (new GetxService):
  Hive `AppPrefs['ytm']` = `{cookie, label}`; Rx `isLoggedIn` /
  `cookieHeader` / `accountLabel`; `applyCookies(Map)` merges harvested
  pairs over the stored jar (new wins, rotated names refresh) and
  **refuses to persist without a SAPISID alias**
  (`SAPISID|__Secure-1PAPISID|__Secure-3PAPISID` — the only alias used
  for the hash); `sapisidFromCookie()`; static `sapisidHash(sapisid,
  {epochSeconds})` = `SAPISIDHASH <epoch>_<sha1("<epoch> <sapisid>
  https://music.youtube.com")>` (regenerated per request since YouTube
  bounds the epoch to ~5 min); `signOut()` deletes the box entry.
- `music_service.dart`: `_sendRequest` now composes per-call headers —
  `_headers` + `Cookie` + fresh `Authorization` when
  `YtAccountService.isLoggedIn` (resolved via
  `Get.isRegistered`-safe `_ytAccount()` helper; no `onBehalfOfUser`).
- `main.dart`: `YtAccountService` lazyPut between SupabaseService and
  PlaylistSyncService; lazyPut order only affects construction-time
  reads because header state is read per request.

### InnerTube surfaces
- `getLibraryShelf(browseId)`: shelf sniff via the same two-path probe
  `getPlaylistOrAlbumSongs` uses (`twoColumn` const + `singleColumn`
  fallback); items through `parseLibraryGrid`; paged to end with
  `getContinuationsPlaylist` (shelf `continuations`, token re-POSTed on
  `browse`). Wrappers: `getLibraryPlaylists` → `FEmusic_liked_playlists`,
  `getLibraryAlbums` → `FEmusic_liked_albums`, `getLibraryArtists` →
  `FEmusic_library_corpus_track_artists`; `getLikedSongs` →
  `getPlaylistOrAlbumSongs(playlistId: 'LM')` (the existing VL prefixing
  makes `VLLM`, confirmed valid by ryotunes' live smoke tests).
- `nav_parser.parseLibraryGrid`: cards (`musicTwoRowItemRenderer`) —
  id from `navigationBrowseId` with `title.runs[0]` fallback (library
  pages nest the endpoint either way), kind inferred from the pageType
  (playlist/album/artist/track), `subtitle` run 0, first thumbnail;
  rows (`musicResponsiveListItemRenderer`) — title/subtitle via
  `getFlexColumnItem` + `text_run_text`, second-column run 0 pageType
  for kind, `thumbnails` const probe.

### Login UI
- `lib/ui/screens/Settings/yt_login_screen.dart`: `YtLoginScreen`
  (mobile/web) — embedded InAppWebView starting at the Google login URL;
  navigation allow-list (*.google.com, *.youtube.com, gstatic,
  googleusercontent, youtube-nocookie) with `stopLoading()` on foreign
  hosts; auto-capture on landing at music.youtube.com via
  `CookieManager.getCookies(url: origin)`; AppBar capture button for
  manual recovery. `showYtPasteCookiesDialog` (desktop) — paste the
  cookie string (strips a `Cookie:` prefix), same SAPISID gate.
- Settings tile "YT Music Account" beside the Piped tile: link/unlink
  TextButton, snackbar feedback; unlink = `signOut()`.

### Library mirrors (all read-only + on-demand copies)
- `YtLibraryController` (library_controller.dart): Rx playlists/albums/
  artists mirror lists + `isYtFetched`; `ever(isLoggedIn)` refetch, and
  clears everything on sign-out; per-shelf failure is swallowed
  (fail-through-empty); `openYtItem` routes playlist/album browseIds via
  AppLinksController.openPlaylistOrAlbum and artist ids via openArtist
  (existing screens handle browseId-only arguments fine); 
  `mergeLikedSongsToFavourites` pulls `LM` tracks and merges into
  `LIBFAV` (skip existing ids, `MediaItemBuilder.toJson` value shape)
  then `PlaylistSyncService.syncAllFavoritesFromLocal()`.
- `library.dart`: `YtMirrorSection(kind)` rendered above the local
  content in all three tabs (playlists/albums/artists; bottom-nav and
  desktop layouts both inherit), with section title, sync-refetch
  button, per-item horizontal scroll of `YtMirrorCard`s (thumb, title,
  subtitle; scaffold while YTM data is in flight); playlists section
  carries the "Import liked songs to Favorites" button (spinner while
  importing). Hidden entirely when not logged in or when the shelf
  banks come back empty.
- `main.dart`: `YtLibraryController` lazyPut after LibraryArtistsController.

### Live data shapes learned while wiring fixtures
- `musicResponsiveListItemFlexColumnRenderer` rows wrap runs under a
  `text` key (`getFlexColumnItem` requires `text.runs`) — flat fixture
  silently parses to ''.
- `run_text` (`runs.0.text`) is *not* what flex columns use; `flex` is
  already the renderer map → `text_run_text` (`text.runs.0.text`).
- mtrir kind detection goes through `title.runs[0].navigationEndpoint…`
  while the top-level `navigationEndpoint.browseEndpoint.browseId`
  gives the id in most real responses — hence the dual probe.

### Verification
- `test/yt_account_test.dart` (new): sapisidHash shape + exact vector
  (epoch 1700000000 / `test-sapisid` →
  `SAPISIDHASH 1700000000_17d748c1…`), parseLibraryGrid cards (
  playlist/album/artist + thumbnail + subtitle), rows (second-column
  pageType), skip-without-id. 5 passing.
- `flutter test`: 384 passed, 1 pre-existing skip (was 379/1 before).
- `flutter analyze lib`: only pre-existing deprecation/experimental
  infos (RadioGroup/onReorder/LockCachingAudioSource) — zero issues in
  touched files.
