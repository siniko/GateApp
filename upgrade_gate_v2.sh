#!/usr/bin/env bash
set -euo pipefail

ROOT="$(pwd)"
if [[ ! -f "$ROOT/settings.gradle.kts" || ! -d "$ROOT/app/src/main" ]]; then
  echo "Run this script from the GateControlApp project root."
  exit 1
fi

PKG_DIR="$ROOT/app/src/main/java/com/example/gatecontrol"
RES="$ROOT/app/src/main/res"

mkdir -p "$PKG_DIR" "$RES/layout" "$RES/drawable" "$RES/values"

cat > "$ROOT/app/src/main/AndroidManifest.xml" <<'EOF'
<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns:android="http://schemas.android.com/apk/res/android">

    <uses-permission android:name="android.permission.SEND_SMS" />
    <uses-permission android:name="android.permission.READ_CONTACTS" />
    <uses-permission android:name="android.permission.SYSTEM_ALERT_WINDOW" />
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE_SPECIAL_USE" />
    <uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED" />
    <uses-permission android:name="android.permission.POST_NOTIFICATIONS" />

    <application
        android:allowBackup="true"
        android:label="Gate Control"
        android:supportsRtl="true"
        android:theme="@style/Theme.GateControl">

        <activity
            android:name=".MainActivity"
            android:exported="true">
            <intent-filter>
                <action android:name="android.intent.action.MAIN" />
                <category android:name="android.intent.category.LAUNCHER" />
            </intent-filter>
        </activity>

        <receiver
            android:name=".GateWidgetProvider"
            android:exported="false">
            <intent-filter>
                <action android:name="android.appwidget.action.APPWIDGET_UPDATE" />
            </intent-filter>
            <meta-data
                android:name="android.appwidget.provider"
                android:resource="@xml/gate_widget_info" />
        </receiver>

        <service
            android:name=".EdgeSwipeService"
            android:exported="false"
            android:foregroundServiceType="specialUse">
            <property
                android:name="android.app.PROPERTY_SPECIAL_USE_FGS_SUBTYPE"
                android:value="User-enabled edge gesture for private home gate control" />
        </service>

        <receiver
            android:name=".BootReceiver"
            android:enabled="true"
            android:exported="false">
            <intent-filter>
                <action android:name="android.intent.action.BOOT_COMPLETED" />
            </intent-filter>
        </receiver>

    </application>
</manifest>
EOF

cat > "$PKG_DIR/GatePreferences.kt" <<'EOF'
package com.example.gatecontrol

import android.content.Context

object GatePreferences {
    private const val PREFS_NAME = "gate_control_preferences"
    private const val KEY_PHONE_NUMBER = "gate_phone_number"
    private const val KEY_OPEN_COMMAND = "gate_open_command"
    private const val KEY_CLOSE_COMMAND = "gate_close_command"
    private const val KEY_CONTACT_LOOKUP_KEY = "gate_contact_lookup_key"
    private const val KEY_CONTACT_PHONE_DATA_ID = "gate_contact_phone_data_id"
    private const val KEY_CONTACT_NAME = "gate_contact_name"
    private const val KEY_EDGE_ENABLED = "edge_swipe_enabled"

    fun getPhoneNumber(context: Context): String = prefs(context)
        .getString(KEY_PHONE_NUMBER, "")?.trim().orEmpty()

    fun setPhoneNumber(context: Context, number: String) {
        prefs(context).edit().putString(KEY_PHONE_NUMBER, number.trim()).apply()
    }

    fun getOpenCommand(context: Context): String = prefs(context)
        .getString(KEY_OPEN_COMMAND, "2011#ON#")?.trim().orEmpty().ifBlank { "2011#ON#" }

    fun setOpenCommand(context: Context, command: String) {
        prefs(context).edit().putString(KEY_OPEN_COMMAND, command.trim()).apply()
    }

    fun getCloseCommand(context: Context): String = prefs(context)
        .getString(KEY_CLOSE_COMMAND, "2011#OFF#")?.trim().orEmpty().ifBlank { "2011#OFF#" }

