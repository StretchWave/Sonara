package com.sonara.music

import android.content.ComponentName
import android.content.pm.PackageManager
import android.os.Bundle
import android.view.KeyEvent
import com.ryanheise.audioservice.AudioServiceActivity
import com.ryanheise.audioservice.AudioServiceGate
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch

class MainActivity : AudioServiceActivity() {
    companion object {
        const val CHANNEL = "com.sonara.music/inputControl"
        const val EVENTS = "com.sonara.music/inputControlEvents"

        private const val RECEIVER_CLASS =
            "com.ryanheise.audioservice.MediaButtonReceiver"

        private val MEDIA_KEYCODES = setOf(
            KeyEvent.KEYCODE_HEADSETHOOK,
            KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE,
            KeyEvent.KEYCODE_MEDIA_NEXT,
            KeyEvent.KEYCODE_MEDIA_PREVIOUS,
            KeyEvent.KEYCODE_MEDIA_STOP,
            KeyEvent.KEYCODE_MEDIA_PLAY,
            KeyEvent.KEYCODE_MEDIA_PAUSE
        )
    }

    private val activityScope =
        CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private var gateJob: Job? = null
    private var eventJob: Job? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        // Native owns the flag: load persisted value and apply the gating
        // switch before the Flutter engine (and audio_service) start, so a
        // kill/relaunch boots with the session state matching the toggle.
        InputControlStore.init(applicationContext)
        gateJob = activityScope.launch {
            InputControlStore.enabled.collect { enabled ->
                applyInputControl(enabled)
            }
        }
        super.onCreate(savedInstanceState)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        MethodChannel(messenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "getInputControlEnabled" -> {
                    result.success(InputControlStore.enabled.value)
                }
                "setInputControlEnabled" -> {
                    val enabled = call.argument<Boolean>("enabled") ?: true
                    activityScope.launch(Dispatchers.IO) {
                        InputControlStore.setEnabled(applicationContext, enabled)
                    }
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
        EventChannel(messenger, EVENTS).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(args: Any?, events: EventChannel.EventSink) {
                    eventJob = activityScope.launch {
                        InputControlStore.enabled.collect { enabled ->
                            events.success(enabled)
                        }
                    }
                }

                override fun onCancel(args: Any?) {
                    eventJob?.cancel()
                    eventJob = null
                }
            }
        )
    }

    override fun onDestroy() {
        gateJob?.cancel()
        eventJob?.cancel()
        activityScope.cancel()
        super.onDestroy()
    }

    /**
     * Master gating switch (requirements 1 + 2). Runs live on every toggle
     * via the StateFlow collector: no playback restart, no app restart, no
     * player or AudioManager-focus calls.
     */
    private fun applyInputControl(enabled: Boolean) {
        // Req 1: session deactivation. Inactive session => no lockscreen card,
        // no notification controls, no Auto/Wear target. Playback continues.
        // (Re)applied on every emission because audio_service re-asserts
        // active on play events; this collector is the last writer while off.
        AudioServiceGate.setInputControlEnabled(applicationContext, enabled)

        // Req 2: media-button receiver routing. Android can fall back to the
        // last-active app's registered receiver even with no active session,
        // so the component itself is disabled while off.
        // Note: we never call setMediaButtonReceiver() ourselves, so there
        // is no self-set fallback to clear; re-enabling the component is the
        // full "on" path.
        packageManager.setComponentEnabledSetting(
            ComponentName(applicationContext, RECEIVER_CLASS),
            if (enabled) {
                PackageManager.COMPONENT_ENABLED_STATE_ENABLED
            } else {
                PackageManager.COMPONENT_ENABLED_STATE_DISABLED
            },
            PackageManager.DONT_KILL_APP
        )
    }

    /**
     * Req 4: wired foreground key events (cosmetic only). While off, media
     * keys are left unconsumed so this window never intercepts them. This is
     * NOT what removes the app from system routing — requirements 1 and 2
     * do that.
     */
    override fun dispatchKeyEvent(event: KeyEvent): Boolean {
        if (!InputControlStore.enabled.value && event.keyCode in MEDIA_KEYCODES) {
            return super.dispatchKeyEvent(event)
        }
        return super.dispatchKeyEvent(event)
    }
}
