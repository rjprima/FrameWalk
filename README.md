# FrameWalk

An app designed to help you find inspiration and never run out of things to photograph, all while taking relaxing walks through your community.

## Layout

```bash

FrameWalk/
├── frame_walk
│   ├── backend
│   └── frontend
├── .gitignore
├── LICENSE
├── README.md
└── coding-guidelines.md

```

## Goals

Users will be able to explore their surrounding area and find inspiration in their environment through photography prompts along routes/locations around the University of Washington, Seattle, campus.

Whether a user’s list of ideas has met its end or has struggled to even start, lack of inspiration can demotivate, kill consistency, and vice versa. We don’t want users to be stuck wishing they could be more creative and feeling like they need a lucky epiphany instead of a reliable source to offer an aesthetic vision.

Since people have their typical routes around school, work, and their general neighborhood, new places and scenery lie waiting to be discovered. Offering users a new, specific path with curated photo prompts will let them literally see the space through a new lens.
As the seasons change, we want users to reflect on a detailed catalog of their exploration and personal perspective along with their ever-changing environment.

## Android Setup and Google Maps Configuration

This guide walks you through running FrameWalk on an Android emulator with a working Google Maps view, on either **macOS** or **Windows**. Every teammate sets up their own Google Maps API key. Keys are never shared or committed.

Quick facts about how this project is configured:

| Setting | Value | Where it's defined |
| --- | --- | --- |
| Flutter project root | `FrameWalk/frame_walk/` | folder containing `pubspec.yaml` |
| Android application ID (package name) | `com.frame_walk.app` | `frame_walk/android/app/build.gradle.kts` |
| Maps plugin | `google_maps_flutter` | `frame_walk/pubspec.yaml` |
| Where your API key goes | `MAPS_API_KEY=...` in `frame_walk/android/local.properties` | not committed (ignored by `frame_walk/android/.gitignore`) |
| How the key reaches the app | `build.gradle.kts` reads `MAPS_API_KEY` from `local.properties` and passes it to `AndroidManifest.xml` as `${MAPS_API_KEY}` | `frame_walk/android/app/build.gradle.kts`, `frame_walk/android/app/src/main/AndroidManifest.xml` |

> **Commands:** when macOS and Windows differ, both are shown. Mac commands are for the **Terminal** app; Windows commands are for **PowerShell**. Commands that are the same on both are shown once.

### 1. Prerequisites

#### 1.1 Install Flutter (includes Dart)

Dart comes bundled with Flutter, so you don't install it separately. The project requires Dart `^3.13.5` (see `pubspec.yaml`), so use a current **stable** Flutter release. The project was set up with Flutter 3.47.8.

1. Follow the official install guide for your OS and choose **Android** as the target platform:
   - macOS: <https://docs.flutter.dev/get-started/install/macos>
   - Windows: <https://docs.flutter.dev/get-started/install/windows>
2. Make sure the `flutter` command is on your `PATH`. Close and reopen your terminal, then run:

   ```bash
   flutter --version
   ```

   You should see `channel stable` and a Dart version of 3.13.5 or newer. If not, run `flutter upgrade`.

#### 1.2 Install Android Studio

1. Download and install Android Studio from <https://developer.android.com/studio>.
2. Open it and complete the **Setup Wizard** using the **Standard** install type. This installs the Android SDK, Android Emulator, and a bundled Java runtime (JDK). You don't need to install Java separately.
3. Open the SDK Manager:
   - **macOS:** **Android Studio > Settings > Languages & Frameworks > Android SDK**
   - **Windows:** **File > Settings > Languages & Frameworks > Android SDK**

   (From the Welcome screen: **More Actions > SDK Manager**.)
4. On the **SDK Tools** tab, make sure these are checked, then click **Apply**:
   - Android SDK Build-Tools
   - **Android SDK Command-line Tools (latest)** (`flutter doctor` needs this)
   - Android Emulator
   - Android SDK Platform-Tools

#### 1.3 Install the Flutter and Dart plugins in Android Studio

1. Open the Plugins settings:
   - **macOS:** **Android Studio > Settings > Plugins**
   - **Windows:** **File > Settings > Plugins**
2. On the **Marketplace** tab, search for **Flutter** and click **Install**. Accept when it offers to install **Dart** too.
3. Restart Android Studio.

#### 1.4 Create an Android emulator