    fun setCloseCommand(context: Context, command: String) {
        prefs(context).edit().putString(KEY_CLOSE_COMMAND, command.trim()).apply()
    }

    fun setContact(context: Context, lookupKey: String, phoneDataId: Long, displayName: String) {
        prefs(context).edit()
            .putString(KEY_CONTACT_LOOKUP_KEY, lookupKey)
            .putLong(KEY_CONTACT_PHONE_DATA_ID, phoneDataId)
            .putString(KEY_CONTACT_NAME, displayName)
            .apply()
    }

    fun clearContact(context: Context) {
        prefs(context).edit()
            .remove(KEY_CONTACT_LOOKUP_KEY)
            .remove(KEY_CONTACT_PHONE_DATA_ID)
            .remove(KEY_CONTACT_NAME)
            .apply()
    }

    fun getContactLookupKey(context: Context): String = prefs(context)
        .getString(KEY_CONTACT_LOOKUP_KEY, "").orEmpty()

    fun getContactPhoneDataId(context: Context): Long = prefs(context)
        .getLong(KEY_CONTACT_PHONE_DATA_ID, -1L)

    fun getContactName(context: Context): String = prefs(context)
        .getString(KEY_CONTACT_NAME, "").orEmpty()

    fun usesContact(context: Context): Boolean = getContactLookupKey(context).isNotBlank()

    fun isEdgeEnabled(context: Context): Boolean =
        prefs(context).getBoolean(KEY_EDGE_ENABLED, false)

    fun setEdgeEnabled(context: Context, enabled: Boolean) {
        prefs(context).edit().putBoolean(KEY_EDGE_ENABLED, enabled).apply()
    }

    private fun prefs(context: Context) =
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
}
EOF

cat > "$PKG_DIR/BootReceiver.kt" <<'EOF'
package com.example.gatecontrol

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.provider.Settings

class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Intent.ACTION_BOOT_COMPLETED) return
        if (!GatePreferences.isEdgeEnabled(context)) return
        if (!Settings.canDrawOverlays(context)) return

        val serviceIntent = Intent(context, EdgeSwipeService::class.java)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            context.startForegroundService(serviceIntent)
        } else {
            context.startService(serviceIntent)
        }
    }
}
EOF

cat > "$PKG_DIR/EdgeSwipeService.kt" <<'EOF'
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
EOF

cat > "$PKG_DIR/MainActivity.kt" <<'EOF'
package com.example.gatecontrol

import android.Manifest
import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.ContactsContract
import android.provider.Settings
import android.widget.Button
import android.widget.TextView
import android.widget.Toast
import androidx.activity.result.contract.ActivityResultContracts
import androidx.appcompat.app.AppCompatActivity
import androidx.core.content.ContextCompat
import com.google.android.material.textfield.TextInputEditText

class MainActivity : AppCompatActivity() {

    private lateinit var phoneNumberInput: TextInputEditText
    private lateinit var openCommandInput: TextInputEditText
    private lateinit var closeCommandInput: TextInputEditText
    private lateinit var statusText: TextView
    private var waitingForOverlayPermission = false

