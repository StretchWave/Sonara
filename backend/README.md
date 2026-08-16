# Sonara Playlist Resolver (backend)

Server-side playlist metadata resolution for Sonara
Flutter app. It lets users import **public** Spotify playlists **without
creating their own Spotify Developer App** — the backend holds the
credentials and normalizes the result, so the app never talks to Spotify
directly.

```
Flutter app
    │  POST /api/playlist/resolve  {"url": "https://open.spotify.com/playlist/..."}
    ▼
Backend resolver
    │  provider chain: cache → public (anonymous) → Apify scraper → Spotify official API
    ▼
Normalized playlist metadata (provider-agnostic JSON)
```

## Run locally

**No credentials are required to resolve public playlists.** The
`public-spotify` provider bootstraps an anonymous web-player token from
the Spotify embed page and uses Spotify's own partner GraphQL to enumerate
the playlist and fetch full track metadata — the same path the Spotify web
player uses before sign-in. Paste a URL, get tracks.

```bash
cd backend
dart pub get
dart run bin/server.dart
# Sonara playlist resolver listening on http://0.0.0.0:3000
```

Optional additional sources:

```bash
# Apify scraper — a configured alternative to the anonymous channel.
export APIFY_API_TOKEN=...
# Optional: override the scraper actor (default is the free
# axlymxp/spotify-playlist-track-extractor).
export APIFY_ACTOR_ID=axlymxp/spotify-playlist-track-extractor

# Optional: server-side Spotify credentials (fallback when the scraper
# cannot resolve). Create a free app at
# https://developer.spotify.com/dashboard.
export SPOTIFY_CLIENT_ID=...
export SPOTIFY_CLIENT_SECRET=...
```

Point the Flutter app at it:

```bash
cd .. && flutter run -d windows --dart-define=BACKEND_URL=http://localhost:3000
```

## Configuration (environment variables)

| Variable                      | Default | Purpose                                        |
| ----------------------------- | ------- | ---------------------------------------------- |
| `PORT`                        | `3000`  | HTTP listen port                               |
| `HOST`                        | `0.0.0.0` | Listen address                              |
| `APIFY_API_TOKEN`             | —       | Optional — Apify API token; never shipped to the app |
| `APIFY_ACTOR_ID`              | `axlymxp/spotify-playlist-track-extractor` | Scraper actor to run |
| `APIFY_MAX_TRACKS_PER_PLAYLIST` | `0`  | Cap on tracks per playlist (`0` = all)         |
| `APIFY_ACTOR_INPUT_JSON`      | —       | Optional raw actor input template (`{{url}}` is substituted) |
| `APIFY_RUN_TIMEOUT_SECONDS`   | `120`   | Max wall-clock time for one actor run          |
| `APIFY_POLL_INTERVAL_SECONDS` | `3`     | Run-status polling interval                    |
| `SPOTIFY_CLIENT_ID`           | —       | Optional fallback Spotify app id               |
| `SPOTIFY_CLIENT_SECRET`       | —       | Optional fallback secret — never shipped to the app |
| `CACHE_TTL_MINUTES`           | `60`    | How long resolved playlists stay cached        |
| `RATE_LIMIT_PER_MINUTE`       | `30`    | Per-IP request limit for the public endpoints  |

Secrets live only in the environment. Nothing is hardcoded, committed, or
returned to the Flutter client.

## API

### `POST /api/playlist/resolve`

Body: `{"url": "https://open.spotify.com/playlist/{id}?si=..."}`

Accepts full URLs, `spotify:playlist:{id}` URIs and bare ids. Track/album/
artist URLs and arbitrary URLs are rejected with a structured error (no
generic URL fetching — SSRF-safe by design).

Success (200):

```json
{
  "success": true,
  "source": {"provider": "spotify", "method": "official_api"},
  "playlist": {"id": "...", "name": "Phonks to Download", "trackCount": 127},
  "tracks": [
    {
      "sourceTrackId": "...",
      "position": 0,
      "title": "...",
      "artists": ["..."],
      "album": "...",
      "albumArtist": "...",
      "durationMs": 213000,
      "isrc": "...",
      "releaseDate": "2020-03-20",
      "explicit": true,
      "artworkUrl": "..."
    }
  ],
  "resolution": {"total": 127, "resolved": 123, "unavailable": 4},
  "warnings": [{"code": "PARTIAL_PLAYLIST", "message": "4 tracks could not be resolved."}],
  "cached": false
}
```

Failure (structured error, never a raw provider error):

```json
{"success": false, "error": {"code": "UNSUPPORTED_SPOTIFY_URL", "message": "..."}}
```

Codes: `INVALID_URL`, `UNSUPPORTED_SPOTIFY_URL`, `PLAYLIST_NOT_FOUND`,
`PLAYLIST_PRIVATE`, `AUTHENTICATION_REQUIRED`, `PERMISSION_DENIED`,
`PROVIDER_RATE_LIMITED`, `PROVIDER_UNAVAILABLE`, `NO_METADATA_SOURCE`,
`NETWORK_ERROR`, `INTERNAL_ERROR`, `APIFY_AUTH_ERROR`,
`APIFY_ACTOR_ERROR`, `APIFY_TIMEOUT`, `INVALID_SCRAPER_RESPONSE`,
`PLAYLIST_EMPTY`.

### `GET /api/playlist/spotify/{id}`

Same result keyed by playlist id. Append `?refresh=true` to bypass the cache
and force a fresh upstream resolution.

### `GET /health`

Liveness + whether the server has Spotify credentials configured.

## Behavior

- **Cache first** — resolved playlists are cached in memory (TTL
  `CACHE_TTL_MINUTES`); repeat requests never hit a scraper.
- **Provider chain** — `cache → public-spotify (anonymous) → Apify →
  Spotify official API`. The chain stops at the first complete result; a
  failing provider is skipped, not fatal.
- **No-credentials import** — public playlists resolve through the
  anonymous web-player channel with zero configuration; the user never
  enters a Client ID or logs in. The Apify path is a configured
  alternative; Spotify official API is the last backend fallback.
- **Request coalescing** — ten simultaneous requests for the same playlist
  produce exactly one upstream call.
- **Partial results** — unavailable tracks are counted in `resolution` and
  listed as `warnings`; the request still succeeds.
- **Rate limits** — per-IP fixed-window limiting with `Retry-After`; the
  Spotify client caches its app token and refreshes on expiry/401.
- **Spotify auth fallback stays in the app** — when the backend cannot
  resolve (e.g. private playlist), the Flutter client falls back to its
  existing PKCE flow.

## Deploy

Any container host works (Railway, Render, Fly.io, AWS ECS, ...). A
`Dockerfile` is included:

```bash
docker build -t sonara-resolver backend
docker run -p 3000:3000 -e APIFY_API_TOKEN=... \
  -e SPOTIFY_CLIENT_ID=... -e SPOTIFY_CLIENT_SECRET=... sonara-resolver
```

Then build the app with `--dart-define=BACKEND_URL=https://your-deployed-url`.

## Tests

```bash
cd backend && dart test
```

Covers URL validation, token caching, pagination, provider error mapping,
the cache-first chain, request coalescing, refresh/invalidation, partial
results, the anonymous public-spotify channel (embed token bootstrap,
GraphQL enumeration, track decoration, structured failure mapping), the
Apify actor flow (run lifecycle, normalization, deduplication) and the
HTTP endpoints (including rate limiting).
