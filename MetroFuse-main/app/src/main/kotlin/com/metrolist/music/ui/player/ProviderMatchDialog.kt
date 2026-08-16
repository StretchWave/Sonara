/**
 * Metrolist Project (C) 2026
 * Licensed under GPL-3.0 | See git history for contributors
 */

package com.metrolist.music.ui.player

import android.widget.Toast
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.ListItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.metrolist.music.LocalPlayerConnection
import com.metrolist.music.R
import com.metrolist.music.models.MediaMetadata
import com.metrolist.music.providers.ProviderMatchCandidate
import com.metrolist.music.providers.ProviderMatchSearch
import com.metrolist.music.providers.displayName
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

@Composable
fun ProviderMatchDialog(
    mediaMetadata: MediaMetadata,
    onDismiss: () -> Unit,
) {
    val context = LocalContext.current
    val playerConnection = LocalPlayerConnection.current
    var candidates by remember(mediaMetadata.id) { mutableStateOf<List<ProviderMatchCandidate>?>(null) }
    var failed by remember(mediaMetadata.id) { mutableStateOf(false) }

    LaunchedEffect(mediaMetadata.id) {
        failed = false
        candidates = runCatching {
            ProviderMatchSearch.search(context, mediaMetadata)
        }.onFailure {
            failed = true
        }.getOrDefault(emptyList())
    }

    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(stringResource(R.string.choose_audio_source)) },
        text = {
            when {
                candidates == null -> {
                    Box(
                        contentAlignment = Alignment.Center,
                        modifier = Modifier
                            .fillMaxWidth()
                            .heightIn(min = 140.dp),
                    ) {
                        CircularProgressIndicator()
                    }
                }
                candidates.orEmpty().isEmpty() -> {
                    Text(
                        text = stringResource(
                            if (failed) {
                                R.string.audio_source_matches_failed
                            } else {
                                R.string.audio_source_matches_empty
                            },
                        ),
                    )
                }
                else -> {
                    LazyColumn(
                        modifier = Modifier.heightIn(max = 440.dp),
                    ) {
                        item(key = "auto") {
                            ListItem(
                                headlineContent = { Text(stringResource(R.string.automatic_audio_source)) },
                                supportingContent = { Text(stringResource(R.string.automatic_audio_source_description)) },
                                modifier = Modifier.clickable {
                                    playerConnection?.service?.setProviderMatchOverride(
                                        mediaId = mediaMetadata.id,
                                        provider = null,
                                        providerTrackId = null,
                                        label = null,
                                    )
                                    Toast.makeText(context, R.string.audio_source_match_updated, Toast.LENGTH_SHORT).show()
                                    onDismiss()
                                },
                            )
                            HorizontalDivider()
                        }
                        items(
                            items = candidates.orEmpty(),
                            key = { "${it.provider.name}:${it.providerTrackId}" },
                        ) { candidate ->
                            Column(
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .clickable {
                                        playerConnection?.service?.setProviderMatchOverride(
                                            mediaId = mediaMetadata.id,
                                            provider = candidate.provider,
                                            providerTrackId = candidate.providerTrackId,
                                            label = candidate.label,
                                        )
                                        Toast.makeText(context, R.string.audio_source_match_updated, Toast.LENGTH_SHORT).show()
                                        onDismiss()
                                    }
                                    .padding(vertical = 4.dp),
                            ) {
                                ListItem(
                                    overlineContent = {
                                        Text(
                                            text = candidate.provider.displayName(),
                                            color = MaterialTheme.colorScheme.primary,
                                        )
                                    },
                                    headlineContent = { Text(candidate.title) },
                                    supportingContent = {
                                        Text(
                                            listOf(candidate.artist, candidate.album)
                                                .filter { !it.isNullOrBlank() }
                                                .joinToString(" - "),
                                        )
                                    },
                                )
                            }
                            HorizontalDivider()
                        }
                    }
                }
            }
        },
        confirmButton = {
            TextButton(onClick = onDismiss) {
                Text(stringResource(android.R.string.cancel))
            }
        },
    )
}