    private val requestSmsPermission =
        registerForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
            updateStatus()
            Toast.makeText(
                this,
                if (granted) "SMS permission granted" else "SMS permission is required",
                Toast.LENGTH_SHORT
            ).show()
        }

    private val requestContactsPermission =
        registerForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
            if (granted) launchContactPicker()
            else Toast.makeText(
                this,
                "Contacts permission is needed to keep the gate number linked",
                Toast.LENGTH_LONG
            ).show()
            updateStatus()
        }

    private val requestNotificationPermission =
        registerForActivityResult(ActivityResultContracts.RequestPermission()) {
            startEdgeServiceIfAllowed()
        }

    private val pickGatePhone =
        registerForActivityResult(ActivityResultContracts.StartActivityForResult()) { result ->
            val uri = result.data?.data ?: return@registerForActivityResult
            if (result.resultCode != RESULT_OK) return@registerForActivityResult

            contentResolver.query(
                uri,
                arrayOf(
                    ContactsContract.CommonDataKinds.Phone._ID,
                    ContactsContract.CommonDataKinds.Phone.NUMBER,
                    ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME,
                    ContactsContract.CommonDataKinds.Phone.LOOKUP_KEY
                ),
                null,
                null,
                null
            )?.use { cursor ->
                if (cursor.moveToFirst()) {
                    val dataId = cursor.getLong(0)
                    val number = cursor.getString(1).orEmpty()
                    val name = cursor.getString(2).orEmpty()
                    val lookupKey = cursor.getString(3).orEmpty()

                    if (lookupKey.isNotBlank()) {
                        GatePreferences.setContact(this, lookupKey, dataId, name)
                        GatePreferences.setPhoneNumber(this, number)
                        phoneNumberInput.setText(number)
                        refreshWidgets()
                        updateStatus()
                        Toast.makeText(
                            this,
                            "Linked to ${name.ifBlank { "selected contact" }}",
                            Toast.LENGTH_SHORT
                        ).show()
                    }
                }
            }
        }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_main)

        phoneNumberInput = findViewById(R.id.phoneNumberInput)
        openCommandInput = findViewById(R.id.openCommandInput)
        closeCommandInput = findViewById(R.id.closeCommandInput)
        statusText = findViewById(R.id.statusText)

        val saveButton: Button = findViewById(R.id.saveButton)
        val chooseContactButton: Button = findViewById(R.id.chooseContactButton)
        val useManualNumberButton: Button = findViewById(R.id.useManualNumberButton)
        val permissionButton: Button = findViewById(R.id.permissionButton)
        val enableEdgeButton: Button = findViewById(R.id.enableEdgeButton)
        val disableEdgeButton: Button = findViewById(R.id.disableEdgeButton)

        phoneNumberInput.setText(GatePreferences.getPhoneNumber(this))
        openCommandInput.setText(GatePreferences.getOpenCommand(this))
        closeCommandInput.setText(GatePreferences.getCloseCommand(this))

        saveButton.setOnClickListener {
            val number = phoneNumberInput.text?.toString()?.trim().orEmpty()
            val openCommand = openCommandInput.text?.toString()?.trim().orEmpty()
            val closeCommand = closeCommandInput.text?.toString()?.trim().orEmpty()

            if (!GatePreferences.usesContact(this) && number.isBlank()) {
                phoneNumberInput.error = "Enter a gate number or choose a contact"
                return@setOnClickListener
            }
            if (openCommand.isBlank()) {
                openCommandInput.error = "Enter the OPEN command"
                return@setOnClickListener
            }
            if (closeCommand.isBlank()) {
                closeCommandInput.error = "Enter the CLOSE command"
                return@setOnClickListener
            }

            GatePreferences.setPhoneNumber(this, number)
            GatePreferences.setOpenCommand(this, openCommand)
            GatePreferences.setCloseCommand(this, closeCommand)
            refreshWidgets()
            updateStatus()
            Toast.makeText(this, "Settings saved", Toast.LENGTH_SHORT).show()
        }

        chooseContactButton.setOnClickListener {
            if (ContextCompat.checkSelfPermission(
                    this,
                    Manifest.permission.READ_CONTACTS
                ) == PackageManager.PERMISSION_GRANTED
            ) {
                launchContactPicker()
            } else {
                requestContactsPermission.launch(Manifest.permission.READ_CONTACTS)
            }
        }

        useManualNumberButton.setOnClickListener {
            GatePreferences.clearContact(this)
            updateStatus()
            Toast.makeText(this, "Using manually entered number", Toast.LENGTH_SHORT).show()
        }

        permissionButton.setOnClickListener {
            if (ContextCompat.checkSelfPermission(
                    this,
                    Manifest.permission.SEND_SMS
                ) == PackageManager.PERMISSION_GRANTED
            ) {
                Toast.makeText(this, "SMS permission is already enabled", Toast.LENGTH_SHORT).show()
            } else {
                requestSmsPermission.launch(Manifest.permission.SEND_SMS)
            }
        }

        enableEdgeButton.setOnClickListener { enableEdgeSwipe() }

        disableEdgeButton.setOnClickListener {
            GatePreferences.setEdgeEnabled(this, false)
            stopService(Intent(this, EdgeSwipeService::class.java))
            updateStatus()
            Toast.makeText(this, "Edge swipe disabled", Toast.LENGTH_SHORT).show()
        }

        updateStatus()
    }

    override fun onResume() {
        super.onResume()

        if (waitingForOverlayPermission) {
            waitingForOverlayPermission = false
            if (Settings.canDrawOverlays(this)) {
                finishEnableEdgeSwipe()
            }
        } else if (GatePreferences.isEdgeEnabled(this) && Settings.canDrawOverlays(this)) {
            startEdgeServiceIfAllowed()
        }

        updateStatus()
    }

    private fun enableEdgeSwipe() {
        if (!Settings.canDrawOverlays(this)) {
            waitingForOverlayPermission = true
            val intent = Intent(
                Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                Uri.parse("package:$packageName")
            )
            startActivity(intent)
            return
        }

        finishEnableEdgeSwipe()
    }

    private fun finishEnableEdgeSwipe() {
        GatePreferences.setEdgeEnabled(this, true)

        if (
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            ContextCompat.checkSelfPermission(
                this,
                Manifest.permission.POST_NOTIFICATIONS
            ) != PackageManager.PERMISSION_GRANTED
        ) {
            requestNotificationPermission.launch(Manifest.permission.POST_NOTIFICATIONS)
        } else {
            startEdgeServiceIfAllowed()
        }

        updateStatus()
    }

    private fun startEdgeServiceIfAllowed() {
        if (!GatePreferences.isEdgeEnabled(this)) return
        if (!Settings.canDrawOverlays(this)) return

        val intent = Intent(this, EdgeSwipeService::class.java)
        ContextCompat.startForegroundService(this, intent)
    }

    private fun launchContactPicker() {
        val intent = Intent(Intent.ACTION_PICK, ContactsContract.CommonDataKinds.Phone.CONTENT_URI)
        pickGatePhone.launch(intent)
    }

    private fun updateStatus() {
        val smsAllowed = ContextCompat.checkSelfPermission(
            this,
            Manifest.permission.SEND_SMS
        ) == PackageManager.PERMISSION_GRANTED

        val linked = GatePreferences.usesContact(this)
        val contactName = GatePreferences.getContactName(this)
        val currentNumber = if (
            ContextCompat.checkSelfPermission(
                this,
                Manifest.permission.READ_CONTACTS
            ) == PackageManager.PERMISSION_GRANTED
        ) {
            runCatching { GateContactResolver.resolvePhoneNumber(this) }.getOrNull()
        } else {
            GatePreferences.getPhoneNumber(this).ifBlank { null }
        }

        if (currentNumber != null && currentNumber != phoneNumberInput.text?.toString()) {
            phoneNumberInput.setText(currentNumber)
            GatePreferences.setPhoneNumber(this, currentNumber)
        }

        val overlayAllowed = Settings.canDrawOverlays(this)
        val edgeEnabled = GatePreferences.isEdgeEnabled(this)

        statusText.text = buildString {
            append("Number source: ")
            if (linked) append("Contact: ${contactName.ifBlank { "Gate" }}") else append("Manual")
            append("\nCurrent number: ")
            append(currentNumber ?: "Not configured")
            append("\nSMS permission: ")
            append(if (smsAllowed) "Allowed" else "Not allowed")
            append("\nDisplay over other apps: ")
            append(if (overlayAllowed) "Allowed" else "Not allowed")
            append("\nEdge swipe: ")
            append(if (edgeEnabled && overlayAllowed) "Enabled — swipe inward from the middle-right edge" else "Disabled")
        }
    }

    private fun refreshWidgets() {
        val manager = AppWidgetManager.getInstance(this)
        val component = ComponentName(this, GateWidgetProvider::class.java)
        val ids = manager.getAppWidgetIds(component)
        GateWidgetProvider.updateWidgets(this, manager, ids)
    }
}
EOF

