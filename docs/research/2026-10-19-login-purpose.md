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
