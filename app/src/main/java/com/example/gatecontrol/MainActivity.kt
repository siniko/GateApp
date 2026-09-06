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