1. In Android Studio, open **Device Manager**: **View > Tool Windows > Device Manager**, or **More Actions > Virtual Device Manager** on the Welcome screen.
2. Click **+** (Create Virtual Device) and pick a phone, such as **Pixel 8**, then click **Next**.
3. Pick a system image. **This step matters for Google Maps:**
   - Choose an image whose **Services** column says **Google Play** (preferred) or **Google APIs**.
   - Do **not** choose a plain "Android Open Source" image. Those have no Google Play Services, and the map will not load.
   - **Mac with Apple silicon (M1/M2/M3/M4):** choose an **arm64-v8a** image.
   - **Windows and Intel Macs:** choose an **x86_64** image.
   - Download a recent API level, for example the latest one marked "Recommended".
4. Click **Next**, then **Finish**. Press **▶** next to the device to start it once and confirm it boots.

**Windows only, if the emulator won't start or is extremely slow:** the emulator needs hardware virtualization.

- Make sure virtualization (Intel VT-x / AMD-V / SVM) is enabled in your BIOS/UEFI settings.
- In SDK Manager > SDK Tools, install **Android Emulator hypervisor driver (installer)**, *or* turn on **Windows Hypervisor Platform** under **Control Panel > Programs > Turn Windows features on or off**, then restart.

**macOS:** no extra virtualization setup is needed.

#### 1.5 Verify with `flutter doctor`

1. Accept the Android SDK licenses (type `y` for each):

   ```bash
   flutter doctor --android-licenses
   ```

2. Run the doctor:

   ```bash
   flutter doctor
   ```

3. For this project you need green checkmarks for **Flutter**, **Android toolchain**, and **Android Studio**. Warnings about Xcode, Chrome, or Visual Studio are fine to ignore; we're only targeting Android here.

### 2. Getting the Project Running

#### 2.1 Clone the repository

```bash
git clone https://github.com/rjprima/FrameWalk.git
```

