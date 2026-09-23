# AppTesterClub for Android

The Android client. Browse every instance you are paired with, and install APK
builds straight from the phone.

## Build it

Android Studio, or the command line:

```bash
cd android
echo "sdk.dir=$HOME/Library/Android/sdk" > local.properties
./gradlew assembleRelease
```

The APK lands in `app/build/outputs/apk/release/`. It is signed with the debug
key so a fresh clone produces something installable with no setup; replace it
with your own keystore before handing builds to real testers.

## Pairing

Open `/pair` on your instance and scan the code, or tap the
`apptesterclub://pair?...` link on the phone. The same link works for the iOS
client, so one QR code serves both.

## How installing works

This is the part that differs from iOS. iOS needs a signed manifest and an
`itms-services://` URL because the system fetches the binary itself. Android is
the opposite: the app downloads the APK to its own cache and hands it to the
system package installer through a FileProvider.

Two consequences, both good. The download is ours, so progress is real rather
than a spinner. And "is this installed?" has an exact answer from the package
manager, including the installed version, where the iOS client can only ask
whether a URL scheme resolves.

Android will not let any app install packages until you grant it that right.
The first Install tap sends you to the right settings page.

## Not here yet

- Push notifications. The server speaks APNs, not FCM, so a new build does not
  notify an Android phone. See ROADMAP.md.
- QR scanning in-app. Pairing links work; the camera scanner does not exist yet.
