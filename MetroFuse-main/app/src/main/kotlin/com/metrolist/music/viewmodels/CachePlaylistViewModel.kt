/**
 * Metrolist Project (C) 2026
 * Licensed under GPL-3.0 | See git history for contributors
 */

package com.metrolist.music.viewmodels

import android.content.Context
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import androidx.media3.datasource.cache.SimpleCache
import com.metrolist.music.constants.HideExplicitKey
import com.metrolist.music.constants.HideVideoSongsKey
import com.metrolist.music.db.MusicDatabase
import com.metrolist.music.db.entities.Song
import com.metrolist.music.di.DownloadCache
import com.metrolist.music.di.PlayerCache
import com.metrolist.music.extensions.filterExplicit
import com.metrolist.music.extensions.filterVideoSongs
import com.metrolist.music.utils.dataStore
import com.metrolist.music.utils.get
import dagger.hilt.android.lifecycle.HiltViewModel
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch
import java.time.LocalDateTime
import javax.inject.Inject

@HiltViewModel
class CachePlaylistViewModel
    @Inject
    constructor(
        @ApplicationContext private val context: Context,
        private val database: MusicDatabase,
        @PlayerCache private val playerCache: SimpleCache,
        @DownloadCache private val downloadCache: SimpleCache,
    ) : ViewModel() {
        private val _cachedSongs = MutableStateFlow<List<Song>>(emptyList())
        val cachedSongs: StateFlow<List<Song>> = _cachedSongs

        init {
            viewModelScope.launch {
                while (true) {
                    val hideExplicit = context.dataStore.get(HideExplicitKey, false)
                    val hideVideoSongs = context.dataStore.get(HideVideoSongsKey, false)
                    val playerCacheKeys = playerCache.keys.toSet()
                    val downloadCacheKeys = downloadCache.keys.toSet()
                    val downloadedIds =
                        database
                            .downloadedSongsByNameAsc()
                            .first()
                            .mapTo(mutableSetOf()) { it.id }
                    val cacheKeysBySongId =
                        (playerCacheKeys + downloadCacheKeys)
                            .mapNotNull { key -> key.cacheMediaIdOrNull()?.let { mediaId -> mediaId to key } }
                            .filterNot { (mediaId, _) -> mediaId in downloadedIds }
                            .groupBy(
                                keySelector = { it.first },
                                valueTransform = { it.second },
                            )

                    val songs =
                        if (cacheKeysBySongId.isNotEmpty()) {
                            database.getSongsByIds(cacheKeysBySongId.keys.toList())
                        } else {
                            emptyList()
                        }

                    val completeSongs =
                        songs.filter { song ->
                            val candidateKeys = cacheKeysBySongId[song.id].orEmpty() + song.id
                            candidateKeys.any { key ->
                                playerCache.hasUsableCacheFor(key, song.format?.contentLength) ||
                                    downloadCache.hasUsableCacheFor(key, song.format?.contentLength)
                            }
                        }

                    if (completeSongs.isNotEmpty()) {
                        val now = LocalDateTime.now()
                        database.query {
                            completeSongs.forEach {
                                if (it.song.dateDownload == null || !it.song.isCached) {
                                    update(
                                        it.song.copy(
                                            dateDownload = it.song.dateDownload ?: now,
                                            isCached = true,
                                        )
                                    )
                                }
                            }
                        }
                    }

                    _cachedSongs.value =
                        completeSongs
                            .sortedByDescending { it.song.dateDownload ?: LocalDateTime.MIN }
                            .filterExplicit(hideExplicit)
                            .filterVideoSongs(hideVideoSongs)

                    delay(1000)
                }
            }
        }

        fun removeSongFromCache(songId: String) {
            val keys =
                (playerCache.keys + downloadCache.keys)
                    .filter { it.cacheMediaIdOrNull() == songId }
                    .toSet() + songId
            keys.forEach { key ->
                playerCache.removeResource(key)
                downloadCache.removeResource(key)
            }
            viewModelScope.launch {
                database.getSongById(songId)?.song?.let { song ->
                    database.query {
                        update(song.copy(isCached = false))
                    }
                }
            }
        }

        private fun SimpleCache.hasUsableCacheFor(
            key: String,
            contentLength: Long?,
        ): Boolean {
            val length = contentLength?.takeIf { it > 0L }
            if (length != null && runCatching { isCached(key, 0L, length) }.getOrDefault(false)) {
                return true
            }
            return runCatching {
                getCachedSpans(key).any { span ->
                    span.isCached && span.length > 0L && span.file?.exists() == true
                }
            }.getOrDefault(false)
        }

        private fun String.cacheMediaIdOrNull(): String? {
            val stripped =
                CACHE_KEY_PREFIXES.fold(trim()) { value, prefix ->
                    value.removePrefix(prefix)
                }
            return stripped
                .takeIf { it.isNotBlank() }
                ?.takeUnless { it.startsWith("http://", ignoreCase = true) }
                ?.takeUnless { it.startsWith("https://", ignoreCase = true) }
                ?.takeUnless { it.startsWith("file:", ignoreCase = true) }
        }

        private companion object {
            private val CACHE_KEY_PREFIXES =
                listOf(
                    "apple-wrapper-alac-v3:",
                    "apple-wrapper-alac-v2:",
                    "apple-wrapper-alac:",
                    "qobuz-fallback-v2:",
                    "qobuz-fallback:",
                    "tidal-flac-fallback-temp-v1:",
                    "tidal-flac-fallback:",
                    "deezer-fallback-audio:",
                    "soundcloud-fallback-mp3:",
                    "instagram-fallback-audio:",
                    "direct-http-audio:",
                    "youtube-fallback-aac:",
                )
        }
    }
