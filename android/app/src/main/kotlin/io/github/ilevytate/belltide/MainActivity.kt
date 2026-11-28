package io.github.ilevytate.belltide

import android.Manifest
import android.content.ActivityNotFoundException
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.media.AudioDeviceCallback
import android.media.AudioDeviceInfo
import android.media.AudioManager
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import androidx.core.content.ContextCompat
import androidx.core.net.toUri
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.github.ilevytate.belltide.clickup.ClickUpSync
import io.github.ilevytate.belltide.service.ChimePlayer
import io.github.ilevytate.belltide.service.EngineHub
import io.github.ilevytate.belltide.service.EngineSettings
import io.github.ilevytate.belltide.service.EngineStore
import io.github.ilevytate.belltide.service.TimerService

/**
 * Hosts the Flutter UI and bridges it to the timer service.
 *
 * Method channel `belltide/engine` carries commands; event channel
 * `belltide/engine/state` streams JSON snapshots of the running timers.
 */
class MainActivity : FlutterActivity() {
    private var stateListener: ((String) -> Unit)? = null
    private var pendingPermissionResult: MethodChannel.Result? = null
    private var methods: MethodChannel? = null

    /** Tells the UI when a volume or the ringer mode changes while it is on screen. */
    private val audioReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            methods?.invokeMethod("audioChanged", null)
        }
    }

    /** Headphones change which volume chimes use, so the volume buttons and the UI follow. */
    private val outputCallback = object : AudioDeviceCallback() {
        override fun onAudioDevicesAdded(addedDevices: Array<out AudioDeviceInfo>) = onOutputsChanged()
        override fun onAudioDevicesRemoved(removedDevices: Array<out AudioDeviceInfo>) = onOutputsChanged()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        methods = MethodChannel(messenger, METHOD_CHANNEL).also { it.setMethodCallHandler(::onMethodCall) }
        followChimeVolume(EngineStore(this).settings)
        EventChannel(messenger, EVENT_CHANNEL).setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                val listener: (String) -> Unit = { events.success(it) }
                stateListener?.let(EngineHub::removeListener)
                stateListener = listener
                EngineHub.addListener(listener)
                events.success(EngineHub.current())
            }

            override fun onCancel(arguments: Any?) {
                stateListener?.let(EngineHub::removeListener)
                stateListener = null
            }
        })
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        stateListener?.let(EngineHub::removeListener)
        stateListener = null
        methods = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

    override fun onResume() {
        super.onResume()
        runCatching { TimerService.restoreIfNeeded(this) }
    }

    // Started, not resumed: the phone's volume panel opens over the app, and the
    // volume shown behind it should keep up while the user drags its sliders.
    override fun onStart() {
        super.onStart()
        val filter = IntentFilter(AudioManager.RINGER_MODE_CHANGED_ACTION).apply { addAction(VOLUME_CHANGED) }
        ContextCompat.registerReceiver(this, audioReceiver, filter, ContextCompat.RECEIVER_NOT_EXPORTED)
        getSystemService(AudioManager::class.java).registerAudioDeviceCallback(outputCallback, null)
    }

    override fun onStop() {
        getSystemService(AudioManager::class.java).unregisterAudioDeviceCallback(outputCallback)
        unregisterReceiver(audioReceiver)
        super.onStop()
    }

    private fun onOutputsChanged() {
        followChimeVolume(EngineStore(this).settings)
        methods?.invokeMethod("audioChanged", null)
    }

    private fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "start" -> {
                    TimerService.start(this, call.requireArg("config"))
                    result.success(null)
                }
                "pause" -> command(TimerService.ACTION_PAUSE, call, result)
                "resume" -> command(TimerService.ACTION_RESUME, call, result)
                "skip" -> command(TimerService.ACTION_SKIP, call, result)
                "stop" -> command(TimerService.ACTION_STOP, call, result)
                "stopAll" -> {
                    TimerService.send(this, TimerService.ACTION_STOP_ALL)
                    result.success(null)
                }
                "currentState" -> result.success(EngineHub.current())
                "previewSound" -> {
                    ChimePlayer.get(this).preview(call.requireArg("sound"))
                    result.success(null)
                }
                "applySettings" -> {
                    val settings = EngineSettings(
                        audioStream = call.argument<String>("audioStream") ?: EngineSettings.STREAM_ALARM,
                        vibrate = call.argument<Boolean>("vibrate") ?: false,
                        level = call.argument<Number>("level")?.toFloat() ?: 1f,
                        duckOthers = call.argument<Boolean>("duckOthers") ?: true,
                        vibrateWhenSilenced = call.argument<Boolean>("vibrateWhenSilenced") ?: false,
                    )
                    EngineStore(this).settings = settings
                    ChimePlayer.get(this).onSettingsChanged()
                    followChimeVolume(settings)
                    result.success(null)
                }
                "audioStatus" -> result.success(audioStatus())
                "openVolumeSettings" -> {
                    openVolumeSettings()
                    result.success(null)
                }
                "notificationPermission" -> result.success(notificationPermission())
                "requestNotificationPermission" -> requestNotificationPermission(result)
                "openNotificationSettings" -> {
                    startActivity(
                        Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
                            .putExtra(Settings.EXTRA_APP_PACKAGE, packageName),
                    )
                    result.success(null)
                }
                "isIgnoringBatteryOptimizations" -> result.success(
                    getSystemService(PowerManager::class.java).isIgnoringBatteryOptimizations(packageName),
                )
                "openBatterySettings" -> {
                    openBatterySettings()
                    result.success(null)
                }
                "openUrl" -> {
                    val uri = call.requireArg<String>("url").toUri()
                    if (uri.scheme != "https") throw IllegalArgumentException("Only https links open")
                    startActivity(Intent(Intent.ACTION_VIEW, uri))
                    result.success(null)
                }
                "clickupGetToken" -> result.success(ClickUpSync.get(this).token)
                "clickupSetToken" -> {
                    ClickUpSync.get(this).token = call.argument<String>("token")
                    result.success(null)
                }
                "clickupSetLogging" -> {
                    ClickUpSync.get(this).loggingEnabled = call.argument<Boolean>("enabled") ?: true
                    result.success(null)
                }
                "clickupClearQueue" -> {
                    ClickUpSync.get(this).clearQueue()
                    result.success(null)
                }
                "clickupSyncStatus" -> result.success(ClickUpSync.get(this).status())
                "clickupSyncNow" -> {
                    val sync = ClickUpSync.get(this)
                    sync.flush { result.success(sync.status()) }
                }
                else -> result.notImplemented()
            }
        } catch (e: Exception) {
            result.error("engine_error", e.message, null)
        }
    }

    private fun command(action: String, call: MethodCall, result: MethodChannel.Result) {
        TimerService.send(this, action, call.requireArg<String>("id"))
        result.success(null)
    }

    private fun notificationPermission(): String = when {
        Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU -> "granted"
        checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) ==
            PackageManager.PERMISSION_GRANTED -> "granted"
        else -> "denied"
    }

    private fun requestNotificationPermission(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU || notificationPermission() == "granted") {
            result.success(true)
            return
        }
        // Only one request can be in flight; answer an older caller first.
        pendingPermissionResult?.success(false)
        pendingPermissionResult = result
        requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), REQUEST_NOTIFICATIONS)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != REQUEST_NOTIFICATIONS) return
        val granted = grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED
        pendingPermissionResult?.success(granted)
        pendingPermissionResult = null
    }

    /** Makes the phone's volume buttons adjust the chime volume while the app is on screen. */
    private fun followChimeVolume(settings: EngineSettings) {
        val audio = getSystemService(AudioManager::class.java)
        volumeControlStream = ChimePlayer.streamType(ChimePlayer.streamNow(audio, settings))
    }

    /** The phone volume chimes play at right now, and whether the ringer is silenced. */
    private fun audioStatus(): Map<String, Any> {
        val audio = getSystemService(AudioManager::class.java)
        val settings = EngineStore(this).settings
        // Media may have moved to or from headphones without anything being plugged in.
        followChimeVolume(settings)
        val stream = ChimePlayer.streamType(ChimePlayer.streamNow(audio, settings))
        return mapOf(
            "volume" to audio.getStreamVolume(stream),
            "maxVolume" to audio.getStreamMaxVolume(stream),
            "headphones" to ChimePlayer.externalOutput(audio),
            "ringer" to when (audio.ringerMode) {
                AudioManager.RINGER_MODE_SILENT -> "silent"
                AudioManager.RINGER_MODE_VIBRATE -> "vibrate"
                else -> "normal"
            },
        )
    }

    private fun openVolumeSettings() {
        try {
            // The volume panel slides up over the app, so the user never leaves it.
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                startActivity(Intent(Settings.Panel.ACTION_VOLUME))
                return
            }
        } catch (e: ActivityNotFoundException) {
            // Fall through to the full sound settings screen.
        }
        startActivity(Intent(Settings.ACTION_SOUND_SETTINGS))
    }

    private fun openBatterySettings() {
        val appDetails = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS)
            .setData(Uri.fromParts("package", packageName, null))
        try {
            startActivity(Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS))
        } catch (e: ActivityNotFoundException) {
            // Some OEM builds drop the battery list; app details always exists.
            startActivity(appDetails)
        }
    }

    private fun <T> MethodCall.requireArg(name: String): T =
        argument<T>(name) ?: throw IllegalArgumentException("Missing argument: $name")

    private companion object {
        const val METHOD_CHANNEL = "belltide/engine"
        const val EVENT_CHANNEL = "belltide/engine/state"
        const val REQUEST_NOTIFICATIONS = 4101

        /** AudioManager.VOLUME_CHANGED_ACTION, which the SDK hides but every device sends. */
        const val VOLUME_CHANGED = "android.media.VOLUME_CHANGED_ACTION"
    }
}