cat > "$RES/layout/activity_main.xml" <<'EOF'
<?xml version="1.0" encoding="utf-8"?>
<ScrollView xmlns:android="http://schemas.android.com/apk/res/android"
    android:layout_width="match_parent"
    android:layout_height="match_parent"
    android:fillViewport="true">

    <LinearLayout
        android:layout_width="match_parent"
        android:layout_height="wrap_content"
        android:orientation="vertical"
        android:padding="24dp">

        <TextView
            android:layout_width="wrap_content"
            android:layout_height="wrap_content"
            android:text="Gate Control"
            android:textSize="28sp"
            android:textStyle="bold"
            android:layout_marginBottom="8dp" />

        <TextView
            android:layout_width="wrap_content"
            android:layout_height="wrap_content"
            android:text="Configure the gate once, then use a swipe from the right edge instead of keeping a widget on screen."
            android:textSize="16sp"
            android:layout_marginBottom="20dp" />

        <Button
            android:id="@+id/enableEdgeButton"
            android:layout_width="match_parent"
            android:layout_height="wrap_content"
            android:text="Enable edge swipe control" />

        <Button
            android:id="@+id/disableEdgeButton"
            android:layout_width="match_parent"
            android:layout_height="wrap_content"
            android:layout_marginTop="8dp"
            android:text="Disable edge swipe control" />

        <TextView
            android:layout_width="match_parent"
            android:layout_height="wrap_content"
            android:layout_marginTop="10dp"
            android:layout_marginBottom="20dp"
            android:text="When enabled: swipe from the middle-right edge toward the centre. OPEN/CLOSE always requires confirmation before sending."
            android:textSize="14sp" />

        <Button
            android:id="@+id/chooseContactButton"
            android:layout_width="match_parent"
            android:layout_height="wrap_content"
            android:text="Choose gate contact" />

        <Button
            android:id="@+id/useManualNumberButton"
            android:layout_width="match_parent"
            android:layout_height="wrap_content"
            android:layout_marginTop="8dp"
            android:text="Use manual number instead" />

        <com.google.android.material.textfield.TextInputLayout
            android:layout_width="match_parent"
            android:layout_height="wrap_content"
            android:layout_marginTop="16dp"
            android:hint="Gate phone number">

            <com.google.android.material.textfield.TextInputEditText
                android:id="@+id/phoneNumberInput"
                android:layout_width="match_parent"
                android:layout_height="wrap_content"
                android:inputType="phone"
                android:singleLine="true" />
        </com.google.android.material.textfield.TextInputLayout>

        <com.google.android.material.textfield.TextInputLayout
            android:layout_width="match_parent"
            android:layout_height="wrap_content"
            android:layout_marginTop="16dp"
            android:hint="OPEN SMS command">

            <com.google.android.material.textfield.TextInputEditText
                android:id="@+id/openCommandInput"
                android:layout_width="match_parent"
                android:layout_height="wrap_content"
                android:inputType="text"
                android:singleLine="true" />
        </com.google.android.material.textfield.TextInputLayout>

        <com.google.android.material.textfield.TextInputLayout
            android:layout_width="match_parent"
            android:layout_height="wrap_content"
            android:layout_marginTop="12dp"
            android:hint="CLOSE SMS command">

            <com.google.android.material.textfield.TextInputEditText
                android:id="@+id/closeCommandInput"
                android:layout_width="match_parent"
                android:layout_height="wrap_content"
                android:inputType="text"
                android:singleLine="true" />
        </com.google.android.material.textfield.TextInputLayout>

        <Button
            android:id="@+id/saveButton"
            android:layout_width="match_parent"
            android:layout_height="wrap_content"
            android:layout_marginTop="20dp"
            android:text="Save settings" />

        <Button
            android:id="@+id/permissionButton"
            android:layout_width="match_parent"
            android:layout_height="wrap_content"
            android:layout_marginTop="12dp"
            android:text="Allow SMS permission" />

        <TextView
            android:id="@+id/statusText"
            android:layout_width="match_parent"
            android:layout_height="wrap_content"
            android:layout_marginTop="24dp"
            android:textSize="15sp" />

    </LinearLayout>
