package com.sonara.music

import android.content.Context
import androidx.datastore.preferences.core.booleanPreferencesKey
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.preferencesDataStore
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.launch

private val Context.inputControlDataStore by preferencesDataStore(
    name = "input_control"
)

/**
 * Single source of truth for `inputControlEnabled`.
 *
 * Native owns the flag: persisted in Jetpack DataStore (default true) and
 * exposed as a [StateFlow]. Every gating point (session switch, receiver
 * switch, key dispatch, Dart handler via channels) collects or reads this
 * one flow. No copies, no duplicated flags.
 */
object InputControlStore {
    private val KEY_ENABLED = booleanPreferencesKey("inputControlEnabled")

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    private val _enabled = MutableStateFlow(true)

    /** Observable flag; Dart observes via EventChannel, native via collection. */
    val enabled: StateFlow<Boolean> = _enabled.asStateFlow()

    @Volatile
    private var initialised = false

    /**
     * Starts DataStore collection. Safe to call multiple times; subsequent
     * calls are no-ops. Must be called with an application context, ideally
     * in [android.app.Application.onCreate] or the launch activity's
     * `onCreate` before the Flutter engine attaches.
     */
    @Synchronized
    fun init(context: Context) {
        if (initialised) return
        initialised = true
        val appContext = context.applicationContext
        scope.launch {
            appContext.inputControlDataStore.data
                .map { prefs -> prefs[KEY_ENABLED] ?: true }
                .collect { value ->
                    if (_enabled.value != value) _enabled.value = value
                }
        }
    }

    /** Persists the flag; collectors (including the gating switch) react. */
    suspend fun setEnabled(context: Context, enabled: Boolean) {
        context.applicationContext.inputControlDataStore.edit { prefs ->
            prefs[KEY_ENABLED] = enabled
        }
        // Optimistic update so UI/channel reads see it before DataStore emits.
        _enabled.value = enabled
    }

    /** One-shot synchronous-feeling read of the persisted value. */
    suspend fun loadPersisted(context: Context): Boolean {
        return context.applicationContext.inputControlDataStore.data
            .map { prefs -> prefs[KEY_ENABLED] ?: true }
            .first()
    }
}
