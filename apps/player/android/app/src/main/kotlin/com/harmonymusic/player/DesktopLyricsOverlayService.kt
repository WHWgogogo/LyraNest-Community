package com.harmonymusic.player

import com.lyranest.community.player.R

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.pm.ServiceInfo
import android.graphics.Color
import android.graphics.PixelFormat
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.os.Build
import android.os.IBinder
import android.provider.Settings
import android.text.Layout
import android.text.SpannableString
import android.text.Spanned
import android.text.TextUtils
import android.text.style.AlignmentSpan
import android.util.TypedValue
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.WindowInsets
import android.view.WindowManager
import android.widget.TextView
import kotlin.math.ceil

internal object DesktopLyricsOverlayWidthCalculator {
    fun calculate(
        text: String,
        measureLine: (String) -> Float,
        horizontalPadding: Int,
        minimumWidth: Int,
        maximumWidth: Int,
    ): Int {
        val safeMaximumWidth = maximumWidth.coerceAtLeast(0)
        val safeMinimumWidth = minimumWidth.coerceIn(0, safeMaximumWidth)
        val widestLine = text
            .split('\n')
            .maxOfOrNull { line ->
                measureLine(line)
                    .takeIf { width -> width.isFinite() && width > 0f }
                    ?: 0f
            }
            ?: 0f
        val desiredWidth =
            ceil(widestLine.toDouble()).toInt() + horizontalPadding.coerceAtLeast(0)
        return desiredWidth.coerceIn(safeMinimumWidth, safeMaximumWidth)
    }
}

class DesktopLyricsOverlayService : Service() {
    private lateinit var windowManager: WindowManager
    private var overlayView: View? = null
    private var overlayTextView: TextView? = null
    private var dragStartX = 0
    private var dragStartY = 0
    private var dragTouchStartX = 0f
    private var dragTouchStartY = 0f

    private data class OverlayConfiguration(
        val backgroundOpacity: Float,
        val textColor: Int,
        val fontSize: Float,
        val textAlignment: String,
    )

    private data class OverlayPosition(
        val x: Int,
        val y: Int,
    )

    override fun onCreate() {
        super.onCreate()
        serviceInstance = this
        windowManager = getSystemService(WINDOW_SERVICE) as WindowManager
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_SHOW -> {
                if (ensureForeground()) {
                    showOverlay(intent.getStringExtra(EXTRA_TEXT).orEmpty())
                }
            }
            ACTION_UPDATE -> {
                val text = intent.getStringExtra(EXTRA_TEXT).orEmpty()
                if (overlayVisible) {
                    if (ensureForeground()) {
                        updateOverlayText(text)
                    }
                } else {
                    latestText = text
                    setOverlayState(STATUS_HIDDEN, "Overlay is hidden; lyrics text was stored.")
                    stopSelf(startId)
                }
            }
            ACTION_HIDE -> {
                hideOverlay()
                stopForegroundCompat()
                stopSelf(startId)
            }
            ACTION_DISPOSE -> {
                disposeSelf(startId)
            }
        }
        return START_NOT_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? {
        return null
    }

    override fun onTaskRemoved(rootIntent: Intent?) {
        disposeSelf()
        super.onTaskRemoved(rootIntent)
    }

    override fun onDestroy() {
        hideOverlay()
        stopForegroundCompat()
        serviceInstance = null
        super.onDestroy()
    }

