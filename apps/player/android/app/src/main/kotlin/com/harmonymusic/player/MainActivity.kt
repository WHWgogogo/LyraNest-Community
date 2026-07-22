package com.harmonymusic.player

import android.Manifest
import android.content.ActivityNotFoundException
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import java.util.ArrayDeque
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var appLifecycleChannel: MethodChannel? = null
    private var desktopLyricsChannel: MethodChannel? = null
    private var systemMediaChannel: MethodChannel? = null
    private var systemMediaEventChannel: EventChannel? = null
    private var systemMediaEventSink: EventChannel.EventSink? = null
    private var systemMediaSession: SystemMediaSessionManager? = null
    private var pendingNotificationPermissionResult: MethodChannel.Result? = null
    private val pendingSystemMediaActions = ArrayDeque<String>()

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        appLifecycleChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            APP_LIFECYCLE_CHANNEL,
        ).also { channel ->
            channel.setMethodCallHandler { call, result ->
                when (call.method) {
                    "moveTaskToBack" -> result.success(moveTaskToBack(true))
                    "exitApplication" -> {
                        result.success(null)
                        finishAndRemoveTask()
                    }
                    else -> result.notImplemented()
                }
            }
        }
        systemMediaSession = SystemMediaSessionManager(applicationContext) { action ->
            runOnUiThread {
                dispatchSystemMediaAction(action)
            }
        }
        systemMediaChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            SYSTEM_MEDIA_CHANNEL,
        ).also { channel ->
            channel.setMethodCallHandler { call, result ->
                when (call.method) {
                    "update" -> {
                        systemMediaSession?.update(systemMediaUpdateFrom(call))
                        result.success(null)
                    }
                    "ackAction" -> {
                        val action = call.argument<String>("action")
                        val systemMediaAction = action?.let(
                            SystemMediaSessionManager::actionFromEvent,
                        )
                        if (systemMediaAction == null) {
                            result.error(
                                "invalid_action",
                                "System media action acknowledgement has an invalid action.",
                                null,
                            )
                        } else {
                            systemMediaSession?.acknowledgeAction(
                                action = systemMediaAction,
                                handled = call.argument<Boolean>("handled") ?: false,
                            )
                            result.success(null)
                        }
                    }
                    "clear",
                    "dispose" -> {
                        systemMediaSession?.clear()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
        }
        systemMediaEventChannel = EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            SYSTEM_MEDIA_EVENT_CHANNEL,
        ).also { channel ->
            channel.setStreamHandler(
                object : EventChannel.StreamHandler {
                    override fun onListen(
                        arguments: Any?,
                        events: EventChannel.EventSink?,
                    ) {
                        systemMediaEventSink = events
                        flushPendingSystemMediaActions()
                    }

                    override fun onCancel(arguments: Any?) {
                        systemMediaEventSink = null
                    }
                },
            )
        }
        desktopLyricsChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            DESKTOP_LYRICS_CHANNEL,
        ).also { channel ->
            channel.setMethodCallHandler { _, result ->
                result.error(
                    "desktop_lyrics_unavailable",
                    "Desktop lyrics are not available in LyraNest Community.",
                    null,
                )
            }
        }    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        appLifecycleChannel?.setMethodCallHandler(null)
        appLifecycleChannel = null
        systemMediaEventSink = null
        pendingSystemMediaActions.clear()
        systemMediaEventChannel?.setStreamHandler(null)
        systemMediaEventChannel = null
        systemMediaChannel?.setMethodCallHandler(null)
        systemMediaChannel = null
        systemMediaSession?.release()
        systemMediaSession = null
        desktopLyricsChannel?.setMethodCallHandler(null)
        desktopLyricsChannel = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

    override fun onDestroy() {
        pendingNotificationPermissionResult = null
        if (isFinishing) {
            systemMediaSession?.release()
        }
        super.onDestroy()
    }

    private fun systemMediaUpdateFrom(call: MethodCall): SystemMediaUpdate {
        return SystemMediaUpdate(
            title = call.argument<String>("title").orEmpty(),
            artist = call.argument<String>("artist")?.trim()?.takeIf { it.isNotEmpty() },
            album = call.argument<String>("album")?.trim()?.takeIf { it.isNotEmpty() },
            artworkUrl = call.argument<String>("artworkUrl")
                ?.trim()
                ?.takeIf { it.isNotEmpty() },
            status = call.argument<String>("status").orEmpty(),
            isLoading = call.argument<Boolean>("isLoading") ?: false,
            positionMs = call.argument<Number>("positionMs")?.toLong() ?: 0,
            durationMs = call.argument<Number>("durationMs")?.toLong() ?: 0,
            canSkipPrevious = call.argument<Boolean>("canSkipPrevious") ?: false,
            canSkipNext = call.argument<Boolean>("canSkipNext") ?: false,
            playbackMode = call.argument<String>("playbackMode").orEmpty(),
            desktopLyricsEnabled =
                call.argument<Boolean>("desktopLyricsEnabled") ?: false,
        )
    }

    private fun dispatchSystemMediaAction(action: String) {
        val sink = systemMediaEventSink
        if (sink == null) {
            enqueueSystemMediaAction(action)
            return
        }

        try {
            sink.success(mapOf("action" to action))
        } catch (_: RuntimeException) {
            systemMediaEventSink = null
            enqueueSystemMediaAction(action)
        }
    }

    private fun flushPendingSystemMediaActions() {
        while (pendingSystemMediaActions.isNotEmpty()) {
            val action = pendingSystemMediaActions.removeFirst()
            dispatchSystemMediaAction(action)
            if (systemMediaEventSink == null) {
                return
            }
        }
    }

    private fun enqueueSystemMediaAction(action: String) {
        while (pendingSystemMediaActions.size >= MAX_PENDING_SYSTEM_MEDIA_ACTIONS) {
            pendingSystemMediaActions.removeFirst()
        }
        pendingSystemMediaActions.addLast(action)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        if (requestCode == NOTIFICATION_PERMISSION_REQUEST_CODE) {
            val pendingResult = pendingNotificationPermissionResult
            pendingNotificationPermissionResult = null
            val canPostNotifications =
                DesktopLyricsOverlayService.canPostNotifications(applicationContext)
            val state = if (canPostNotifications) {
                "permissionGranted"
            } else {
                "notificationPermissionDenied"
            }
            val message = if (canPostNotifications) {
                "Overlay and notification permissions are granted."
            } else {
                "Notification permission was denied. Android may hide the foreground notification."
            }
            pendingResult?.success(
                DesktopLyricsOverlayService.statusMap(
                    applicationContext,
                    state = state,
                    message = message,
                ),
            )
            return
        }
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
    }

    private fun requestDesktopLyricsPermissions(result: MethodChannel.Result) {
        if (!DesktopLyricsOverlayService.canDrawOverlays(applicationContext)) {
            result.success(openOverlayPermissionSettings())
            return
        }

        if (
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) !=
            PackageManager.PERMISSION_GRANTED
        ) {
            if (pendingNotificationPermissionResult != null) {
                result.success(
                    DesktopLyricsOverlayService.statusMap(
                        applicationContext,
                        state = "error",
                        message = "A notification permission request is already active.",
                    ),
                )
                return
            }
            pendingNotificationPermissionResult = result
            requestPermissions(
                arrayOf(Manifest.permission.POST_NOTIFICATIONS),
                NOTIFICATION_PERMISSION_REQUEST_CODE,
            )
            return
        }

        result.success(
            DesktopLyricsOverlayService.statusMap(
                applicationContext,
                state = "permissionGranted",
                message = "Overlay and notification permissions are granted.",
            ),
        )
    }

    private fun openOverlayPermissionSettings(): Map<String, Any> {
        if (DesktopLyricsOverlayService.canDrawOverlays(applicationContext)) {
            return DesktopLyricsOverlayService.statusMap(
                applicationContext,
                state = "permissionGranted",
                message = "Overlay permission is already granted.",
            )
        }

        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) {
            return DesktopLyricsOverlayService.statusMap(
                applicationContext,
                state = "permissionGranted",
                message = "Overlay permission is granted at install time on this Android version.",
            )
        }

        return try {
            val packageUri = Uri.parse("package:$packageName")
            val intent = Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION, packageUri)
            startActivity(intent)
            DesktopLyricsOverlayService.statusMap(
                applicationContext,
                state = "permissionRequestOpened",
                message = "Opened Android overlay permission settings.",
            )
        } catch (exception: ActivityNotFoundException) {
            startActivity(Intent(Settings.ACTION_SETTINGS))
            DesktopLyricsOverlayService.statusMap(
                applicationContext,
                state = "permissionRequestOpened",
                message = "Opened Android settings. Enable display over other apps for this app.",
            )
        } catch (exception: RuntimeException) {
            DesktopLyricsOverlayService.statusMap(
                applicationContext,
                state = "error",
                message = exception.localizedMessage ?: exception.javaClass.simpleName,
            )
        }
    }

    companion object {
        private const val APP_LIFECYCLE_CHANNEL = "com.harmonymusic.player/app_lifecycle"
        private const val DESKTOP_LYRICS_CHANNEL = "com.harmonymusic.player/desktop_lyrics"
        private const val SYSTEM_MEDIA_CHANNEL = "com.harmonymusic.player/system_media"
        private const val SYSTEM_MEDIA_EVENT_CHANNEL =
            "com.harmonymusic.player/system_media_events"
        private const val NOTIFICATION_PERMISSION_REQUEST_CODE = 24019
        private const val MAX_PENDING_SYSTEM_MEDIA_ACTIONS = 8
    }
}
