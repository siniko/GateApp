package com.example.gatecontrol

import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Color
import android.graphics.PixelFormat
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.provider.Settings
import android.telephony.SmsManager
import android.view.Gravity
import android.view.LayoutInflater
import android.view.MotionEvent
import android.view.View
import android.view.WindowManager
import android.widget.Button
import android.widget.LinearLayout
import android.widget.TextView
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import kotlin.math.abs

class EdgeSwipeService : Service() {

    private lateinit var windowManager: WindowManager
    private var edgeView: View? = null
    private var panelView: View? = null
    private val handler = Handler(Looper.getMainLooper())

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
        startForeground(NOTIFICATION_ID, buildNotification())

        windowManager = getSystemService(WINDOW_SERVICE) as WindowManager

        if (Settings.canDrawOverlays(this)) {
            showEdgeHandle()
        } else {
            stopSelf()
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (!GatePreferences.isEdgeEnabled(this)) {
            stopSelf()
            return START_NOT_STICKY
        }

        if (edgeView == null && Settings.canDrawOverlays(this)) {
            showEdgeHandle()
        }

        return START_STICKY
    }

    override fun onDestroy() {
        hidePanel()
        edgeView?.let { safeRemove(it) }
        edgeView = null
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    private fun showEdgeHandle() {
        if (edgeView != null) return

        var startX = 0f
        var startY = 0f

        val view = View(this).apply {
            setBackgroundColor(Color.argb(10, 255, 255, 255))
            setOnTouchListener { _, event ->
                when (event.actionMasked) {
                    MotionEvent.ACTION_DOWN -> {
                        startX = event.rawX
                        startY = event.rawY
                        true
                    }
                    MotionEvent.ACTION_UP -> {
                        val dx = event.rawX - startX
                        val dy = event.rawY - startY

                        // Right-edge swipe toward the centre.
                        if (dx < -dp(70).toFloat() && abs(dy) < dp(130)) {
                            showControlPanel()
                        }
                        true
                    }
                    else -> true
                }
            }
        }

        val params = WindowManager.LayoutParams(
            dp(18),
            dp(240),
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL or
                WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN,
            PixelFormat.TRANSLUCENT
        ).apply {
            gravity = Gravity.END or Gravity.CENTER_VERTICAL
        }

        runCatching {
            windowManager.addView(view, params)
            edgeView = view
        }.onFailure {
            stopSelf()
        }
    }

    private fun showControlPanel() {
        if (panelView != null) return

        val view = LayoutInflater.from(this).inflate(R.layout.edge_control_panel, null)

        val titleText = view.findViewById<TextView>(R.id.panelTitle)
        val subtitleText = view.findViewById<TextView>(R.id.panelSubtitle)
        val actionsGroup = view.findViewById<LinearLayout>(R.id.actionsGroup)
        val confirmGroup = view.findViewById<LinearLayout>(R.id.confirmGroup)
        val confirmMessage = view.findViewById<TextView>(R.id.confirmMessage)
        val statusText = view.findViewById<TextView>(R.id.panelStatus)
        val openButton = view.findViewById<Button>(R.id.panelOpenButton)
        val closeButton = view.findViewById<Button>(R.id.panelCloseButton)
        val confirmButton = view.findViewById<Button>(R.id.panelConfirmButton)
        val cancelButton = view.findViewById<Button>(R.id.panelCancelButton)
        val dismissButton = view.findViewById<TextView>(R.id.panelDismissButton)

        var pendingCommand = ""
        var pendingConfirmation = ""

        fun resetPanel() {
            titleText.text = "HOME GATE"
            subtitleText.text = "Choose an action"
            actionsGroup.visibility = View.VISIBLE
            confirmGroup.visibility = View.GONE
            statusText.visibility = View.GONE
            pendingCommand = ""
            pendingConfirmation = ""
        }

        fun askConfirmation(action: String, command: String, sentMessage: String) {
            pendingCommand = command
            pendingConfirmation = sentMessage
            actionsGroup.visibility = View.GONE
            confirmGroup.visibility = View.VISIBLE
            statusText.visibility = View.GONE
            titleText.text = "Are you sure?"
            subtitleText.text = ""
            confirmMessage.text = if (action == "OPEN") {
                "Open the home gate?"
            } else {
                "Close the home gate?"
            }
        }

        openButton.setOnClickListener {
            askConfirmation("OPEN", GatePreferences.getOpenCommand(this), "Open command sent")
        }

        closeButton.setOnClickListener {
            askConfirmation("CLOSE", GatePreferences.getCloseCommand(this), "Close command sent")
        }

        cancelButton.setOnClickListener { resetPanel() }

        dismissButton.setOnClickListener { hidePanel() }

        confirmButton.setOnClickListener {
            val result = sendGateSms(pendingCommand)
            confirmGroup.visibility = View.GONE
            actionsGroup.visibility = View.GONE
            statusText.visibility = View.VISIBLE

            if (result == null) {
                titleText.text = "Sent ✓"
                subtitleText.text = pendingConfirmation
                statusText.text = "SMS sent successfully"
                handler.postDelayed({ hidePanel() }, 1400)
            } else {
                titleText.text = "Could not send"
                subtitleText.text = ""
                statusText.text = result
                handler.postDelayed({ resetPanel() }, 2200)
            }
        }

        resetPanel()

        val params = WindowManager.LayoutParams(
            dp(330),
            WindowManager.LayoutParams.WRAP_CONTENT,
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL or
                WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN,
            PixelFormat.TRANSLUCENT
        ).apply {
            gravity = Gravity.END or Gravity.CENTER_VERTICAL
            x = dp(12)
        }

        runCatching {
            windowManager.addView(view, params)
            panelView = view
        }
    }

    private fun hidePanel() {
        handler.removeCallbacksAndMessages(null)
        panelView?.let { safeRemove(it) }
        panelView = null
    }

    /**
     * @return null on success, otherwise a user-facing error message.
     */
    private fun sendGateSms(command: String): String? {
        if (ContextCompat.checkSelfPermission(
                this,
                Manifest.permission.SEND_SMS
            ) != PackageManager.PERMISSION_GRANTED
        ) {
            return "Open Gate Control and allow SMS permission."
        }

        if (
            GatePreferences.usesContact(this) &&
            ContextCompat.checkSelfPermission(
                this,
                Manifest.permission.READ_CONTACTS
            ) != PackageManager.PERMISSION_GRANTED
        ) {
            return "Open Gate Control and allow Contacts permission."
        }

        val number = try {
            GateContactResolver.resolvePhoneNumber(this)
        } catch (_: SecurityException) {
            null
        }

        if (number.isNullOrBlank()) {
            return "Gate phone number could not be found."
        }

        if (command.isBlank()) {
            return "Gate command is empty."
        }

        return try {
            val smsManager = getSystemService(SmsManager::class.java)
            smsManager.sendTextMessage(number, null, command, null, null)
            GatePreferences.setPhoneNumber(this, number)
            null
        } catch (e: Exception) {
            "SMS failed: ${e.message ?: "Unknown error"}"
        }
    }

    private fun safeRemove(view: View) {
        runCatching { windowManager.removeView(view) }
    }

    private fun dp(value: Int): Int =
        (value * resources.displayMetrics.density).toInt()

    private fun createNotificationChannel() {
        val manager = getSystemService(NotificationManager::class.java)
        val channel = NotificationChannel(
            CHANNEL_ID,
            "Gate edge control",
            NotificationManager.IMPORTANCE_LOW
        ).apply {
            description = "Keeps the edge-swipe gate control available"
            setShowBadge(false)
        }
        manager.createNotificationChannel(channel)
    }

    private fun buildNotification() = NotificationCompat.Builder(this, CHANNEL_ID)
        .setSmallIcon(R.drawable.ic_gate_notification)
        .setContentTitle("Gate Control")
        .setContentText("Edge swipe control is active")
        .setOngoing(true)
        .setPriority(NotificationCompat.PRIORITY_LOW)
        .setContentIntent(
            PendingIntent.getActivity(
                this,
                0,
                Intent(this, MainActivity::class.java),
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
        )
        .build()

    companion object {
        private const val CHANNEL_ID = "gate_edge_control"
        private const val NOTIFICATION_ID = 2011
    }
}
