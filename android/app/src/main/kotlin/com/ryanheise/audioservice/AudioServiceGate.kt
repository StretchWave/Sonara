package com.ryanheise.audioservice

import android.app.NotificationManager
import android.content.Context
import android.support.v4.media.session.MediaSessionCompat

/**
 * Same-package shim for gating audio_service's MediaSessionCompat.
 *
 * `AudioService.instance` is package-private static and `mediaSession` is
 * private, so code in `com.sonara.music` cannot touch the session directly.
 * This helper lives in the plugin's package to reach them via reflection
 * without forking audio_service.
 *
 * Off: `mediaSession.isActive = false` + cancel the media notification +
 * drop foreground state WITHOUT stopping playback (`just_audio` keeps
 * playing; no `stopSelf()`, no player calls). On: set active again; the
 * notification rebuilds on the next playback-state update from Dart.
 * Audio focus is deliberately untouched: on API 26+ button routing follows
 * session active/playing state, not focus ownership.
 */
object AudioServiceGate {
    // Mirrors AudioService.NOTIFICATION_ID (private static final int 1124).
    private const val NOTIFICATION_ID = 1124

    private fun mediaSession(): MediaSessionCompat? {
        return try {
            val serviceClass = Class.forName("com.ryanheise.audioservice.AudioService")
            val instanceField = serviceClass.getDeclaredField("instance").apply {
                isAccessible = true
            }
            val instance = instanceField.get(null) ?: return null
            val sessionField = serviceClass.getDeclaredField("mediaSession").apply {
                isAccessible = true
            }
            sessionField.get(instance) as? MediaSessionCompat
        } catch (_: Exception) {
            null
        }
    }

    /**
     * Applies the master session switch. Never touches playback or focus.
     * Safe to call when the service isn't running (no-op returning false).
     */
    fun setInputControlEnabled(context: Context, enabled: Boolean): Boolean {
        val session = mediaSession() ?: return false
        try {
            if (!enabled) {
                if (session.isActive) session.isActive = false
                val nm = context.getSystemService(Context.NOTIFICATION_SERVICE)
                    as? NotificationManager
                nm?.cancel(NOTIFICATION_ID)
            } else {
                if (!session.isActive) session.isActive = true
            }
        } catch (_: Exception) {
            return false
        }
        return true
    }
}