    private fun ensureForeground(): Boolean {
        return try {
            val notification = buildNotification()
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                startForeground(
                    NOTIFICATION_ID,
                    notification,
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE,
                )
            } else {
                startForeground(NOTIFICATION_ID, notification)
            }
            true
        } catch (exception: RuntimeException) {
            setOverlayState(
                STATUS_ERROR,
                exception.localizedMessage ?: exception.javaClass.simpleName,
            )
            stopSelf()
            false
        }
    }

    private fun showOverlay(text: String) {
        if (!canDrawOverlays(this)) {
            setOverlayState(
                STATUS_PERMISSION_DENIED,
                "Display over other apps permission is required before showing lyrics.",
            )
            stopForegroundCompat()
            stopSelf()
            return
        }

        latestText = text
        val configuration = overlayConfiguration(this)
        if (overlayView == null) {
            overlayTextView = createLyricsTextView(configuration)
            overlayView = overlayTextView
        }

        val lyricsView = overlayView ?: return
        val textView = overlayTextView ?: return
        textView.text = displayedText(text, configuration.textAlignment)
        val layoutParams = createLayoutParams(targetOverlayWidth(textView, text))

        try {
            if (lyricsView.parent == null) {
                windowManager.addView(lyricsView, layoutParams)
            } else {
                windowManager.updateViewLayout(lyricsView, layoutParams)
            }
            overlayVisible = true
            setOverlayState(STATUS_VISIBLE, "Desktop lyrics overlay is visible.")
        } catch (exception: RuntimeException) {
            overlayVisible = false
            setOverlayState(
                STATUS_ERROR,
                exception.localizedMessage ?: exception.javaClass.simpleName,
            )
            stopForegroundCompat()
            stopSelf()
        }
    }

    private fun updateOverlayText(text: String) {
        latestText = text
        overlayTextView?.text = displayedText(
            text,
            overlayConfiguration(this).textAlignment,
        )
        refreshOverlayLayout()
        setOverlayState(STATUS_UPDATED, "Desktop lyrics overlay text was updated.")
    }

    private fun hideOverlay() {
        val lyricsView = overlayView
        if (lyricsView?.parent != null) {
            try {
                windowManager.removeView(lyricsView)
            } catch (exception: RuntimeException) {
                setOverlayState(
                    STATUS_ERROR,
                    exception.localizedMessage ?: exception.javaClass.simpleName,
                )
            }
        }
        overlayView = null
        overlayTextView = null
        overlayVisible = false
        setOverlayState(STATUS_HIDDEN, "Desktop lyrics overlay is hidden.")
    }

    private fun disposeSelf(startId: Int? = null) {
        hideOverlay()
        stopForegroundCompat()
        setOverlayState(STATUS_DISPOSED, "Desktop lyrics overlay service was disposed.")
        if (startId == null) {
            stopSelf()
        } else {
            stopSelf(startId)
        }
    }

    private fun createLyricsTextView(configuration: OverlayConfiguration): TextView {
        val textView = TextView(this)
        textView.typeface = Typeface.DEFAULT_BOLD
        textView.maxLines = MAX_WRAPPED_LINES
        textView.ellipsize = TextUtils.TruncateAt.END
        textView.setHorizontallyScrolling(false)
        textView.includeFontPadding = false
        textView.setLineSpacing(0f, 1.25f)
        textView.setPadding(dp(20), dp(12), dp(20), dp(12))
        textView.maxWidth = maxOverlayWidth()
        applyTextAppearance(textView, configuration)
        textView.setOnTouchListener { view, motionEvent ->
            handleDrag(view, motionEvent)
        }
        return textView
    }

    private fun applyConfiguration(
        configuration: OverlayConfiguration,
        resetPosition: Boolean,
    ): Boolean {
        overlayTextView?.let { textView ->
            applyTextAppearance(textView, configuration)
            textView.text = displayedText(latestText, configuration.textAlignment)
            textView.requestLayout()
            textView.invalidate()
        }
        if (!refreshOverlayLayout()) {
            return false
        }
        return !resetPosition || resetOverlayPosition()
    }

    private fun refreshOverlayLayout(): Boolean {
        val lyricsView = overlayView ?: return true
        val layoutParams = lyricsView.layoutParams as? WindowManager.LayoutParams ?: return true
        overlayTextView?.let { textView ->
            layoutParams.width = targetOverlayWidth(textView, latestText)
        }
        if (lyricsView.parent == null) {
            return true
        }
        try {
            lyricsView.requestLayout()
            windowManager.updateViewLayout(lyricsView, layoutParams)
            return true
        } catch (exception: RuntimeException) {
            setOverlayState(
                STATUS_ERROR,
                exception.localizedMessage ?: exception.javaClass.simpleName,
            )
            return false
        }
    }

    private fun applyTextAppearance(
        textView: TextView,
        configuration: OverlayConfiguration,
    ) {
        textView.setTextColor(configuration.textColor)
        textView.setTextSize(TypedValue.COMPLEX_UNIT_SP, configuration.fontSize)
        textView.gravity = when (configuration.textAlignment) {
            TEXT_ALIGNMENT_LEFT,
            TEXT_ALIGNMENT_SPLIT
            -> Gravity.LEFT or Gravity.CENTER_VERTICAL
            TEXT_ALIGNMENT_RIGHT -> Gravity.RIGHT or Gravity.CENTER_VERTICAL
            else -> Gravity.CENTER_HORIZONTAL or Gravity.CENTER_VERTICAL
        }
        textView.textAlignment = View.TEXT_ALIGNMENT_GRAVITY
        textView.background = GradientDrawable().apply {
            val alpha = (configuration.backgroundOpacity * 255).toInt()
                .coerceIn(0, 255)
            setColor(Color.argb(alpha, 0, 0, 0))
            cornerRadius = dp(24).toFloat()
        }
        textView.elevation = if (configuration.backgroundOpacity == 0f) {
            0f
        } else {
            dp(8).toFloat()
        }
    }

    private fun createLayoutParams(width: Int): WindowManager.LayoutParams {
        val preferences = getSharedPreferences(PREFS_NAME, MODE_PRIVATE)
        val defaultPosition = safeDefaultPosition()
        val overlayType = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        } else {
            WindowManager.LayoutParams.TYPE_PHONE
        }

        return WindowManager.LayoutParams(
            width,
            WindowManager.LayoutParams.WRAP_CONTENT,
            overlayType,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE,
            PixelFormat.TRANSLUCENT,
        ).apply {
            gravity = Gravity.TOP or Gravity.START
            x = preferences.getInt(PREF_X, defaultPosition.x)
            y = preferences.getInt(PREF_Y, defaultPosition.y)
        }
    }

    private fun resetOverlayPosition(): Boolean {
        val lyricsView = overlayView ?: return true
        val layoutParams = lyricsView.layoutParams as? WindowManager.LayoutParams ?: return true
        val defaultPosition = safeDefaultPosition()
        layoutParams.x = defaultPosition.x
        layoutParams.y = defaultPosition.y
        if (lyricsView.parent == null) {
            return true
        }
        return try {
            windowManager.updateViewLayout(lyricsView, layoutParams)
            true
        } catch (exception: RuntimeException) {
            setOverlayState(
                STATUS_ERROR,
                exception.localizedMessage ?: exception.javaClass.simpleName,
            )
            false
        }
    }

    private fun safeDefaultPosition(): OverlayPosition {
        val topInset = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            windowManager.currentWindowMetrics.windowInsets
                .getInsetsIgnoringVisibility(WindowInsets.Type.statusBars())
                .top
        } else {
            statusBarHeight()
        }
        return OverlayPosition(
            x = dp(24),
            y = (topInset + dp(24)).coerceAtLeast(dp(72)),
        )
    }

    private fun statusBarHeight(): Int {
        val resourceId = resources.getIdentifier("status_bar_height", "dimen", "android")
        return if (resourceId == 0) {
            0
        } else {
            resources.getDimensionPixelSize(resourceId)
        }
    }

    private fun handleDrag(view: View, motionEvent: MotionEvent): Boolean {
        val layoutParams = view.layoutParams as? WindowManager.LayoutParams ?: return true

        when (motionEvent.actionMasked) {
            MotionEvent.ACTION_DOWN -> {
                dragStartX = layoutParams.x
                dragStartY = layoutParams.y
                dragTouchStartX = motionEvent.rawX
                dragTouchStartY = motionEvent.rawY
                return true
            }
            MotionEvent.ACTION_MOVE -> {
                layoutParams.x = dragStartX + (motionEvent.rawX - dragTouchStartX).toInt()
                layoutParams.y = dragStartY + (motionEvent.rawY - dragTouchStartY).toInt()
                try {
                    windowManager.updateViewLayout(view, layoutParams)
                } catch (exception: RuntimeException) {
                    setOverlayState(
                        STATUS_ERROR,
                        exception.localizedMessage ?: exception.javaClass.simpleName,
                    )
                }
                return true
            }
            MotionEvent.ACTION_UP,
            MotionEvent.ACTION_CANCEL -> {
                savePosition(layoutParams.x, layoutParams.y)
                view.performClick()
                return true
            }
        }

        return true
    }

    private fun savePosition(positionX: Int, positionY: Int) {
        getSharedPreferences(PREFS_NAME, MODE_PRIVATE)
            .edit()
            .putInt(PREF_X, positionX)
            .putInt(PREF_Y, positionY)
            .apply()
    }

    private fun buildNotification(): Notification {
        val launchIntent = packageManager.getLaunchIntentForPackage(packageName)
        val pendingIntentFlags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        } else {
            PendingIntent.FLAG_UPDATE_CURRENT
        }
        val pendingIntent = launchIntent?.let {
            PendingIntent.getActivity(this, 0, it, pendingIntentFlags)
        }
        val disposeIntent = Intent(this, DesktopLyricsOverlayService::class.java).apply {
            action = ACTION_DISPOSE
        }
        val disposePendingIntent = PendingIntent.getService(
            this,
            1,
            disposeIntent,
            pendingIntentFlags,
        )

        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, NOTIFICATION_CHANNEL_ID)
        } else {
            Notification.Builder(this)
        }

        return builder
            .setSmallIcon(R.drawable.ic_desktop_lyrics_notification)
            .setContentTitle(getString(R.string.desktop_lyrics_notification_title))
            .setContentText(getString(R.string.desktop_lyrics_notification_text))
            .setOngoing(true)
            .setShowWhen(false)
            .setCategory(Notification.CATEGORY_SERVICE)
            .setContentIntent(pendingIntent)
            .addAction(
                R.drawable.ic_desktop_lyrics_notification,
                getString(R.string.desktop_lyrics_notification_stop),
                disposePendingIntent,
            )
            .build()
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            return
        }

        val channel = NotificationChannel(
            NOTIFICATION_CHANNEL_ID,
            getString(R.string.desktop_lyrics_notification_channel_name),
            NotificationManager.IMPORTANCE_LOW,
        ).apply {
            description = getString(R.string.desktop_lyrics_notification_channel_description)
            setShowBadge(false)
        }
        val notificationManager = getSystemService(NotificationManager::class.java)
        notificationManager.createNotificationChannel(channel)
    }

    private fun stopForegroundCompat() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            stopForeground(STOP_FOREGROUND_REMOVE)
        } else {
            @Suppress("DEPRECATION")
            stopForeground(true)
        }
    }

    private fun maxOverlayWidth(): Int {
        val displayWidth = resources.displayMetrics.widthPixels
        return (displayWidth - dp(SCREEN_MARGIN_DP) * 2)
            .coerceAtLeast(1)
            .coerceAtMost(dp(MAX_OVERLAY_WIDTH_DP))
    }

    private fun minOverlayWidth(): Int {
        return dp(MIN_OVERLAY_WIDTH_DP).coerceAtMost(maxOverlayWidth())
    }

    private fun targetOverlayWidth(textView: TextView, text: String): Int {
        val maximumWidth = maxOverlayWidth()
        textView.maxWidth = maximumWidth
        return DesktopLyricsOverlayWidthCalculator.calculate(
            text = visibleText(text),
            measureLine = textView.paint::measureText,
            horizontalPadding = textView.paddingLeft + textView.paddingRight,
            minimumWidth = minOverlayWidth(),
            maximumWidth = maximumWidth,
        )
    }

    private fun dp(value: Int): Int {
        return (value * resources.displayMetrics.density + 0.5f).toInt()
    }

    private fun visibleText(text: String): String {
        return text.ifBlank { "♪" }
    }

    private fun displayedText(text: String, textAlignment: String): CharSequence {
        val visibleText = visibleText(text)
        if (textAlignment != TEXT_ALIGNMENT_SPLIT) {
            return visibleText
        }

        val splitText = SpannableString(visibleText)
        val firstLineEnd = visibleText.indexOf('\n').let { lineBreak ->
            if (lineBreak == -1) visibleText.length else lineBreak
        }
        val firstSpanEnd = if (firstLineEnd == visibleText.length) {
            firstLineEnd
        } else {
            firstLineEnd + 1
        }
        splitText.setSpan(
            AlignmentSpan.Standard(Layout.Alignment.ALIGN_NORMAL),
            0,
            firstSpanEnd,
            Spanned.SPAN_EXCLUSIVE_EXCLUSIVE,
        )

        if (firstLineEnd < visibleText.length) {
            val secondLineStart = firstLineEnd + 1
            val secondLineEnd = visibleText.indexOf('\n', secondLineStart).let { lineBreak ->
                if (lineBreak == -1) visibleText.length else lineBreak
            }
            if (secondLineStart < secondLineEnd) {
                val secondSpanEnd = if (secondLineEnd == visibleText.length) {
                    secondLineEnd
                } else {
                    secondLineEnd + 1
                }
                splitText.setSpan(
                    AlignmentSpan.Standard(Layout.Alignment.ALIGN_OPPOSITE),
                    secondLineStart,
                    secondSpanEnd,
                    Spanned.SPAN_EXCLUSIVE_EXCLUSIVE,
                )
            }
        }

        return splitText
    }

    companion object {
        private const val ACTION_SHOW = "com.harmonymusic.player.desktop_lyrics.SHOW"
        private const val ACTION_UPDATE = "com.harmonymusic.player.desktop_lyrics.UPDATE"
        private const val ACTION_HIDE = "com.harmonymusic.player.desktop_lyrics.HIDE"
        private const val ACTION_DISPOSE = "com.harmonymusic.player.desktop_lyrics.DISPOSE"
        private const val EXTRA_TEXT = "text"
        private const val NOTIFICATION_CHANNEL_ID = "desktop_lyrics_overlay"
        private const val NOTIFICATION_ID = 24018
        private const val PREFS_NAME = "desktop_lyrics_overlay"
        private const val PREF_X = "x"
        private const val PREF_Y = "y"
        private const val PREF_BACKGROUND_OPACITY = "background_opacity"
        private const val PREF_TEXT_COLOR = "text_color"
        private const val PREF_FONT_SIZE = "font_size"
        private const val PREF_TEXT_ALIGNMENT = "text_alignment"
        private const val FLUTTER_PREFERENCES_NAME = "FlutterSharedPreferences"
        private const val FLUTTER_DESKTOP_LYRICS_FONT_SIZE_KEY =
            "flutter.player_preferences.desktop_lyrics_font_size.v1"
        private const val FLUTTER_LEGACY_LYRICS_FONT_SIZE_KEY =
            "flutter.player_preferences.lyrics_font_size.v1"
        private const val DEFAULT_BACKGROUND_OPACITY = 0.6f
        private const val DEFAULT_FONT_SIZE = 22f
        private const val MIN_FONT_SIZE = 14f
        private const val MAX_FONT_SIZE = 36f
        private const val MIN_OVERLAY_WIDTH_DP = 160
        private const val MAX_OVERLAY_WIDTH_DP = 720
        private const val SCREEN_MARGIN_DP = 16
        private const val MAX_WRAPPED_LINES = 4
        private const val TEXT_ALIGNMENT_LEFT = "left"
        private const val TEXT_ALIGNMENT_CENTER = "center"
        private const val TEXT_ALIGNMENT_RIGHT = "right"
        private const val TEXT_ALIGNMENT_SPLIT = "split"
        private const val STATUS_UNSUPPORTED = "unsupported"
        private const val STATUS_PERMISSION_GRANTED = "permissionGranted"
        private const val STATUS_PERMISSION_DENIED = "permissionDenied"
        private const val STATUS_PERMISSION_REQUEST_OPENED = "permissionRequestOpened"
        private const val STATUS_NOTIFICATION_PERMISSION_DENIED =
            "notificationPermissionDenied"
        private const val STATUS_SHOW_REQUESTED = "showRequested"
        private const val STATUS_VISIBLE = "visible"
        private const val STATUS_UPDATED = "updated"
        private const val STATUS_HIDDEN = "hidden"
        private const val STATUS_DISPOSED = "disposed"
        private const val STATUS_ERROR = "error"

        @Volatile
        private var serviceInstance: DesktopLyricsOverlayService? = null

        @Volatile
        private var overlayVisible = false

        @Volatile
        private var latestText = ""

        @Volatile
        private var lastState = STATUS_HIDDEN

        @Volatile
        private var lastMessage = "Desktop lyrics overlay is hidden."

        fun canDrawOverlays(context: Context): Boolean {
            return Build.VERSION.SDK_INT < Build.VERSION_CODES.M || Settings.canDrawOverlays(context)
        }

        fun canPostNotifications(context: Context): Boolean {
            return Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
                context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) ==
                PackageManager.PERMISSION_GRANTED
        }

        fun statusMap(
            context: Context,
            state: String? = null,
            message: String? = null,
        ): Map<String, Any> {
            val hasOverlayPermission = canDrawOverlays(context)
            val resolvedState = state ?: when {
                !hasOverlayPermission -> STATUS_PERMISSION_DENIED
                overlayVisible -> STATUS_VISIBLE
                else -> lastState
            }
            val resolvedMessage = message ?: when (resolvedState) {
                STATUS_PERMISSION_GRANTED -> "Overlay permission is granted."
                STATUS_PERMISSION_DENIED -> "Display over other apps permission is required."
                STATUS_PERMISSION_REQUEST_OPENED -> "Opened Android overlay permission settings."
                STATUS_NOTIFICATION_PERMISSION_DENIED ->
                    "Notification permission is required for a visible foreground notification."
                STATUS_SHOW_REQUESTED -> "Desktop lyrics overlay show was requested."
                STATUS_VISIBLE -> "Desktop lyrics overlay is visible."
                STATUS_UPDATED -> "Desktop lyrics overlay text was updated."
                STATUS_HIDDEN -> "Desktop lyrics overlay is hidden."
                STATUS_DISPOSED -> "Desktop lyrics overlay service was disposed."
                STATUS_UNSUPPORTED -> "Desktop lyrics overlay is unsupported on this device."
                STATUS_ERROR -> lastMessage
                else -> lastMessage
            }

            return mapOf(
                "platform" to "android",
                "state" to resolvedState,
                "canDrawOverlays" to hasOverlayPermission,
                "canPostNotifications" to canPostNotifications(context),
                "isVisible" to overlayVisible,
                "message" to resolvedMessage,
            )
        }

        fun show(context: Context, text: String): Map<String, Any> {
            if (!canDrawOverlays(context)) {
                return statusMap(
                    context,
                    state = STATUS_PERMISSION_DENIED,
                    message = "Display over other apps permission is required before showing lyrics.",
                )
            }

            val service = serviceInstance
            if (service != null) {
                if (service.ensureForeground()) {
                    service.showOverlay(text)
                }
                return statusMap(context)
            }

            latestText = text
            val intent = Intent(context, DesktopLyricsOverlayService::class.java).apply {
                action = ACTION_SHOW
                putExtra(EXTRA_TEXT, text)
            }

            return try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    context.startForegroundService(intent)
                } else {
                    context.startService(intent)
                }
                setOverlayState(
                    STATUS_SHOW_REQUESTED,
                    "Desktop lyrics overlay show was requested.",
                )
                statusMap(
                    context,
                    state = STATUS_SHOW_REQUESTED,
                    message = "Desktop lyrics overlay show was requested.",
                )
            } catch (exception: RuntimeException) {
                setOverlayState(
                    STATUS_ERROR,
                    exception.localizedMessage ?: exception.javaClass.simpleName,
                )
                statusMap(context, state = STATUS_ERROR)
            }
        }

        fun update(context: Context, text: String): Map<String, Any> {
            latestText = text
            if (!canDrawOverlays(context)) {
                return statusMap(
                    context,
                    state = STATUS_PERMISSION_DENIED,
                    message = "Display over other apps permission is required before updating lyrics.",
                )
            }

            val service = serviceInstance
            return if (service != null && overlayVisible) {
                service.updateOverlayText(text)
                statusMap(context)
            } else {
                setOverlayState(STATUS_HIDDEN, "Overlay is hidden; lyrics text was stored.")
                statusMap(context, state = STATUS_HIDDEN)
            }
        }

        fun configure(
            context: Context,
            backgroundOpacity: Double?,
            textColor: Int?,
            textAlignment: String?,
            resetPosition: Boolean,
            fontSize: Double? = null,
        ): Map<String, Any> {
            val currentConfiguration = overlayConfiguration(context)
            val configuration = OverlayConfiguration(
                backgroundOpacity = backgroundOpacity
                    ?.takeIf { it.isFinite() }
                    ?.toFloat()
                    ?.coerceIn(0f, 1f)
                    ?: currentConfiguration.backgroundOpacity,
                textColor = textColor ?: currentConfiguration.textColor,
                fontSize = fontSize
                    ?.takeIf {
                        it.isFinite() &&
                            it >= MIN_FONT_SIZE.toDouble() &&
                            it <= MAX_FONT_SIZE.toDouble()
                    }
                    ?.toFloat()
                    ?: currentConfiguration.fontSize,
                textAlignment = textAlignment
                    ?.takeIf {
                        it == TEXT_ALIGNMENT_LEFT ||
                            it == TEXT_ALIGNMENT_CENTER ||
                            it == TEXT_ALIGNMENT_RIGHT ||
                            it == TEXT_ALIGNMENT_SPLIT
                    }
                    ?: currentConfiguration.textAlignment,
            )
            context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                .edit()
                .putFloat(PREF_BACKGROUND_OPACITY, configuration.backgroundOpacity)
                .putInt(PREF_TEXT_COLOR, configuration.textColor)
                .putFloat(PREF_FONT_SIZE, configuration.fontSize)
                .putString(PREF_TEXT_ALIGNMENT, configuration.textAlignment)
                .apply {
                    if (resetPosition) {
                        remove(PREF_X)
                        remove(PREF_Y)
                    }
                }
                .apply()
            val configurationApplied =
                serviceInstance?.applyConfiguration(configuration, resetPosition) ?: true
            if (!configurationApplied) {
                return statusMap(context, state = STATUS_ERROR)
            }
            setOverlayState(STATUS_UPDATED, "Desktop lyrics overlay configuration was updated.")
            return statusMap(
                context,
                state = STATUS_UPDATED,
                message = "Desktop lyrics overlay configuration was updated.",
            )
        }

        fun hide(context: Context): Map<String, Any> {
            serviceInstance?.let { service ->
                service.hideOverlay()
                service.stopForegroundCompat()
                service.stopSelf()
            }
            setOverlayState(STATUS_HIDDEN, "Desktop lyrics overlay is hidden.")
            return statusMap(context, state = STATUS_HIDDEN)
        }

        fun disposeOverlay(context: Context): Map<String, Any> {
            serviceInstance?.disposeSelf()
            overlayVisible = false
            setOverlayState(STATUS_DISPOSED, "Desktop lyrics overlay service was disposed.")
            return statusMap(context, state = STATUS_DISPOSED)
        }

        private fun overlayConfiguration(context: Context): OverlayConfiguration {
            val preferences = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            return OverlayConfiguration(
                backgroundOpacity = preferences.getFloat(
                    PREF_BACKGROUND_OPACITY,
                    DEFAULT_BACKGROUND_OPACITY,
                ).coerceIn(0f, 1f),
                textColor = preferences.getInt(PREF_TEXT_COLOR, Color.WHITE),
                fontSize = preferences.getFloat(
                    PREF_FONT_SIZE,
                    flutterDesktopLyricsFontSize(context),
                ).coerceIn(MIN_FONT_SIZE, MAX_FONT_SIZE),
                textAlignment = preferences.getString(
                    PREF_TEXT_ALIGNMENT,
                    TEXT_ALIGNMENT_CENTER,
                ).let { alignment ->
                    if (
                        alignment == TEXT_ALIGNMENT_LEFT ||
                            alignment == TEXT_ALIGNMENT_CENTER ||
                            alignment == TEXT_ALIGNMENT_RIGHT ||
                            alignment == TEXT_ALIGNMENT_SPLIT
                    ) {
                        alignment
                    } else {
                        TEXT_ALIGNMENT_CENTER
                    }
                },
            )
        }

        private fun flutterDesktopLyricsFontSize(context: Context): Float {
            val preferences = context
                .getSharedPreferences(FLUTTER_PREFERENCES_NAME, Context.MODE_PRIVATE)
            val value = preferences.all[FLUTTER_DESKTOP_LYRICS_FONT_SIZE_KEY] as? Number
                ?: preferences.all[FLUTTER_LEGACY_LYRICS_FONT_SIZE_KEY] as? Number
            return value
                ?.toFloat()
                ?.takeIf { it.isFinite() && it >= MIN_FONT_SIZE && it <= MAX_FONT_SIZE }
                ?: DEFAULT_FONT_SIZE
        }

        private fun setOverlayState(state: String, message: String) {
            lastState = state
            lastMessage = message
        }
    }
}
