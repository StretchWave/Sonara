package com.sonara.music

import android.content.Context
import android.content.SharedPreferences
/**
 * Single source of truth for inputControlEnabled on the native side.
 * Mirrors the Dart Hive value `inputControlEnabled` (default true) via
 * MethodChannel `com.sonara.music/inputControl`. Also persists to
 * SharedPreferences so the value survives process restart before Flutter
 * re-syncs.
 *
 * All native gating points (dispatchKeyEvent, MediaSession active state)
 * read from [isEnabled] — no drift between session state, command availability
 * and key dispatch.
 */
object InputControlManager {
    private const val PREFS_NAME = "sonara_input_control"
    private const val KEY_ENABLED = "inputControlEnabled"

    @Volatile
    var isEnabled: Boolean = true
        private set

    fun init(context: Context) {
        val prefs = prefs(context)
        isEnabled = prefs.getBoolean(KEY_ENABLED, true)
    }

    fun setEnabled(context: Context, enabled: Boolean) {
        isEnabled = enabled
        prefs(context).edit().putBoolean(KEY_ENABLED, enabled).apply()
    }

    fun setEnabledInMemory(enabled: Boolean) {
        isEnabled = enabled
    }

    private fun prefs(context: Context): SharedPreferences =
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
}