</ScrollView>
EOF

cat > "$RES/layout/edge_control_panel.xml" <<'EOF'
<?xml version="1.0" encoding="utf-8"?>
<LinearLayout xmlns:android="http://schemas.android.com/apk/res/android"
    android:layout_width="match_parent"
    android:layout_height="wrap_content"
    android:background="@drawable/edge_panel_background"
    android:elevation="16dp"
    android:orientation="vertical"
    android:padding="20dp">

    <LinearLayout
        android:layout_width="match_parent"
        android:layout_height="wrap_content"
        android:gravity="center_vertical"
        android:orientation="horizontal">

        <TextView
            android:id="@+id/panelTitle"
            android:layout_width="0dp"
            android:layout_height="wrap_content"
            android:layout_weight="1"
            android:text="HOME GATE"
            android:textColor="#FFFFFFFF"
            android:textSize="21sp"
            android:textStyle="bold" />

        <TextView
            android:id="@+id/panelDismissButton"
            android:layout_width="42dp"
            android:layout_height="42dp"
            android:gravity="center"
            android:text="×"
            android:textColor="#CCFFFFFF"
            android:textSize="28sp" />
    </LinearLayout>

    <TextView
        android:id="@+id/panelSubtitle"
        android:layout_width="match_parent"
        android:layout_height="wrap_content"
        android:layout_marginTop="2dp"
        android:layout_marginBottom="18dp"
        android:text="Choose an action"
        android:textColor="#BFFFFFFF"
        android:textSize="14sp" />

    <LinearLayout
        android:id="@+id/actionsGroup"
        android:layout_width="match_parent"
        android:layout_height="wrap_content"
        android:orientation="horizontal">

        <Button
            android:id="@+id/panelOpenButton"
            android:layout_width="0dp"
            android:layout_height="58dp"
            android:layout_weight="1"
            android:text="OPEN"
            android:textStyle="bold" />

        <Button
            android:id="@+id/panelCloseButton"
            android:layout_width="0dp"
            android:layout_height="58dp"
            android:layout_marginStart="10dp"
            android:layout_weight="1"
            android:text="CLOSE"
            android:textStyle="bold" />
    </LinearLayout>

    <LinearLayout
        android:id="@+id/confirmGroup"
        android:layout_width="match_parent"
        android:layout_height="wrap_content"
        android:orientation="vertical"
        android:visibility="gone">

        <TextView
            android:id="@+id/confirmMessage"
            android:layout_width="match_parent"
            android:layout_height="wrap_content"
            android:layout_marginBottom="14dp"
            android:text="Open the home gate?"
            android:textColor="#FFFFFFFF"
            android:textSize="17sp" />

        <LinearLayout
            android:layout_width="match_parent"
            android:layout_height="wrap_content"
            android:orientation="horizontal">

            <Button
                android:id="@+id/panelCancelButton"
                android:layout_width="0dp"
                android:layout_height="54dp"
                android:layout_weight="1"
                android:text="CANCEL" />

            <Button
                android:id="@+id/panelConfirmButton"
                android:layout_width="0dp"
                android:layout_height="54dp"
                android:layout_marginStart="10dp"
                android:layout_weight="1"
                android:text="CONFIRM"
                android:textStyle="bold" />
        </LinearLayout>
    </LinearLayout>

    <TextView
        android:id="@+id/panelStatus"
        android:layout_width="match_parent"
        android:layout_height="wrap_content"
        android:gravity="center"
        android:paddingTop="10dp"
        android:paddingBottom="6dp"
        android:text="SMS sent successfully"
        android:textColor="#FFFFFFFF"
        android:textSize="16sp"
        android:textStyle="bold"
        android:visibility="gone" />