(If you've set up SSH keys with GitHub, you can use `git@github.com:rjprima/FrameWalk.git` instead.)

#### 2.2 Open the correct folder in Android Studio

The Flutter project lives in the **`frame_walk`** subfolder, not the top-level `FrameWalk` folder.

1. In Android Studio choose **File > Open** (or **Open** on the Welcome screen).
2. Select **`FrameWalk/frame_walk`** (the folder that contains `pubspec.yaml`) and click **Open**.
   - Don't open `FrameWalk/` (the repo root) or `FrameWalk/frame_walk/android/`. Android Studio won't recognize them as a Flutter project.
3. If Android Studio asks for the Flutter SDK path, point it to the folder where you installed Flutter.

#### 2.3 Install dependencies

From a terminal in the `frame_walk` folder (Android Studio has one built in under **View > Tool Windows > Terminal**):

macOS:

```bash
cd FrameWalk/frame_walk
flutter pub get
```

Windows (PowerShell):

```powershell
cd FrameWalk\frame_walk
flutter pub get
```

#### 2.4 Build once to generate local files

Run one debug build. It doesn't need an API key yet. It creates three files that are intentionally **not** in Git and are needed in later steps:

- `android/local.properties` (holds your SDK paths, and later your API key)
- `android/gradlew` / `android/gradlew.bat` (the Gradle wrapper scripts)
- your personal debug signing key (`.android/debug.keystore` in your home folder)

```bash
flutter build apk --debug
```

The first build downloads Gradle and other dependencies and can take several minutes.

#### 2.5 Pick an emulator and run the app

1. Start your emulator from **Device Manager** (▶), or from the terminal:

   ```bash
   flutter emulators
   flutter emulators --launch <emulator id from the list>
   ```

2. Confirm Flutter can see it:

   ```bash
   flutter devices
   ```

   You should see something like `sdk gphone64 ... (mobile) • emulator-5554 • android-...`.
3. Run the app:
   - **Android Studio:** pick the emulator in the device dropdown in the top toolbar, make sure the run configuration is `main.dart`, and click **Run ▶**.
   - **Terminal:**

     ```bash
     flutter run
     ```

     If more than one device is connected, use `flutter run -d emulator-5554` (with your device ID).

The app should open. **The Map tab will be blank until you finish Section 3.**

### 3. Google Maps API Setup

Each teammate creates their **own** API key tied to **their own** computer's debug signing certificate (SHA-1). This keeps keys out of GitHub and means one person's key can't break anyone else's setup.

#### 3.1 Create or select a Google Cloud project

1. Go to <https://console.cloud.google.com/> and sign in.
2. Click the project picker at the top of the page, then **New Project**.
3. Name it (for example `framewalk-yourname`), click **Create**, then make sure it's selected in the project picker.

#### 3.2 Enable billing

Google requires a billing account on any project that uses the Maps Platform, even for usage that's free.

1. Open **☰ Menu > Billing** and link or create a billing account for the project. New accounts are usually offered free-trial credit.
2. Check the current pricing at <https://mapsplatform.google.com/pricing/>. At the time of writing, map loads in the Maps SDK for Android don't incur charges, but confirm this yourself.
3. Recommended: under **Billing > Budgets & alerts**, create a small budget (e.g. $1) so you get an email if anything ever starts charging.

#### 3.3 Enable the Maps SDK for Android

1. Open **☰ Menu > APIs & Services > Library**.
2. Search for **Maps SDK for Android**, open it, and click **Enable**.

#### 3.4 Create an API key

1. Open **☰ Menu > APIs & Services > Credentials**.
2. Click **+ Create credentials > API key**.
3. Copy the key (it starts with `AIza`) somewhere private for now. **Don't paste it into Slack, Discord, a text message, a Google Doc, or any file in the repo.**

#### 3.5 Find the project's Android package name

Our application ID is:

```text
com.frame_walk.app
```

You can confirm it in `frame_walk/android/app/build.gradle.kts` (look for `applicationId`). If that value is ever changed, everyone must update their key restriction to match.

#### 3.6 Get your debug SHA-1 fingerprint

Android signs debug builds with a debug keystore that's unique to **your** computer, so your SHA-1 is different from everyone else's. Complete step 2.4 first so that the keystore and the Gradle wrapper exist.

**Option A: Gradle wrapper `signingReport` (recommended)**

macOS:

```bash
cd android
./gradlew signingReport
```

Windows (PowerShell):

```powershell
cd android
.\gradlew.bat signingReport
```

The output is long. Find the block for **`Variant: debug`** under **`> Task :app:signingReport`** and copy the value after **`SHA1:`**. It looks like `AB:CD:12:...` (20 pairs separated by colons).

**Option B: `keytool`** (use this if Gradle complains that `JAVA_HOME` isn't set). These commands use the Java runtime bundled with Android Studio at its default install location:

macOS:

```bash
"/Applications/Android Studio.app/Contents/jbr/Contents/Home/bin/keytool" -list -v \
  -keystore ~/.android/debug.keystore -alias androiddebugkey \
  -storepass android -keypass android
```

Windows (PowerShell):

```powershell
& "C:\Program Files\Android\Android Studio\jbr\bin\keytool.exe" -list -v `
  -keystore "$env:USERPROFILE\.android\debug.keystore" -alias androiddebugkey `
  -storepass android -keypass android
```

Copy the line labelled **`SHA1:`**. (`android` is the standard, public password for every debug keystore. It is not a secret.)

#### 3.7 Restrict your API key

Restricting the key means that even if it leaked, it would only work for our app on your computer.

1. Go back to **APIs & Services > Credentials** and click your key's name.
2. Under **Application restrictions**, choose **Android apps**, then click **+ Add**:
   - **Package name:** `com.frame_walk.app`
   - **SHA-1 certificate fingerprint:** the SHA-1 you copied in step 3.6
3. Under **API restrictions**, choose **Restrict key** and select only **Maps SDK for Android**.
4. Click **Save**. Changes can take a few minutes to take effect.

#### 3.8 Add the key to your local configuration

The project reads the key from **`frame_walk/android/local.properties`**. Don't put it anywhere else (not in `AndroidManifest.xml`, not in Dart code).

1. Open `frame_walk/android/local.properties`. Flutter created it in step 2.4, and it already contains lines like `sdk.dir=...` and `flutter.sdk=...`. **Leave those lines as they are.**
2. Add this line at the bottom, using your own key:

   ```properties
   MAPS_API_KEY=AIzaYourOwnKeyGoesHere
   ```

   - No quotes, no spaces inside the key, and the name must be exactly `MAPS_API_KEY`.
3. Save the file and fully rebuild. Hot reload/restart is **not** enough, because the key is baked in at build time:

   ```bash
   flutter clean
   flutter run
   ```

4. Open the **Map** tab. You should see a map centered on the UW campus.

### 4. API Key Security

**Where your key lives:** only in `frame_walk/android/local.properties` on your own computer. `frame_walk/android/.gitignore` contains `/local.properties`, so Git ignores it.

**Safe to commit** (the shared configuration; no secrets in them):

- `frame_walk/android/app/build.gradle.kts`
- `frame_walk/android/app/src/main/AndroidManifest.xml` (it only contains the placeholder `${MAPS_API_KEY}`, never a real key)
- `frame_walk/pubspec.yaml`, `frame_walk/pubspec.lock`

**Never commit:**

- `frame_walk/android/local.properties`
- anything containing a real key (text starting with `AIza`), except the Firebase client config files listed in [Firebase Setup](#firebase-setup)
- keystores (`*.keystore`, `*.jks`) or `key.properties`

**Check before you push.** Run these from the `frame_walk` folder (they work on both macOS and Windows):

```bash
# Should print the .gitignore rule that ignores it. If it prints nothing, STOP and ask the team.
git check-ignore -v android/local.properties

# Should only list the Firebase client config files. Any other output means a key is in a tracked file.
git grep -n "AIza"

# Review exactly what you're about to commit.
git status
git diff --staged
```

Never use `git add -f` on `local.properties`. If a key ever does get pushed, deleting the file isn't enough: go to **APIs & Services > Credentials**, **delete or regenerate** that key, and create a new one.

**One key per teammate:** each person uses their own Google Cloud key restricted to their own SHA-1. Your SHA-1 comes from your own debug keystore, so a teammate's key won't work on your machine (and shouldn't).

### 5. Troubleshooting

**`flutter doctor` reports missing dependencies**

- *"cmdline-tools component is missing"*: install **Android SDK Command-line Tools (latest)** in SDK Manager (step 1.2).
- *"Android license status unknown"*: run `flutter doctor --android-licenses` and accept all.
- *"Unable to locate Android SDK"*: open Android Studio once to finish the Setup Wizard, or run `flutter config --android-sdk <path>`. The default SDK path is `~/Library/Android/sdk` on macOS and `%LOCALAPPDATA%\Android\Sdk` on Windows.
- Run `flutter doctor -v` for full details.

**Emulator doesn't appear in `flutter devices`**

- Make sure the emulator has fully booted to the home screen, then run `flutter devices` again.
- Restart the connection with `adb kill-server` and then `adb devices`. If `adb` isn't found, it's in the SDK's `platform-tools` folder.
- Windows: if the emulator won't launch at all, see the virtualization notes in step 1.4.
- Make sure your system image matches your CPU: **arm64** on Apple-silicon Macs, **x86_64** on Windows and Intel Macs.

**Gradle build fails**

- *"flutter.sdk not set in local.properties"*: `android/local.properties` is missing or was created by hand. Delete it, run `flutter pub get` and then `flutter build apk --debug` to regenerate it, and re-add your `MAPS_API_KEY` line.
- *"Could not reserve enough space for object heap"* or the Gradle daemon crashing: `frame_walk/android/gradle.properties` gives Gradle up to 8 GB of memory (`-Xmx8G`). Close other apps and retry. If your computer has less RAM than that, tell the team rather than editing the shared file.
- *JDK / Java version errors*: Flutter should use the JDK bundled with Android Studio. Check which Java it's using with `flutter doctor -v`. If needed, run `flutter config --jdk-dir <path>`, using `/Applications/Android Studio.app/Contents/jbr/Contents/Home` on macOS or `C:\Program Files\Android\Android Studio\jbr` on Windows.
- *`./gradlew` or `.\gradlew.bat` not found*: the wrapper is gitignored and generated by Flutter. Run `flutter build apk --debug` once from `frame_walk` first.
- Anything else: run `flutter clean`, then `flutter pub get`, then try again.

**Map tab is blank or gray (UI loads but no map tiles)**

- Your system image may lack Google Play Services. Check that the emulator's image says **Google Play** or **Google APIs** (step 1.4).
- `MAPS_API_KEY` may be missing or misspelled in `android/local.properties`. The build still succeeds with no key, but the map stays blank.
- You may have edited `local.properties` without rebuilding. Run `flutter clean` and `flutter run`.
- The **Maps SDK for Android** may not be enabled, or billing may not be set up on your Google Cloud project (steps 3.2–3.3).
- The emulator may have no internet. Open Chrome in the emulator to check.

**API key authorization errors**

Watch the logs while you open the Map tab. Use the **Logcat** tool window in Android Studio, or the output of `flutter run`, and look for `Google Android Maps SDK` messages such as `Authorization failure` or `API key not found`.

- *`API key not found`*: the key isn't reaching the manifest. Recheck step 3.8.
- *`Authorization failure`*: the log usually prints the exact package name and SHA-1 your app is using, e.g. `Android Application (<cert_fingerprint>;<package_name>): XX:XX:...;com.frame_walk.app`. Compare both values with your key's restriction in Google Cloud.
- If you just changed key restrictions, wait about 5 minutes and try again.
- *"This API project is not authorized to use this API"*: enable **Maps SDK for Android** (step 3.3) and make sure the key's API restriction includes it.

**Wrong package name or SHA-1 fingerprint**

- The package name in your key restriction must be exactly `com.frame_walk.app`, with an underscore and no typos.
- The SHA-1 must be from **your** computer's debug keystore (step 3.6), not a teammate's. If you reinstall Android Studio or delete `~/.android` (`%USERPROFILE%\.android` on Windows), a new keystore is generated and you'll need to add the new SHA-1 to your key.
- Make sure you copied the **SHA-1** value, not SHA-256 or MD5.

**Missing local configuration files**

- `android/local.properties`, `android/gradlew`, and `android/gradlew.bat` are intentionally **not** in Git. A fresh clone won't have them. Run `flutter pub get` and then `flutter build apk --debug` from `frame_walk` to generate them, then add your `MAPS_API_KEY` line (step 3.8).
- Running `flutter clean` does **not** delete `local.properties`, so your key line stays.

## iOS Setup

iOS builds need a Mac with Xcode (from the App Store) and CocoaPods (`brew install cocoapods`). Check them with `flutter doctor`. Firebase is already set up for iOS (`ios/Runner/GoogleService-Info.plist` and `lib/firebase_options.dart`), so only Google Maps needs per-developer setup.

| What | Value / location |
| --- | --- |
| iOS bundle ID | `com.jltrinh.frameWalk` (Xcode: Runner > Signing & Capabilities). It differs from the Android ID because iOS doesn't allow `_` in bundle IDs. |
| Where your iOS Maps key goes | `MAPS_API_KEY=...` in `frame_walk/ios/Flutter/Secrets.xcconfig`, which is not committed (ignored by `frame_walk/ios/.gitignore`) |
| How the key reaches the app | `Debug.xcconfig`/`Release.xcconfig` include `Secrets.xcconfig` > `Info.plist` (`GMSApiKey`) > `AppDelegate.swift` calls `GMSServices.provideAPIKey` |

### Google Maps key for iOS

Your Android key can't be reused: it's restricted to Android apps and the Maps SDK for Android. Make a second key in the **same** Google Cloud project (billing is already set up there).

1. In **APIs & Services > Library**, enable **Maps SDK for iOS**.
2. In **APIs & Services > Credentials**, click **+ Create credentials > API key**.
3. Restrict it: under **Application restrictions** choose **iOS apps** and add `com.jltrinh.frameWalk`; under **API restrictions** choose **Maps SDK for iOS** only. Click **Save**.
4. Create `frame_walk/ios/Flutter/Secrets.xcconfig` containing one line, with no quotes:

   ```properties
   MAPS_API_KEY=AIzaYourOwnIosKeyGoesHere
   ```

5. Confirm Git ignores it (from `frame_walk`): `git check-ignore -v ios/Flutter/Secrets.xcconfig` should print the rule. If it prints nothing, **stop** and ask the team.

Without `Secrets.xcconfig` the app still builds and runs, but maps are blank, the same as Android without a key. The Xcode console shows `MAPS_API_KEY is not set`.

### Running on iOS

From `frame_walk`:

```bash
open -a Simulator
flutter run -d ios
```

- **Simulator:** no Apple account is needed. To fake a location, use the Simulator menu **Features > Location > Custom Location** (for example Red Square, `47.6559, -122.3078`). To simulate walking, run the app from Xcode (`open ios/Runner.xcworkspace`) and use **Debug > Simulate Location** with a GPX file.
- **Physical iPhone:** the project is signed with the team that registered `com.jltrinh.frameWalk`. Ask that teammate to add you to their Apple Developer team, then select that team in Xcode under **Runner > Signing & Capabilities**. Turn on **Developer Mode** on the phone (**Settings > Privacy & Security > Developer Mode**). If you choose a different team locally, don't commit the resulting `project.pbxproj` change.

### iOS differences

- **Location is foreground only**, as on Android. No background mode is set. iOS doesn't let apps open the device-wide Location Services switch, so if it's off the app explains where to turn it on (**Settings > Privacy & Security > Location Services**).
- **Automatic GPS pausing is off** (`pauseLocationUpdatesAutomatically: false` in `location_source.dart`). iOS doesn't resume paused updates on its own, and walkers often stand still at photo stops.
- The Map tab has no zoom buttons on iOS, because the iOS Maps SDK has none. Pinch to zoom instead.
- On iOS, Firebase keeps the login in the Keychain, so a user may still be logged in after deleting and reinstalling the app.

## Firebase Setup

Login and account data use one Firebase project shared by the whole team: Firebase Auth for email and password sign-in, and Cloud Firestore for account data. Unlike the Maps key, **teammates don't need their own setup**. The config is committed, so `flutter pub get` and `flutter run` are enough.

**Committed config:** these files contain a Firebase API key starting with `AIza`. That's expected, because this key identifies the project rather than granting access. Access to data is controlled by `frame_walk/firestore.rules`. These are the only files allowed to contain `AIza`:

- `frame_walk/lib/firebase_options.dart`
- `frame_walk/android/app/google-services.json`
- `frame_walk/ios/Runner/GoogleService-Info.plist`

**Firestore collections:**

| Collection | Document ID | Contents |
| --- | --- | --- |
| `users` | Firebase Auth user ID | Username, email, statistics, and created date. Readable only by that user. |
| `usernames` | Lowercase username | The owner's user ID. Keeps usernames unique. |
| `users/{uid}/walks` | Generated walk ID | One walk of a route: route ID and title, status (`active` or `completed`), start and completion times, a copy of the route's stops (ID, name, coordinates, prompt, time reached), distance walked. Cancelled walks are deleted. |
| `users/{uid}/walks/{walkId}/locationPoints` | `p000000`, `p000001`, ... | GPS history for a walk: latitude, longitude, accuracy, and time recorded. |

Passwords are handled by Firebase Auth and are never stored in Firestore.

**If you change `firestore.rules`,** deploy them. This requires the [Firebase CLI](https://firebase.google.com/docs/cli) and access to the project:

```bash
cd frame_walk
firebase deploy --only firestore:rules
```

**If an app ID changes or a platform is added,** regenerate the config with the [FlutterFire CLI](https://firebase.google.com/docs/flutter/setup) by running `flutterfire configure` from `frame_walk`, then commit the result.

**Running the auth tests** (they use fakes, so they don't touch the real project):

```bash
cd frame_walk
flutter test test/backend/services/auth_service_test.dart test/frontend/auth_flow_test.dart
```


## GPS Tracking

Pressing **Start Walk** on a route opens the active-walk screen, which records where the user walks and tells them when they approach (within 75 m) or reach (within 25 m) each stop.

| Piece | File |
| --- | --- |
| Device location (the only code that uses `geolocator`) | `lib/backend/services/location_source.dart` |
| Stop proximity and route progress | `lib/backend/services/route_progress_tracker.dart` |
| Firestore storage | `lib/backend/services/walk_repository.dart` |
| Starts/stops tracking, handles permission and signal problems | `lib/backend/services/walk_tracking_service.dart` |
| Screen | `lib/frontend/screens/active_walk_page.dart` |

**Routes vs. Walked-Routes:** predefined routes are not stored with walks. A walk refers to its route by `routeId` and keeps its own copy of the stops. Only walks with `status: completed` are Walked-Routes.

**Foreground only.** Location is recorded only while FrameWalk is open on screen. When the app goes to the background or the screen locks, tracking pauses and resumes when the user returns. The gap shows up in the location history timestamps. Background tracking would need, at minimum, a location foreground service (`FOREGROUND_SERVICE` and `FOREGROUND_SERVICE_LOCATION` permissions, `POST_NOTIFICATIONS` on Android 13+, and a `foregroundNotificationConfig` in `AndroidSettings`) on Android, and the `location` background mode on iOS. None of these are set up.

**Battery:** high accuracy with a 10 m distance filter (a 5 s minimum interval on Android), so no readings arrive while standing still. Points are saved to Firestore in batches of 10, or every 30 seconds.

**Permissions:** the app asks for "while using the app" location when a walk starts. If permission is denied, location services are off, or only approximate location is allowed, the screen explains why and links to the right settings. If the GPS signal drops mid-walk, the walk keeps going and a banner shows the problem.

**Testing on an emulator:** open the emulator's **Extended controls (⋯) > Location** and set a point near a stop (for example Red Square, `47.6559, -122.3078`), or play back a route.

## Walk Photos

After a walk is completed, users can add photos to it and tag each one with a prompt from that walk, or with "No prompt". Image files go in Firebase Storage. Their metadata and prompt association go in Firestore.

```
Firestore: users/{uid}/walks/{walkedRouteId}/photos/{photoId}
           photoId, userId, walkedRouteId, storagePath, stopId (null = No prompt),
           uploadedAt, updatedAt, contentType, sizeBytes
Storage:   users/{uid}/walkedRoutes/{walkedRouteId}/photos/{photoId}
```

| Piece | File |
| --- | --- |
| API for the frontend (`WalkPhotoService`, `PhotoChangeSet`, `PhotoSaveResult`) | `lib/backend/services/walk_photo_service.dart` |
| Models (`WalkPhoto`, `WalkPrompt`, `PendingPhoto`, `WalkPhotoGallery`) | `lib/models/walk_photo.dart` |
| Storage access (the only code that uses `firebase_storage`) | `lib/backend/services/photo_storage.dart` |
| Image type and size checks | `lib/backend/services/image_validation.dart` |
| Rules | `firestore.rules`, `storage.rules` |

**Associations** come only from the `stopId` the user picks, never from photo time, GPS, EXIF data, or prompt text. Prompts come from the walk's own `WalkedStop`s, so separate walks of the same route never mix.

**Editing flow:** stage edits locally in a `PhotoChangeSet` (`add`, `setStop`, `remove`). Nothing is uploaded until `saveChanges`. That call uploads new files, then writes metadata and association changes in one batch, then processes deletions. If anything fails, `result.remaining` holds exactly what still needs saving.

**Limits:** JPEG, PNG, HEIC/HEIF, and WebP, up to 20 MB, checked by file contents. The backend doesn't recompress photos. To speed up uploads, ask the picker for a smaller image.

**Deploying the rules** (Storage must be enabled in the Firebase console first). On the first deploy, the CLI offers to let Storage rules read Firestore. Accept, because `storage.rules` checks that the walk exists and is completed:

```bash
cd frame_walk
firebase deploy --only firestore:rules,storage
```

**Tests:** `test/backend/services/walk_photo_service_test.dart` uses fakes and runs with `flutter test`. `integration_test/walk_photo_service_emulator_test.dart` runs the real SDKs against the Firebase emulators (needs Java 21+) on a `demo-` project, so it never touches the real one:

```bash
cd frame_walk
firebase emulators:exec --project demo-framewalk --only auth,firestore,storage \
  "flutter test integration_test/walk_photo_service_emulator_test.dart -d <device-id>"
```

**Test UI (temporary, for the frontend team to replace):** Activity > Previous Walks lists completed walks (`lib/frontend/widgets/completed_walks_list.dart`). Tapping one opens `walk_gallery_page.dart`, which shows photos grouped by prompt plus "No prompt". **Add photos** opens `walk_photo_editor_page.dart`, where you pick, tag, and remove photos, then Save, with progress and retry. These screens only call `WalkPhotoService`, so they can be restyled or rewritten without backend changes. `image_picker` is wrapped in `lib/frontend/utils/photo_picker.dart`, and thumbnails load lazily through `lib/frontend/widgets/walk_photo_thumbnail.dart`.

## Links

- [Living Document](https://docs.google.com/document/d/1lYug-M3YyP1dTDqYPlPpnL4UAtH1hgJSdiU_M_lnueI/edit?tab=t.0)
- [Figma](https://www.figma.com/design/9afJm17FYCXVwcnU6hJhCi/CSE-403?node-id=0-1&m=dev&t=1FsT888g7EucfzPl-1)
