package com.sonara.music

import android.os.Bundle
import android.view.KeyEvent
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : AudioServiceActivity() {
    companion object {
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

    private val channelName = "com.sonara.music/inputControl"
    private var methodChannel: MethodChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        InputControlManager.init(this)
        methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
        methodChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "setInputControlEnabled" -> {
                    val enabled = call.argument<Boolean>("enabled") ?: true
                    InputControlManager.setEnabled(this, enabled)
                    result.success(null)
                }
                "getInputControlEnabled" -> {
                    result.success(InputControlManager.isEnabled)
                }
                else -> result.notImplemented()
            }
        }
        // Push current native value to Dart after engine ready (optional sync)
        // Dart is source of truth via Hive; native will be updated via setInputControlEnabled
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        InputControlManager.init(this)
        super.onCreate(savedInstanceState)
    }

    /**
     * Requirement 3: Wired foreground key events.
     * When toggle is off, explicitly pass through unhandled media keycodes
     * by returning false (unconsumed) rather than consuming them.
     * This ensures the app does not intercept when invisible to routing.
     */
    override fun dispatchKeyEvent(event: KeyEvent): Boolean {
        if (event.keyCode in MEDIA_KEYCODES && !InputControlManager.isEnabled) {
            // Pass through — do not consume; let system route to next eligible session
            return false
        }
        return super.dispatchKeyEvent(event)
    }

    override fun onKeyDown(keyCode: Int, event: KeyEvent): Boolean {
        if (keyCode in MEDIA_KEYCODES && !InputControlManager.isEnabled) {
            return false
        }
        return super.onKeyDown(keyCode, event)
    }
}
