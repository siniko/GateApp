# Gate Control Android Widget

A small personal/family Android app with a home-screen widget for controlling a gate by SMS.

## Features

- Home-screen widget with **OPEN** and **CLOSE** buttons.
- Default commands:
  - OPEN: `2011#ON#`
  - CLOSE: `2011#OFF#`
- Both SMS commands are editable in the app.
- Gate number can be entered manually.
- Or choose a **Gate contact** from Android Contacts.
- When a contact is linked, the widget resolves its current phone number before every SMS. In normal use, changing the number in the Contacts app is enough; no Gate Control reconfiguration is required.
- No server/backend is used.

## First setup

1. Open the project in Android Studio (or IntelliJ IDEA with Android support).
2. Build/install it on the Android phone.
3. Open **Gate Control**.
4. Tap **Choose gate contact**, allow Contacts access, and choose the gate's phone entry. Alternatively enter the phone number manually.
5. Verify/edit the OPEN and CLOSE commands.
6. Tap **Save settings**.
7. Tap **Allow SMS permission** and approve it.
8. Add the **Gate Control** widget to the home screen.

## Contact behavior

The app stores the selected contact's Android lookup key and preferred phone row. Each time OPEN/CLOSE is pressed, it queries Contacts for the latest number. If the chosen phone row was recreated during an edit, it falls back to the contact's primary/current phone number.

If the contact has multiple phone numbers, select the gate phone entry in the picker. If you later delete that exact entry and the app has to fall back, it will prefer the contact's primary phone number.

## Permissions

- `SEND_SMS` — required to send the gate command directly from the widget.
- `READ_CONTACTS` — required only for the linked-contact mode so the current number can be read when the widget is pressed.

## Build APK with GitHub Actions

This project includes `.github/workflows/build-apk.yml`.

1. Create a GitHub repository and upload/push the entire project, including the hidden `.github` folder.
2. Open the repository on GitHub and choose **Actions**.
3. Select **Build Android APK**.
4. Click **Run workflow** (or simply push to `main`/`master`; that also triggers a build).
5. When the run finishes, open it and download the **GateControl-APK** artifact.
6. Extract the downloaded ZIP. Inside it is `GateControl.apk`, ready to install on an Android phone.

The workflow builds a debug APK. This is suitable for private/family installation and testing. Android may ask you to allow installation from unknown sources on each phone.