</LinearLayout>
EOF

cat > "$RES/drawable/edge_panel_background.xml" <<'EOF'
<?xml version="1.0" encoding="utf-8"?>
<shape xmlns:android="http://schemas.android.com/apk/res/android"
    android:shape="rectangle">
    <gradient
        android:angle="315"
        android:startColor="#FF17243A"
        android:centerColor="#FF101A2A"
        android:endColor="#FF080E18"
        android:type="linear" />
    <corners android:radius="26dp" />
    <stroke
        android:width="1dp"
        android:color="#33FFFFFF" />
    <padding
        android:left="2dp"
        android:top="2dp"
        android:right="2dp"
        android:bottom="2dp" />
</shape>
EOF

cat > "$RES/drawable/widget_background.xml" <<'EOF'
<?xml version="1.0" encoding="utf-8"?>
<shape xmlns:android="http://schemas.android.com/apk/res/android"
    android:shape="rectangle">
    <gradient
        android:angle="315"
        android:startColor="#FF223653"
        android:centerColor="#FF142238"
        android:endColor="#FF0B1220"
        android:type="linear" />
    <corners android:radius="24dp" />
    <stroke
        android:width="1dp"
        android:color="#30FFFFFF" />
</shape>
EOF

cat > "$RES/drawable/widget_button_background.xml" <<'EOF'
<?xml version="1.0" encoding="utf-8"?>
<shape xmlns:android="http://schemas.android.com/apk/res/android"
    android:shape="rectangle">
    <solid android:color="#22FFFFFF" />
    <corners android:radius="16dp" />
    <stroke
        android:width="1dp"
        android:color="#25FFFFFF" />
