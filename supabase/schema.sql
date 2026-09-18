-- ==============================================================================
-- Sonara (Harmony-Music) Supabase Cloud Synchronization Schema & RLS Policies
-- ==============================================================================
-- This schema supports optional cloud synchronization of user-created playlists
-- and playlist tracks with strict Row-Level Security (RLS) guaranteeing that each
-- user can only read, insert, update, and delete their own data.
-- ==============================================================================

-- 1. Playlists Table
-- Stores playlist metadata. The id is the local Sonara playlist ID (e.g. LIB1712345678)
-- preserving 1:1 mapping with the local Hive database.
create table if not exists public.playlists (
    id text primary key,
    user_id uuid not null references auth.users(id) on delete cascade,
    name text not null,
    description text,
    cover_url text,
    spotify_playlist_id text,
    created_at timestamptz not null default timezone('utc'::text, now()),
    updated_at timestamptz not null default timezone('utc'::text, now())
);

-- Migration for existing databases
alter table public.playlists add column if not exists spotify_playlist_id text;

-- 2. Playlist Tracks Table
-- Stores ordered tracks belonging to a playlist.
-- track_data is a JSONB column containing the full MediaItemBuilder.toJson() map
-- ensuring 100% fidelity reconstruction of track metadata locally.
create table if not exists public.playlist_tracks (
    id text primary key, -- formatted as <playlist_id>_<position> or uuid
    playlist_id text not null references public.playlists(id) on delete cascade,
    user_id uuid not null references auth.users(id) on delete cascade,
    track_id text not null,
    position integer not null,
    track_data jsonb not null,
    created_at timestamptz not null default timezone('utc'::text, now()),
    updated_at timestamptz not null default timezone('utc'::text, now())
);

-- Indices for rapid querying by user and playlist
create index if not exists idx_playlists_user_id on public.playlists(user_id);
create index if not exists idx_playlist_tracks_playlist_id on public.playlist_tracks(playlist_id);
create index if not exists idx_playlist_tracks_user_id on public.playlist_tracks(user_id);

-- Enable Row Level Security (RLS)
alter table public.playlists enable row level security;
alter table public.playlist_tracks enable row level security;

-- ------------------------------------------------------------------------------
-- RLS Policies for public.playlists
-- ------------------------------------------------------------------------------
drop policy if exists "Users can view own playlists" on public.playlists;
create policy "Users can view own playlists"
    on public.playlists for select
    using (auth.uid() = user_id);

drop policy if exists "Users can insert own playlists" on public.playlists;
create policy "Users can insert own playlists"
    on public.playlists for insert
    with check (auth.uid() = user_id);

drop policy if exists "Users can update own playlists" on public.playlists;
create policy "Users can update own playlists"
    on public.playlists for update
    using (auth.uid() = user_id)
    with check (auth.uid() = user_id);

drop policy if exists "Users can delete own playlists" on public.playlists;
create policy "Users can delete own playlists"
    on public.playlists for delete
    using (auth.uid() = user_id);

-- ------------------------------------------------------------------------------
-- RLS Policies for public.playlist_tracks
-- ------------------------------------------------------------------------------
drop policy if exists "Users can view own playlist tracks" on public.playlist_tracks;
create policy "Users can view own playlist tracks"
    on public.playlist_tracks for select
    using (auth.uid() = user_id);

drop policy if exists "Users can insert own playlist tracks" on public.playlist_tracks;
create policy "Users can insert own playlist tracks"
    on public.playlist_tracks for insert
    with check (auth.uid() = user_id);

drop policy if exists "Users can update own playlist tracks" on public.playlist_tracks;
create policy "Users can update own playlist tracks"
    on public.playlist_tracks for update
    using (auth.uid() = user_id)
    with check (auth.uid() = user_id);

drop policy if exists "Users can delete own playlist tracks" on public.playlist_tracks;
create policy "Users can delete own playlist tracks"
    on public.playlist_tracks for delete
    using (auth.uid() = user_id);

-- ==============================================================================
-- 3. User Preferences Table
-- ==============================================================================
-- Stores user onboarding preferences: music languages and favorite artists.
-- Synchronized with local Hive AppPrefs so preferences follow the user across devices.
create table if not exists public.user_preferences (
    id uuid primary key default gen_random_uuid(),
    user_id uuid not null unique references auth.users(id) on delete cascade,
    music_languages jsonb default '[]'::jsonb,
    favorite_artists jsonb default '[]'::jsonb,
    onboarding_completed boolean not null default false,
    created_at timestamptz not null default timezone('utc'::text, now()),
    updated_at timestamptz not null default timezone('utc'::text, now())
);

create index if not exists idx_user_preferences_user_id on public.user_preferences(user_id);

alter table public.user_preferences enable row level security;

-- ------------------------------------------------------------------------------
-- RLS Policies for public.user_preferences
-- ------------------------------------------------------------------------------
drop policy if exists "Users can view own preferences" on public.user_preferences;
create policy "Users can view own preferences"
    on public.user_preferences for select
    using (auth.uid() = user_id);

drop policy if exists "Users can insert own preferences" on public.user_preferences;
create policy "Users can insert own preferences"
    on public.user_preferences for insert
    with check (auth.uid() = user_id);

drop policy if exists "Users can update own preferences" on public.user_preferences;
create policy "Users can update own preferences"
    on public.user_preferences for update
    using (auth.uid() = user_id)
    with check (auth.uid() = user_id);

drop policy if exists "Users can delete own preferences" on public.user_preferences;
create policy "Users can delete own preferences"
    on public.user_preferences for delete
    using (auth.uid() = user_id);

