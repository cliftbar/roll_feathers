Create and use one stable Android release keystore so every APK/AAB for `site.cliftbar.roll_feathers` is signed with the same certificate locally and in GitHub Actions. This lets users upgrade without uninstalling.

---

### Step 1 — Generate a release keystore (one time)
Run on your Mac (or a secure machine). Pick strong passwords and write them down.
```bash
# From the repo root (or any secure directory)
keytool -genkeypair \
  -v \
  -keystore rollfeathers-release.keystore \
  -alias rollfeathers \
  -keyalg RSA -keysize 2048 \
  -validity 10000
```
You’ll be prompted for:
- Keystore password (storePassword)
- First/Last name, etc. (DN info)
- Key password (keyPassword; can match store password)

Files created:
- `rollfeathers-release.keystore` (guard this file)
- Your alias: `rollfeathers`

---

### Step 2 — Back it up securely
- Store the keystore and the four secrets in a password manager/vault:
  - `ANDROID_KEYSTORE` → the keystore file itself
  - `ANDROID_KEYSTORE_PASSWORD` → store password
  - `ANDROID_KEY_ALIAS` → `rollfeathers`
  - `ANDROID_KEY_PASSWORD` → key password
    Losing the keystore means you can’t update existing installs.

---

### Step 3 — Prepare your project to use Gradle-properties–driven signing (preferred)
Edit `android/app/build.gradle.kts` to add a proper `release` signing config and use it for release builds. Prefer user-level Gradle properties, with environment variables as a fallback.

Current snippet (to remove/change):
```kotlin
buildTypes {
    release {
        // Signing with the debug keys for now, so `flutter run --release` works.
        signingConfig = signingConfigs.getByName("debug")
    }
}
```

Replace with this (add the `signingConfigs.release` and point release to it). This version reads values from `~/.gradle/gradle.properties` first, then falls back to environment variables, then to a repo-local path for convenience:
```kotlin
android {
    // ... existing config ...

    signingConfigs {
        create("release") {
            fun prop(name: String): String? = providers.gradleProperty(name).orNull
            val ksPath = prop("ANDROID_KEYSTORE")
                ?: System.getenv("ANDROID_KEYSTORE")
                ?: "android/keystore/rollfeathers-release.keystore" // optional fallback
            storeFile = file(ksPath)
            storePassword = prop("ANDROID_KEYSTORE_PASSWORD") ?: System.getenv("ANDROID_KEYSTORE_PASSWORD")
            keyAlias = prop("ANDROID_KEY_ALIAS") ?: System.getenv("ANDROID_KEY_ALIAS")
            keyPassword = prop("ANDROID_KEY_PASSWORD") ?: System.getenv("ANDROID_KEY_PASSWORD")
        }
    }

    buildTypes {
        release {
            isMinifyEnabled = false
            signingConfig = signingConfigs.getByName("release")
        }
        debug {
            // Optional: make debug installable alongside release
            applicationIdSuffix = ".debug"
        }
    }
}
```
Commit this change.

---

### Step 4 — (Optional) Place the keystore in the repo for local use
Safer approach is to keep it out of the repo. If you prefer local convenience:
```bash
mkdir -p android/keystore
mv /path/to/rollfeathers-release.keystore android/keystore/
```

---

### Step 5 — Configure local credentials using Gradle properties (recommended)
Put these in your user-level `~/.gradle/gradle.properties` (not committed to VCS):
```
ANDROID_KEYSTORE=/absolute/path/to/android/keystore/rollfeathers-release.keystore
ANDROID_KEYSTORE_PASSWORD=<store-pass>
ANDROID_KEY_ALIAS=rollfeathers
ANDROID_KEY_PASSWORD=<key-pass>
```
Alternative (if you prefer env vars locally):
```bash
export ANDROID_KEYSTORE="$PWD/android/keystore/rollfeathers-release.keystore"   # adjust path
export ANDROID_KEYSTORE_PASSWORD="<store-pass>"
export ANDROID_KEY_ALIAS="rollfeathers"
export ANDROID_KEY_PASSWORD="<key-pass>"
```
Using Gradle properties avoids leaking secrets into your global shell environment and works seamlessly from the IDE.

---

### Step 6 — Build locally and verify
```bash
flutter clean
flutter pub get
flutter build apk --release --build-number 1
flutter build appbundle --release --build-number 1
```
Verify signature (pick your build-tools version):
```bash
$ANDROID_SDK_ROOT/build-tools/34.0.0/apksigner verify --print-certs build/app/outputs/flutter-apk/app-release.apk
```
Confirm the certificate SHA-256 digest. Save it; future builds should match.