</shape>
EOF

cat > "$RES/drawable/ic_gate_notification.xml" <<'EOF'
<vector xmlns:android="http://schemas.android.com/apk/res/android"
    android:width="24dp"
    android:height="24dp"
    android:viewportWidth="24"
    android:viewportHeight="24">
    <path
        android:fillColor="#FFFFFFFF"
        android:pathData="M4,3h16v18h-2v-8h-5v8h-2v-8H6v8H4V3zM6,5v6h12V5H6z" />
</vector>
EOF

cat > "$RES/layout/gate_widget.xml" <<'EOF'
<?xml version="1.0" encoding="utf-8"?>
<LinearLayout xmlns:android="http://schemas.android.com/apk/res/android"
    android:layout_width="match_parent"
    android:layout_height="match_parent"
    android:background="@drawable/widget_background"
    android:gravity="center"
    android:orientation="vertical"
    android:padding="14dp">

    <TextView
        android:layout_width="wrap_content"
        android:layout_height="wrap_content"
        android:layout_marginBottom="10dp"
        android:text="HOME GATE"
        android:textColor="#FFFFFFFF"
        android:textSize="15sp"
        android:textStyle="bold" />

    <LinearLayout
        android:layout_width="match_parent"
        android:layout_height="wrap_content"
        android:gravity="center"
        android:orientation="horizontal">

        <TextView
            android:id="@+id/openButton"
            android:layout_width="0dp"
            android:layout_height="52dp"
            android:layout_weight="1"
            android:background="@drawable/widget_button_background"
            android:gravity="center"
            android:text="OPEN"
            android:textColor="#FFFFFFFF"
            android:textSize="15sp"
            android:textStyle="bold" />

        <TextView
            android:id="@+id/closeButton"
            android:layout_width="0dp"
            android:layout_height="52dp"
            android:layout_marginStart="10dp"
            android:layout_weight="1"
            android:background="@drawable/widget_button_background"
            android:gravity="center"
            android:text="CLOSE"
            android:textColor="#FFFFFFFF"
            android:textSize="15sp"
            android:textStyle="bold" />
    </LinearLayout>
</LinearLayout>
EOF

# Keep the project clean of Windows ADS metadata.
find "$ROOT" -name '*:Zone.Identifier' -delete || true
if ! grep -qxF '*:Zone.Identifier' "$ROOT/.gitignore" 2>/dev/null; then
  echo '*:Zone.Identifier' >> "$ROOT/.gitignore"
fi

echo
echo "Files updated."
echo

git add -A
git status --short

echo
read -r -p "Commit and push Gate Control v2 now? [y/N] " answer
if [[ "${answer,,}" == "y" ]]; then
  git commit -m "Add edge swipe gate control with confirmation"
  git push
  echo
  echo "Pushed. GitHub Actions should build a new APK automatically."
else
  echo
  echo "Changes are ready locally. Review them, then commit/push when ready."
fi
