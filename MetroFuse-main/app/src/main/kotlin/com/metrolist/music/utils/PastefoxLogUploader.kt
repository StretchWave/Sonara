/**
 * Metrolist Project (C) 2026
 * Licensed under GPL-3.0 | See git history for contributors
 */

package com.metrolist.music.utils

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONObject
import java.util.concurrent.TimeUnit

object PastefoxLogUploader {
    private const val API_URL = "https://api.pastefox.com/v1/pastes"
    private const val PUBLIC_URL_BASE = "https://pastefox.com"
    private val JSON_MEDIA_TYPE = "application/json; charset=utf-8".toMediaType()
    private val SECRET_PATTERNS =
        listOf(
            Regex("""(?i)\b(sp_dc|arl|authorization|cookie|set-cookie|x-api-key|access[_-]?token|refresh[_-]?token|client[_-]?secret|sessionid|ds_user_id)\s*[:=]\s*([^\s;,&]+)"""),
            Regex("""(?i)([?&](?:token|access_token|refresh_token|signature|sig|hdnea|auth)=)([^&#\s]+)"""),
        )

    private val client =
        OkHttpClient
            .Builder()
            .connectTimeout(8, TimeUnit.SECONDS)
            .readTimeout(15, TimeUnit.SECONDS)
            .callTimeout(20, TimeUnit.SECONDS)
            .build()

    suspend fun createLogPaste(
        title: String,
        content: String,
    ): Result<String> =
        withContext(Dispatchers.IO) {
            runCatching {
                val body =
                    JSONObject()
                        .put("title", title.take(100))
                        .put("content", content.redactSensitiveText())
                        .put("visibility", "PUBLIC")
                        .toString()
                        .toRequestBody(JSON_MEDIA_TYPE)
                val request =
                    Request
                        .Builder()
                        .url(API_URL)
                        .post(body)
                        .header("Accept", "application/json")
                        .build()

                client.newCall(request).execute().use { response ->
                    val responseBody = response.body.string()
                    if (!response.isSuccessful) {
                        throw IllegalStateException("Pastefox HTTP ${response.code}")
                    }

                    val root = JSONObject(responseBody)
                    if (root.optBoolean("success", false).not()) {
                        throw IllegalStateException(root.optString("error", "Pastefox upload failed"))
                    }

                    val data = root.optJSONObject("data")
                        ?: throw IllegalStateException("Pastefox response missing data")
                    data.optString("url")
                        .takeIf { it.startsWith("https://", ignoreCase = true) }
                        ?: data.optString("shareUrl")
                            .takeIf { it.startsWith("https://", ignoreCase = true) }
                        ?: data.optString("slug")
                            .takeIf { it.isNotBlank() }
                            ?.let { slug -> "$PUBLIC_URL_BASE/$slug" }
                        ?: throw IllegalStateException("Pastefox response missing slug")
                }
            }
        }

    private fun String.redactSensitiveText(): String =
        SECRET_PATTERNS.fold(this) { current, pattern ->
            pattern.replace(current) { match ->
                when (match.groupValues.size) {
                    3 -> {
                        val prefix = match.groupValues[1]
                        if (prefix.startsWith("?") || prefix.startsWith("&")) {
                            "$prefix<redacted>"
                        } else {
                            "$prefix=<redacted>"
                        }
                    }
                    else -> "<redacted>"
                }
            }
        }
}
