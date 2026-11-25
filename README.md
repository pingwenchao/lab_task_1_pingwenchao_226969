# GeoPhoto — SSW3401 Lab Task 1

A Flutter mobile application designed following **Apple Human Interface Guidelines (iOS 18+)** that integrates device camera capture, asynchronous GPS telemetry, graceful runtime permission handling, offline local caching, and an automated CI/CD deployment pipeline to Firebase App Distribution.

- **Course:** SSW3401 Mobile Application Development
- **Student:** Ping Wenchao (`226969`)
- **Android Package:** `com.upm.pingwenchao.lab_task_1_pingwenchao_226969`

---

## Key Features

### 1. Apple HIG UI & Interaction
- **Light & OLED Dark Mode:** System-styled theme toggle persisted locally via `SharedPreferences`.
- **Responsive Zero-Overflow Layout:** Built with `CustomScrollView`, `SliverAppBar`, `Row`, `Column`, `Container`, `Image`, and frosted-glass floating action bars.
- **Full-Screen Photo Viewer:** Smooth `Hero` transition with `InteractiveViewer` supporting pinch-to-zoom and drag gestures.
- **Control Center Permission Pills:** Live `Camera` and `Location` status indicators with one-tap permission request or Settings redirection.

### 2. Device Sensors & Permission Handling
- **Camera & GPS Integration:** Captures photos via `image_picker` and acquires asynchronous GPS telemetry (`Latitude`, `Longitude`, `Altitude`, `Accuracy`, `Speed`) using `geolocator` with timeout and offline last-known fallback.
- **Live GPS Tracking:** Toggleable real-time coordinate stream via `CupertinoSwitch` using tabular numeric figures to prevent layout jitter.
- **Graceful Location Denial Handling:** If the user denies location permission, the app does **not** crash. Instead, it displays a non-blocking orange warning banner with a direct **Settings** shortcut, allows the photo to be captured and saved offline, and records the GPS status as `Location Permission Denied`.

### 3. Offline Persistence & Caching
- **Multi-Photo History Gallery:** Stores a serialized JSON list of `GeoPhotoRecord` entries in `SharedPreferences` alongside permanent image files copied to the app documents directory via `path_provider`.
- **Automatic Startup Restoration:** Restores the latest photo, full history filmstrip, GPS telemetry, custom photo notes, and theme preference automatically inside `initState()`—even offline after force-closing the app.
- **Storage & Cache Inspector:** Collapsible panel displaying cache engine status, local file path, file size, and record count.

---

## CI/CD Pipeline (GitHub Actions → Firebase App Distribution)

Every push to the `main` branch automatically triggers `.github/workflows/firebase_deploy.yml` with a two-job workflow:

1. **Job 1 — `Code Analysis & Tests`**
    - Runs `flutter pub get`
    - Runs static analysis (`flutter analyze --no-fatal-infos`)
    - Executes automated widget tests (`flutter test`)
2. **Job 2 — `Build & Deploy to Firebase App Distribution`** *(runs only after Job 1 succeeds)*
    - Sets up Java 21 LTS and stable Flutter SDK
    - Builds release APK with auto-incremented build number (`--build-number=${{ github.run_number }}`)
    - Uploads APK to Firebase App Distribution using GitHub Secrets (`FIREBASE_APP_ID`, `CREDENTIAL_FILE_CONTENT`)
    - Automatically attaches commit SHA release notes and distributes to the `testers` group

---

## Local Setup & Verification

```bash
flutter pub get
flutter analyze --no-fatal-infos
flutter test
flutter run