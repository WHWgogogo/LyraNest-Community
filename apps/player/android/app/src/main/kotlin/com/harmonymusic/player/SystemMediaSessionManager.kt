package com.harmonymusic.player

import com.lyranest.community.player.R

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.media.MediaMetadata
import android.media.session.MediaSession
import android.media.session.PlaybackState
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.view.KeyEvent
import java.io.ByteArrayOutputStream
import java.net.HttpURLConnection
import java.net.URL
import java.util.concurrent.Executors

data class SystemMediaUpdate(
    val title: String,
    val artist: String?,
    val album: String?,
    val artworkUrl: String?,
    val status: String,
    val isLoading: Boolean,
    val positionMs: Long,
    val durationMs: Long,
    val canSkipPrevious: Boolean,
    val canSkipNext: Boolean,
    val playbackMode: String,
    val desktopLyricsEnabled: Boolean,
)

internal data class SystemMediaActionPresentation(
    val label: String,
    val iconResource: Int,
)

class SystemMediaSessionManager(
    context: Context,
    private val onAction: (String) -> Unit,
) {
    private val applicationContext = context.applicationContext
    private val notificationManager =
        applicationContext.getSystemService(NotificationManager::class.java)
    private val mediaSession = MediaSession(applicationContext, MEDIA_SESSION_TAG)
    private val mainHandler = Handler(Looper.getMainLooper())
    private val artworkExecutor = Executors.newSingleThreadExecutor()

    private var currentUpdate: SystemMediaUpdate? = null
    private var requestedArtworkUrl: String? = null
    private var artwork: Bitmap? = null
    private var artworkGeneration = 0L
    private var pendingPlaybackAction: PendingPlaybackAction? = null
    private var pendingActionTimeout: Runnable? = null
    private var lastAction: String? = null
    private var lastActionAtMs = 0L
    private var released = false

    private data class PendingPlaybackAction(
        val action: String,
        val expectedPlaying: Boolean,
        var acknowledged: Boolean = false,
    )

    init {
        createNotificationChannel()
        mediaSession.setFlags(
            MediaSession.FLAG_HANDLES_MEDIA_BUTTONS or
                MediaSession.FLAG_HANDLES_TRANSPORT_CONTROLS,
        )
        mediaSession.setMediaButtonReceiver(
            createBroadcastPendingIntent(Intent.ACTION_MEDIA_BUTTON, REQUEST_MEDIA_BUTTON),
        )
        mediaSession.setCallback(
            object : MediaSession.Callback() {
                override fun onPlay() {
                    dispatchAction(ACTION_PLAY)
                }

                override fun onPause() {
                    dispatchAction(ACTION_PAUSE)
                }

                override fun onSkipToPrevious() {
                    dispatchAction(ACTION_PREVIOUS)
                }

                override fun onSkipToNext() {
                    dispatchAction(ACTION_NEXT)
                }

                override fun onCustomAction(action: String, extras: android.os.Bundle?) {
                    dispatchAction(action)
                }
            },
        )
        activeManager = this
    }

    fun update(update: SystemMediaUpdate) {
        if (released) {
            return
        }
        if (update.title.isBlank()) {
            clear()
            return
        }

        reconcilePendingPlaybackAction(update)
        currentUpdate = update
        refreshArtwork(update.artworkUrl)
        refreshMediaSession()
        publishNotification()
    }

    fun clear() {
        if (released) {
            return
        }
        currentUpdate = null
        clearPendingPlaybackAction()
        requestedArtworkUrl = null
        artwork = null
        artworkGeneration++
        mediaSession.setMetadata(null)
        mediaSession.setPlaybackState(
            PlaybackState.Builder()
                .setState(PlaybackState.STATE_NONE, 0, 0f)
                .build(),
        )
        mediaSession.isActive = false
        notificationManager.cancel(NOTIFICATION_ID)
    }

    fun release() {
        if (released) {
            return
        }
        released = true
        currentUpdate = null
        clearPendingPlaybackAction()
        artwork = null
        artworkGeneration++
        notificationManager.cancel(NOTIFICATION_ID)
        mediaSession.isActive = false
        mediaSession.release()
        artworkExecutor.shutdownNow()
        if (activeManager === this) {
            activeManager = null
        }
    }

    fun acknowledgeAction(action: String, handled: Boolean) {
        val pendingAction = pendingPlaybackAction
        if (released || pendingAction?.action != action) {
            return
        }
        if (!handled) {
            clearPendingPlaybackAction()
            refreshMediaSession()
            publishNotification()
            return
        }

        pendingAction.acknowledged = true
        schedulePendingPlaybackActionTimeout(
            action = action,
            timeoutMs = ACTION_STATE_SYNC_TIMEOUT_MS,
        )
    }

    private fun reconcilePendingPlaybackAction(update: SystemMediaUpdate) {
        val pendingAction = pendingPlaybackAction ?: return
        if (matchesExpectedPlayback(update, pendingAction.expectedPlaying)) {
            clearPendingPlaybackAction()
        }
    }

    private fun matchesExpectedPlayback(
        update: SystemMediaUpdate,
        expectedPlaying: Boolean,
    ): Boolean {
        val isPlayingOrLoading =
            update.status == STATUS_PLAYING ||
                update.status == STATUS_LOADING ||
                update.isLoading
        return isPlayingOrLoading == expectedPlaying
    }

    private fun refreshMediaSession(
        isPlayingOverride: Boolean? = pendingPlaybackAction?.expectedPlaying,
    ) {
        val update = currentUpdate ?: return
        mediaSession.setMetadata(buildMetadata(update))
        mediaSession.setPlaybackState(buildPlaybackState(update, isPlayingOverride))
        mediaSession.isActive = true
    }

    private fun buildMetadata(update: SystemMediaUpdate): MediaMetadata {
        return MediaMetadata.Builder()
            .putString(MediaMetadata.METADATA_KEY_TITLE, update.title)
            .putString(MediaMetadata.METADATA_KEY_ARTIST, update.artist.orEmpty())
            .putString(MediaMetadata.METADATA_KEY_ALBUM, update.album.orEmpty())
            .putLong(
                MediaMetadata.METADATA_KEY_DURATION,
                update.durationMs.coerceAtLeast(0),
            )
            .apply {
                update.artworkUrl?.let { artworkUrl ->
                    putString(MediaMetadata.METADATA_KEY_ART_URI, artworkUrl)
                    putString(MediaMetadata.METADATA_KEY_ALBUM_ART_URI, artworkUrl)
                }
                artwork?.let { bitmap ->
                    putBitmap(MediaMetadata.METADATA_KEY_ART, bitmap)
                    putBitmap(MediaMetadata.METADATA_KEY_ALBUM_ART, bitmap)
                }
            }
            .build()
    }

    private fun buildPlaybackState(
        update: SystemMediaUpdate,
        isPlayingOverride: Boolean?,
    ): PlaybackState {
        val isPlaying = isPlayingOverride ?: (update.status == STATUS_PLAYING)
        val isLoading = isPlayingOverride == null &&
            (update.status == STATUS_LOADING || update.isLoading)
        val sessionState = when {
            isPlaying -> PlaybackState.STATE_PLAYING
            isLoading -> PlaybackState.STATE_BUFFERING
            update.status == STATUS_STOPPED ||
                update.status == STATUS_COMPLETED ||
                update.status == STATUS_ERROR -> PlaybackState.STATE_STOPPED
            else -> PlaybackState.STATE_PAUSED
        }
        val position = update.positionMs
            .coerceAtLeast(0)
            .let { value ->
                if (update.durationMs > 0) {
                    value.coerceAtMost(update.durationMs)
                } else {
                    value
                }
            }
        var actions = PlaybackState.ACTION_PLAY_PAUSE
        actions = actions or if (isPlaying) {
            PlaybackState.ACTION_PAUSE
        } else {
            PlaybackState.ACTION_PLAY
        }
        val slotPlan = SystemMediaControlSlotPlanner.create(
            canSkipPrevious = update.canSkipPrevious,
            canSkipNext = update.canSkipNext,
        )
        if (slotPlan.advertisePreviousAction) {
            actions = actions or PlaybackState.ACTION_SKIP_TO_PREVIOUS
        }
        if (slotPlan.advertiseNextAction) {
            actions = actions or PlaybackState.ACTION_SKIP_TO_NEXT
        }

        return PlaybackState.Builder()
            .setActions(actions)
            .setState(
                sessionState,
                position,
                if (isPlaying) 1f else 0f,
            )
            .apply {
                slotPlan.customActionOrder.forEach { action ->
                    addCustomAction(buildCustomAction(action, update))
                }
            }
            .build()
    }

    private fun buildCustomAction(
        action: String,
        update: SystemMediaUpdate,
    ): PlaybackState.CustomAction {
        val presentation = customActionPresentation(action, update)
        return PlaybackState.CustomAction.Builder(
            action,
            presentation.label,
            presentation.iconResource,
        ).build()
    }

    private fun publishNotification(
        isPlayingOverride: Boolean? = pendingPlaybackAction?.expectedPlaying,
    ) {
        val update = currentUpdate ?: return
        val isPlaying = isPlayingOverride ?: (update.status == STATUS_PLAYING)
        val isLoading = isPlayingOverride == null &&
            (update.status == STATUS_LOADING || update.isLoading)
        val slotPlan = SystemMediaControlSlotPlanner.create(
            canSkipPrevious = update.canSkipPrevious,
            canSkipNext = update.canSkipNext,
        )
        val playbackModePresentation = customActionPresentation(
            ACTION_CYCLE_PLAYBACK_MODE,
            update,
        )
        val playPauseAction = if (isPlaying) {
            Notification.Action.Builder(
                android.R.drawable.ic_media_pause,
                "Pause",
                createBroadcastPendingIntent(ACTION_PAUSE, REQUEST_PAUSE),
            ).build()
        } else {
            Notification.Action.Builder(
                android.R.drawable.ic_media_play,
                "Play",
                createBroadcastPendingIntent(ACTION_PLAY, REQUEST_PLAY),
            ).build()
        }
        val playbackModeAction = Notification.Action.Builder(
            playbackModePresentation.iconResource,
            playbackModePresentation.label,
            createBroadcastPendingIntent(
                ACTION_CYCLE_PLAYBACK_MODE,
                REQUEST_CYCLE_PLAYBACK_MODE,
            ),
        ).build()
        val previousAction = buildNotificationSkipAction(
            action = ACTION_PREVIOUS,
            enabled = slotPlan.previousActionEnabled,
            enabledIconResource = android.R.drawable.ic_media_previous,
            disabledIconResource = R.drawable.ic_system_media_previous_disabled,
            enabledLabel = "Previous",
            disabledLabel = "Previous unavailable",
            requestCode = REQUEST_PREVIOUS,
        )
        val nextAction = buildNotificationSkipAction(
            action = ACTION_NEXT,
            enabled = slotPlan.nextActionEnabled,
            enabledIconResource = android.R.drawable.ic_media_next,
            disabledIconResource = R.drawable.ic_system_media_next_disabled,
            enabledLabel = "Next",
            disabledLabel = "Next unavailable",
            requestCode = REQUEST_NEXT,
        )
        val actionsBySlot = mapOf(
            SystemMediaControlSlot.PLAYBACK_MODE to playbackModeAction,
            SystemMediaControlSlot.PREVIOUS to previousAction,
            SystemMediaControlSlot.PLAY_PAUSE to playPauseAction,
            SystemMediaControlSlot.NEXT to nextAction,
        )
        val builder = notificationBuilder()
            .setSmallIcon(R.drawable.ic_system_media_notification)
            .setContentTitle(update.title)
            .setContentText(notificationText(update))
            .setOnlyAlertOnce(true)
            .setShowWhen(false)
            .setVisibility(Notification.VISIBILITY_PUBLIC)
            .setCategory(Notification.CATEGORY_TRANSPORT)
            .setOngoing(isPlaying || isLoading)
            .setStyle(
                Notification.MediaStyle()
                    .setMediaSession(mediaSession.sessionToken)
                    .setShowActionsInCompactView(1, 2, 3),
            )
            .apply {
                slotPlan.slots.forEach { slot ->
                    addAction(requireNotNull(actionsBySlot[slot]))
                }
            }

        createContentIntent()?.let(builder::setContentIntent)
        artwork?.let(builder::setLargeIcon)

        try {
            notificationManager.notify(NOTIFICATION_ID, builder.build())
        } catch (_: SecurityException) {
        }
    }

    private fun buildNotificationSkipAction(
        action: String,
        enabled: Boolean,
        enabledIconResource: Int,
        disabledIconResource: Int,
        enabledLabel: String,
        disabledLabel: String,
        requestCode: Int,
    ): Notification.Action {
        return Notification.Action.Builder(
            if (enabled) enabledIconResource else disabledIconResource,
            if (enabled) enabledLabel else disabledLabel,
            createBroadcastPendingIntent(action, requestCode),
        ).build()
    }

    private fun notificationBuilder(): Notification.Builder {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(applicationContext, NOTIFICATION_CHANNEL_ID)
        } else {
            Notification.Builder(applicationContext)
        }
    }

    private fun notificationText(update: SystemMediaUpdate): String {
        return listOfNotNull(
            update.artist?.trim()?.takeIf { it.isNotEmpty() },
            update.album?.trim()?.takeIf { it.isNotEmpty() },
            playbackModeActionPresentation(update.playbackMode).label,
            notificationDesktopLyricsStatusLabel(update.desktopLyricsEnabled),
        ).joinToString(" / ")
    }

    private fun createContentIntent(): PendingIntent? {
        val launchIntent = applicationContext.packageManager
            .getLaunchIntentForPackage(applicationContext.packageName)
            ?.apply {
                addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP)
            }
            ?: return null
        return PendingIntent.getActivity(
            applicationContext,
            REQUEST_CONTENT,
            launchIntent,
            pendingIntentFlags(),
        )
    }

    private fun createBroadcastPendingIntent(action: String, requestCode: Int): PendingIntent {
        val intent = Intent(applicationContext, SystemMediaActionReceiver::class.java).apply {
            this.action = action
        }
        return PendingIntent.getBroadcast(
            applicationContext,
            requestCode,
            intent,
            pendingIntentFlags(),
        )
    }

    private fun pendingIntentFlags(): Int {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        } else {
            PendingIntent.FLAG_UPDATE_CURRENT
        }
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            return
        }
        val channel = NotificationChannel(
            NOTIFICATION_CHANNEL_ID,
            "Music playback",
            NotificationManager.IMPORTANCE_LOW,
        ).apply {
            description = "Playback controls and current track information."
            lockscreenVisibility = Notification.VISIBILITY_PUBLIC
            setShowBadge(false)
        }
        notificationManager.createNotificationChannel(channel)
    }

    private fun refreshArtwork(artworkUrl: String?) {
        val normalizedUrl = normalizeArtworkUrl(artworkUrl)
        if (normalizedUrl == requestedArtworkUrl) {
            return
        }

        requestedArtworkUrl = normalizedUrl
        artwork = null
        val generation = ++artworkGeneration
        if (normalizedUrl == null) {
            return
        }

        artworkExecutor.execute {
            val decodedArtwork = downloadArtwork(normalizedUrl)
            mainHandler.post {
                if (
                    !released &&
                    generation == artworkGeneration &&
                    normalizedUrl == requestedArtworkUrl
                ) {
                    artwork = decodedArtwork
                    refreshMediaSession()
                    publishNotification()
                }
            }
        }
    }

    private fun normalizeArtworkUrl(value: String?): String? {
        val url = value?.trim()?.takeIf { it.isNotEmpty() } ?: return null
        return try {
            val uri = Uri.parse(url)
            if (
                (uri.scheme.equals("http", ignoreCase = true) ||
                    uri.scheme.equals("https", ignoreCase = true)) &&
                !uri.host.isNullOrBlank()
            ) {
                url
            } else {
                null
            }
        } catch (_: RuntimeException) {
            null
        }
    }

    private fun downloadArtwork(url: String): Bitmap? {
        val connection = (URL(url).openConnection() as? HttpURLConnection) ?: return null
        return try {
            connection.instanceFollowRedirects = true
            connection.connectTimeout = ARTWORK_TIMEOUT_MS
            connection.readTimeout = ARTWORK_TIMEOUT_MS
            connection.doInput = true
            connection.connect()
            if (connection.responseCode !in 200..299) {
                return null
            }
            if (connection.contentLengthLong > MAX_ARTWORK_BYTES) {
                return null
            }

            val bytes = connection.inputStream.use(::readArtworkBytes) ?: return null
            decodeArtwork(bytes)
        } catch (_: Exception) {
            null
        } finally {
            connection.disconnect()
        }
    }

    private fun readArtworkBytes(input: java.io.InputStream): ByteArray? {
        val output = ByteArrayOutputStream()
        val buffer = ByteArray(8192)
        while (true) {
            val read = input.read(buffer)
            if (read == -1) {
                break
            }
            if (output.size().toLong() + read > MAX_ARTWORK_BYTES) {
                return null
            }
            output.write(buffer, 0, read)
        }
        return output.toByteArray()
    }

    private fun decodeArtwork(bytes: ByteArray): Bitmap? {
        val bounds = BitmapFactory.Options().apply {
            inJustDecodeBounds = true
        }
        BitmapFactory.decodeByteArray(bytes, 0, bytes.size, bounds)
        if (bounds.outWidth <= 0 || bounds.outHeight <= 0) {
            return null
        }

        val options = BitmapFactory.Options().apply {
            inSampleSize = calculateInSampleSize(bounds, MAX_ARTWORK_DIMENSION)
        }
        return BitmapFactory.decodeByteArray(bytes, 0, bytes.size, options)
    }

    private fun calculateInSampleSize(
        bounds: BitmapFactory.Options,
        targetSize: Int,
    ): Int {
        var sampleSize = 1
        var width = bounds.outWidth
        var height = bounds.outHeight
        while (width / 2 >= targetSize || height / 2 >= targetSize) {
            sampleSize *= 2
            width /= 2
            height /= 2
        }
        return sampleSize
    }

    private fun dispatchAction(action: String) {
        val update = currentUpdate
        if (
            released ||
            update == null ||
            !isActionEnabled(action, update) ||
            isDuplicateAction(action)
        ) {
            return
        }
        val expectedPlaying = when (action) {
            ACTION_PLAY -> true
            ACTION_PAUSE -> false
            else -> null
        }
        if (expectedPlaying != null) {
            pendingPlaybackAction = PendingPlaybackAction(
                action = action,
                expectedPlaying = expectedPlaying,
            )
            refreshMediaSession()
            publishNotification()
            schedulePendingPlaybackActionTimeout(
                action = action,
                timeoutMs = ACTION_ACK_TIMEOUT_MS,
            )
        }
        actionForEvent(action)?.let(onAction)
    }

    private fun isActionEnabled(
        action: String,
        update: SystemMediaUpdate,
    ): Boolean {
        val slotPlan = SystemMediaControlSlotPlanner.create(
            canSkipPrevious = update.canSkipPrevious,
            canSkipNext = update.canSkipNext,
        )
        return when (action) {
            ACTION_PREVIOUS -> slotPlan.previousActionEnabled
            ACTION_NEXT -> slotPlan.nextActionEnabled
            else -> true
        }
    }

    private fun isDuplicateAction(action: String): Boolean {
        val now = SystemClock.elapsedRealtime()
        if (action == lastAction && now - lastActionAtMs < ACTION_DEBOUNCE_MS) {
            return true
        }
        lastAction = action
        lastActionAtMs = now
        return false
    }

    private fun toggleAction(): String {
        val update = currentUpdate
        return if (
            update?.status == STATUS_PLAYING ||
            update?.status == STATUS_LOADING ||
            update?.isLoading == true
        ) {
            ACTION_PAUSE
        } else {
            ACTION_PLAY
        }
    }

    private fun schedulePendingPlaybackActionTimeout(
        action: String,
        timeoutMs: Long,
    ) {
        pendingActionTimeout?.let(mainHandler::removeCallbacks)
        val timeout = Runnable {
            val pendingAction = pendingPlaybackAction
            if (!released && pendingAction?.action == action) {
                clearPendingPlaybackAction()
                refreshMediaSession()
                publishNotification()
            }
        }
        pendingActionTimeout = timeout
        mainHandler.postDelayed(timeout, timeoutMs)
    }

    private fun clearPendingPlaybackAction() {
        pendingPlaybackAction = null
        pendingActionTimeout?.let(mainHandler::removeCallbacks)
        pendingActionTimeout = null
    }

    private fun notificationDesktopLyricsStatusLabel(isEnabled: Boolean): String {
        return if (isEnabled) {
            "\u684c\u9762\u6b4c\u8bcd\u5df2\u5f00\u542f"
        } else {
            "\u684c\u9762\u6b4c\u8bcd\u5df2\u5173\u95ed"
        }
    }

    companion object {
        internal const val ACTION_CYCLE_PLAYBACK_MODE =
            "com.harmonymusic.player.system_media.CYCLE_PLAYBACK_MODE"
        internal const val ACTION_PREVIOUS = "com.harmonymusic.player.system_media.PREVIOUS"
        internal const val ACTION_PLAY = "com.harmonymusic.player.system_media.PLAY"
        internal const val ACTION_PAUSE = "com.harmonymusic.player.system_media.PAUSE"
        internal const val ACTION_NEXT = "com.harmonymusic.player.system_media.NEXT"
        internal const val ACTION_TOGGLE_DESKTOP_LYRICS =
            "com.harmonymusic.player.system_media.TOGGLE_DESKTOP_LYRICS"

        private const val MEDIA_SESSION_TAG = "HarmonyMusicSystemMedia"
        private const val NOTIFICATION_CHANNEL_ID = "system_media_playback"
        private const val NOTIFICATION_ID = 24020
        private const val REQUEST_CONTENT = 1
        private const val REQUEST_MEDIA_BUTTON = 2
        private const val REQUEST_PREVIOUS = 3
        private const val REQUEST_PLAY = 4
        private const val REQUEST_PAUSE = 5
        private const val REQUEST_NEXT = 6
        private const val REQUEST_CYCLE_PLAYBACK_MODE = 7
        private const val STATUS_PLAYING = "playing"
        private const val STATUS_LOADING = "loading"
        private const val STATUS_STOPPED = "stopped"
        private const val STATUS_COMPLETED = "completed"
        private const val STATUS_ERROR = "error"
        private const val PLAYBACK_MODE_REPEAT_ALL = "repeatAll"
        private const val PLAYBACK_MODE_REPEAT_ONE = "repeatOne"
        private const val PLAYBACK_MODE_SHUFFLE = "shuffle"
        private const val ARTWORK_TIMEOUT_MS = 8_000
        private const val MAX_ARTWORK_BYTES = 8L * 1024L * 1024L
        private const val MAX_ARTWORK_DIMENSION = 1024
        private const val ACTION_DEBOUNCE_MS = 500L
        private const val ACTION_ACK_TIMEOUT_MS = 1_200L
        private const val ACTION_STATE_SYNC_TIMEOUT_MS = 2_500L

        @Volatile
        private var activeManager: SystemMediaSessionManager? = null

        internal fun dispatchFromReceiver(action: String) {
            activeManager?.dispatchAction(action)
        }

        internal fun actionForEvent(action: String): String? {
            return when (action) {
                ACTION_CYCLE_PLAYBACK_MODE -> "playbackMode"
                ACTION_PREVIOUS -> "previous"
                ACTION_PLAY -> "play"
                ACTION_PAUSE -> "pause"
                ACTION_NEXT -> "next"
                else -> null
            }
        }

        internal fun actionFromEvent(action: String): String? {
            return when (action) {
                "playbackMode" -> ACTION_CYCLE_PLAYBACK_MODE
                "previous" -> ACTION_PREVIOUS
                "play" -> ACTION_PLAY
                "pause" -> ACTION_PAUSE
                "next" -> ACTION_NEXT
                else -> null
            }
        }

        internal fun playbackModeIcon(playbackMode: String): Int {
            return playbackModeActionPresentation(playbackMode).iconResource
        }

        internal fun customActionPresentation(
            action: String,
            update: SystemMediaUpdate,
        ): SystemMediaActionPresentation {
            return when (action) {
                ACTION_CYCLE_PLAYBACK_MODE -> playbackModeActionPresentation(update.playbackMode)
                else -> error("Unsupported system media custom action: $action")
            }
        }

        internal fun playbackModeActionPresentation(
            playbackMode: String,
        ): SystemMediaActionPresentation {
            return when (playbackMode) {
                PLAYBACK_MODE_REPEAT_ALL -> SystemMediaActionPresentation(
                    label = "\u5217\u8868\u5faa\u73af",
                    iconResource = R.drawable.ic_system_media_repeat_rounded,
                )
                PLAYBACK_MODE_REPEAT_ONE -> SystemMediaActionPresentation(
                    label = "\u5355\u66f2\u5faa\u73af",
                    iconResource = R.drawable.ic_system_media_repeat_one_rounded,
                )
                PLAYBACK_MODE_SHUFFLE -> SystemMediaActionPresentation(
                    label = "\u968f\u673a\u64ad\u653e",
                    iconResource = R.drawable.ic_system_media_shuffle_rounded,
                )
                else -> SystemMediaActionPresentation(
                    label = "\u987a\u5e8f\u64ad\u653e",
                    iconResource = R.drawable.ic_system_media_repeat_rounded,
                )
            }
        }


        internal fun actionForMediaButton(intent: Intent): String? {
            @Suppress("DEPRECATION")
            val keyEvent = intent.getParcelableExtra<KeyEvent>(Intent.EXTRA_KEY_EVENT)
                ?: return null
            if (keyEvent.action != KeyEvent.ACTION_DOWN) {
                return null
            }
            return when (keyEvent.keyCode) {
                KeyEvent.KEYCODE_MEDIA_PREVIOUS -> ACTION_PREVIOUS
                KeyEvent.KEYCODE_MEDIA_NEXT -> ACTION_NEXT
                KeyEvent.KEYCODE_MEDIA_PLAY -> ACTION_PLAY
                KeyEvent.KEYCODE_MEDIA_PAUSE -> ACTION_PAUSE
                KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE,
                KeyEvent.KEYCODE_HEADSETHOOK -> activeManager?.toggleAction()
                else -> null
            }
        }
    }
}