---

### Step 7 — Add secrets to GitHub Actions
Create secrets in GitHub → Settings → Secrets and variables → Actions:
- `ANDROID_KEYSTORE_B64` → base64 of the keystore file
  ```bash
  # macOS: create a one-line base64
  base64 < android/keystore/rollfeathers-release.keystore > keystore.b64
  # Open keystore.b64 and ensure it’s a single line (no spaces/newlines added in copy)
  ```
- `ANDROID_KEYSTORE_PASSWORD`
- `ANDROID_KEY_ALIAS` → `rollfeathers`
- `ANDROID_KEY_PASSWORD`

---

### Step 8 — Update your workflow to use the release keystore
Edit `.github/workflows/tagged_release.yaml` in the `build-macos-mobile` job to restore the keystore and export env vars before building.

Add these steps before the Android builds:
```yaml
      - name: Prepare Android signing
        run: |
          mkdir -p android/keystore
          echo "$ANDROID_KEYSTORE_B64" | base64 --decode > android/keystore/rollfeathers-release.keystore
        env:
          ANDROID_KEYSTORE_B64: ${{ secrets.ANDROID_KEYSTORE_B64 }}

      - name: Build Android (signed)
        env:
          ANDROID_KEYSTORE: ${{ github.workspace }}/android/keystore/rollfeathers-release.keystore
          ANDROID_KEYSTORE_PASSWORD: ${{ secrets.ANDROID_KEYSTORE_PASSWORD }}
          ANDROID_KEY_ALIAS: ${{ secrets.ANDROID_KEY_ALIAS }}
          ANDROID_KEY_PASSWORD: ${{ secrets.ANDROID_KEY_PASSWORD }}
        run: |
          flutter build apk --release --build-number "$GITHUB_RUN_NUMBER"
          flutter build appbundle --release --build-number "$GITHUB_RUN_NUMBER"
```
Then keep your rename/upload steps as you already have, or use the robust renaming we discussed earlier.

Note: Your current workflow builds Android before macOS. Insert the two steps right before `flutter build apk --release` and `flutter build appbundle --release` so those builds use the release key.

---

### Step 9 — Keep `versionCode` increasing
Your `build.gradle.kts` uses `versionCode = flutter.versionCode`. In CI, pass an ever-increasing integer:
```yaml
flutter build apk --release --build-number "$GITHUB_RUN_NUMBER"
flutter build appbundle --release --build-number "$GITHUB_RUN_NUMBER"
```
This prevents `INSTALL_FAILED_VERSION_DOWNGRADE` during updates.

---

### Step 10 — Install/update behavior on devices
- If the device currently has a build signed with a different key (e.g., a debug build from your Mac), you must uninstall that first:
  ```bash
  adb uninstall site.cliftbar.roll_feathers
  ```
- After you adopt the release key, all future APKs/AABs signed with the same key will update in place.
- If a user installed from Google Play, they cannot side‑load your GitHub APK over it (Play uses Google’s signing key). Use Play for testers in that case.

---

### Step 11 — (Optional) Enroll in Play App Signing
If/when you publish to Play:
- Enroll in Play App Signing (recommended). Your AAB will be signed with your upload key (the one you created) and Google will re-sign for distribution.
- Keep the same upload key forever (or follow Play’s key-rotation procedure).

---

### Step 12 — Confirm everything end-to-end
1) Push a tag to trigger the workflow:
```bash
git tag v0.10.13
git push origin v0.10.13
```
2) When the release is ready, download the APK from GitHub Releases.
3) Install it on a device that doesn’t have a mismatched build:
```bash
adb install -r path/to/roll_feathers-v0.10.13-release.apk
```
4) If you later rebuild, verify `apksigner --print-certs` matches the same SHA‑256.

---

### Quick checklist
- Keystore generated and backed up
- `build.gradle.kts` uses `signingConfigs.release` for `release`
- Gradle properties set in `~/.gradle/gradle.properties` (or env vars/fallback path available)
- CI: secrets added + keystore restored + env exported
- Android builds pass `--build-number` with a monotonic value
- APK/AAB signatures verified with `apksigner`
- Old mismatched installs uninstalled before installing the new, consistently-signed APK

If you want, I can provide a ready-to-commit diff for `android/app/build.gradle.kts` and a patch for your `tagged_release.yaml` with the signing steps inserted in the right place.