/// Strongly typed provider identifiers, replacing scattered raw string
/// literals throughout the codebase.
///
/// Each id serializes to a stable persistence-safe string via [stableId],
/// and deserializes via [fromStableId]. Unknown / legacy aliases are handled
/// gracefully so old caches and configs keep working.
library;

/// The role a provider plays in the routing system.
enum ProviderRole {
  /// Mainstream catalog with ISRC, metadata, lossless (Qobuz, Tidal, …).
  primaryCatalog,

  /// Direct video/audio source (YouTube Music).
  video,

  /// Community-uploaded content (SoundCloud).
  community,

  /// Public-domain / archive content (Internet Archive).
  archive,

  /// Social-media audio extraction (Instagram).
  social,
}

/// Every audio source the app can route through.
enum ProviderId {
  qobuz(
    stableId: 'qobuz',
    displayName: 'Qobuz',
    role: ProviderRole.primaryCatalog,
  ),
  tidal(
    stableId: 'tidal',
    displayName: 'Tidal',
    role: ProviderRole.primaryCatalog,
  ),
  deezer(
    stableId: 'deezer',
    displayName: 'Deezer',
    role: ProviderRole.primaryCatalog,
  ),
  apple(
    stableId: 'apple',
    displayName: 'Apple Music',
    role: ProviderRole.primaryCatalog,
  ),
  amazon(
    stableId: 'amazon',
    displayName: 'Amazon Music',
    role: ProviderRole.primaryCatalog,
  ),
  youtubeMusic(
    stableId: 'youtube_music',
    displayName: 'YouTube Music',
    role: ProviderRole.video,
  ),
  soundcloud(
    stableId: 'soundcloud',
    displayName: 'SoundCloud',
    role: ProviderRole.community,
  ),
  internetArchive(
    stableId: 'internet_archive',
    displayName: 'Internet Archive',
    role: ProviderRole.archive,
  ),
  instagram(
    stableId: 'instagram',
    displayName: 'Instagram',
    role: ProviderRole.social,
  );

  const ProviderId({
    required this.stableId,
    required this.displayName,
    required this.role,
  });

  /// Persistence-safe string id (e.g. `'qobuz'`, `'youtube_music'`).
  final String stableId;

  /// Human-readable name for display.
  final String displayName;

  /// The role this provider plays in routing decisions.
  final ProviderRole role;

  /// Whether this provider is a lossless catalog source that can verify
  /// recordings by ISRC.
  bool get isCatalogProvider => role == ProviderRole.primaryCatalog;

  /// Whether this provider can verify it holds the *exact* recording the
  /// user picked (ISRC match or provider track ID).
  bool get canVerifyExactRecording =>
      role == ProviderRole.primaryCatalog || role == ProviderRole.video;

  /// Legacy alias map — old settings/caches may contain these.
  static const Map<String, String> _aliases = {
    'youtube': 'youtube_music',
    'ytmusic': 'youtube_music',
    'yt': 'youtube_music',
    'sc': 'soundcloud',
    'ia': 'internet_archive',
    'ig': 'instagram',
  };

  /// Resolves a stable id string (including legacy aliases) to a
  /// [ProviderId], or `null` when the id is unknown.
  static ProviderId? fromStableId(String? id) {
    if (id == null || id.isEmpty) return null;
    final normalized = _aliases[id] ?? id;
    for (final provider in ProviderId.values) {
      if (provider.stableId == normalized) return provider;
    }
    return null;
  }

  /// Like [fromStableId] but throws an [ArgumentError] for unknown ids.
  static ProviderId requireStableId(String id) {
    final result = fromStableId(id);
    if (result == null) {
      throw ArgumentError.value(id, 'id', 'Unknown provider id');
    }
    return result;
  }

  /// All stable id strings that should be recognized (including aliases).
  static Set<String> get allKnownIds => {
        for (final p in ProviderId.values) p.stableId,
        ..._aliases.keys,
      };

  /// The default provider priority order.
  static const List<ProviderId> defaultOrder = [
    qobuz,
    tidal,
    deezer,
    apple,
    amazon,
    youtubeMusic,
    soundcloud,
    instagram,
    internetArchive,
  ];

  @override
  String toString() => stableId;
}
