# Pager Lab Controller

Flutter Android utility for a personally authorized lab. The only device target is `172.16.52.1`. SSH is limited to fixed read-only probes; SFTP is limited to browsing and downloading within a configured `payloads/user` root. No payload execution, arbitrary shell command interface, games, or music/song generation features are present.

## Important status

This repository contains source/configuration only. No APK has been built, no code has been run through Flutter analyzer/tests, and no connection to real hardware has been verified. Package constraints are starting points; resolve compatible versions with your installed Flutter SDK and pub.dev. Pager firmware, SSH host fingerprint, and SFTP directory must be verified on your device.

## What the app does

- Fixed SSH destination: `172.16.52.1:22`; host key must match a SHA-256 fingerprint you verified out of band.
- Root username/password and host fingerprint are stored using Android secure storage.
- Fixed read-only probes: `uname -srm`, `/proc/uptime`, `/proc/loadavg`, `/proc/meminfo`, `df -P /`, `ip -brief address`, and bounded `logread -l 50`. Unsupported/unparseable results are marked unavailable.
- SFTP reads only under a configurable directory ending in `payloads/user`; payload files are never executed.
- `catalog.json` and `README.md` are read as human-authored metadata. Catalog entries require exact listed path, valid SHA-256 matching current file bytes, and a review date within 365 days. Otherwise the UI says `Unclassified — review required`.
- Separate View details and Download actions.
- Three deterministic, on-device assistant modules summarize current telemetry, catalog text, and audit records. They do not call a remote AI model, accept shell commands, or infer safety from catalog labels.
- Away mode is foreground-only. It requires a device authentication gate and explicit lab-context confirmation; it stops on app backgrounding, missed/failed connection checks, scope mismatch, or timer expiry. It does not claim to keep monitoring after Android suspends the app.

## Build on a computer or Termux environment with Flutter installed

1. Install Flutter and Android SDK/command-line tools, accept Android SDK licenses, and check `flutter doctor -v`.
2. Clone and generate the Android platform scaffold (this repo intentionally avoids checking in machine-generated Gradle wrapper binaries):

```sh
git clone https://github.com/jayeshmore9007-alt/pager-lab-controller.git
cd pager-lab-controller
flutter create --platforms=android --org org.example .
```

If `flutter create` asks to overwrite `lib/main.dart` or `pubspec.yaml`, do not overwrite the repository versions. If it reports an existing project instead, run `flutter create --platforms=android --org org.example --project-name pager_lab_controller .` and preserve existing source files.

3. Fetch packages and check the project:

```sh
flutter pub get
flutter analyze
flutter test
```

4. Build and install a debug APK on a connected, USB-debugging-enabled Android device:

```sh
flutter build apk --debug
adb devices
adb install -r build/app/outputs/flutter-apk/app-debug.apk
```

APK output: `build/app/outputs/flutter-apk/app-debug.apk`.

For a release APK (local testing; signing configuration may be required):

```sh
flutter build apk --release
```

## First device setup

- Connect the phone to the authorized lab network and verify the Pager is reachable at `172.16.52.1`.
- Obtain the Pager's SSH host-key SHA-256 fingerprint through a trusted, independent channel and enter it in the app. Never accept a key solely because the app displayed it.
- Enter SSH credentials in the app; do not put secrets in source control.
- Verify the SFTP directory on the Pager. Default is `/root/payloads/user`; change it in app settings only to the actual authorized `payloads/user` directory.
- Check results against the Pager's own interface. `OFFLINE` or `DEGRADED` is not replaced with cached/fabricated live data.

## Platform and safety limitations

- Away mode intentionally stops when app lifecycle leaves the foreground. Android can kill or suspend ordinary Flutter processes; this version has no foreground service, persistent Stop notification, or background polling guarantee. Do not rely on it for unattended monitoring.
- Biometric/passcode support depends on device enrollment, Android configuration, and `local_auth` plugin compatibility and needs real-device testing.
- The default remote root and command availability vary by firmware. The implementation never searches arbitrary filesystem paths.
- Catalog dates/hashes are metadata checks, not a safety certification. Binary/large items may not be previewable; downloads are user-initiated.
- AI agent responses are deterministic local summaries, not a general-purpose LLM. They never execute actions.

## Project structure

```text
lib/main.dart
lib/models/pager_models.dart
lib/services/pager_ssh_service.dart
lib/services/away_monitoring_controller.dart
lib/agents/lab_agents.dart
android/app/src/main/AndroidManifest.xml
```
