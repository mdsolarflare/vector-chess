# Store Release & Runner Guide

This repository uses [`.github/workflows/release.yml`](../.github/workflows/release.yml) to build, sign, and publish store-ready packages for **Steam (Windows, Linux/Steam Deck, macOS)**, **Google Play (Android)**, and **Apple App Store / TestFlight (iOS)**.

## 1. Triggering a Release

* **Tag Release (Full Pipeline + GitHub Release):**
  ```bash
  git tag v0.2.0
  git push origin v0.2.0
  ```
* **Manual Dry-Run / Test Build:**
  Go to **Actions → Store Release Pipeline → Run workflow**. Even before any store secrets are configured, the workflow builds all packages (using ephemeral/ad-hoc signing) so you can verify and download artifacts.

---

## 2. Setting Up Your ARM Mac Mini Runner

> **Important Note on Podman on macOS:**
> On Apple Silicon Macs, **Podman runs a Linux kernel VM** (`aarch64-linux`). Because Apple's `xcodebuild`, `codesign`, `security`, and `notarytool` binaries only exist on Darwin/macOS—and Apple's EULA & kernel frameworks forbid macOS-inside-Linux containers—a Podman container **cannot** sign macOS `.app` bundles or build iOS `.ipa` packages.
>
> For isolated, container-like Apple builds on your ARM Mac Mini, use one of these two approaches instead:
> 1. **[Tart](https://tart.run/) (`brew install cirruslabs/cli/tart`)** — Pulls and runs ephemeral macOS Sonoma/Sequoia VMs using OCI syntax (`tart clone`, `tart run`) directly on Apple's `Virtualization.framework` at near-native speed.
> 2. **Dedicated unprivileged macOS user account** — Create a standard non-admin user (e.g. `ghrunner`) on the Mac Mini and install the GitHub Actions launch agent under that user.

### Runner Registration Steps (on macOS Host or Tart macOS VM)
1. Install **Xcode** from the Mac App Store, then initialize CLI tools:
   ```bash
   sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
   sudo xcodebuild -license accept
   sudo xcodebuild -runFirstLaunch
   ```
2. In GitHub, open **Settings → Actions → Runners → New self-hosted runner**, select **macOS** and **ARM64**, and run the provided `./config.sh` and `./svc.sh install && ./svc.sh start` commands.
3. In GitHub **Settings → Secrets and variables → Actions → Variables**, add:
   * `USE_SELF_HOSTED_MAC` = `true`
   *(When unset or `false`, `build-apple` defaults to GitHub's hosted `macos-latest` runner.)*

---

## 3. GitHub Variables & Secrets Reference

### A. Android — Google Play Store (`.aab`)
Generate an Upload Keystore once on any machine with Java installed:
```bash
keytool -genkeypair -v -keystore vector-chess-upload.keystore \
  -alias vectorchess -keyalg RSA -keysize 2048 -validity 10000
base64 -i vector-chess-upload.keystore > keystore.b64
```

| Type | Name | Description |
| :--- | :--- | :--- |
| Secret | `ANDROID_KEYSTORE_BASE64` | Base64-encoded contents of `vector-chess-upload.keystore` |
| Secret | `ANDROID_KEYSTORE_USER` | Key alias (e.g. `vectorchess`) |
| Secret | `ANDROID_KEYSTORE_PASSWORD` | Keystore & key password |
| Secret | `GOOGLE_PLAY_SERVICE_ACCOUNT_JSON` | *(Optional)* Google Cloud Service Account JSON with Play Console release access for automatic upload to the `internal` track |

---

### B. Apple — macOS (Steam) & iOS (App Store / TestFlight)
Export signing certificates as `.p12` files from Keychain Access and base64-encode them (`base64 -i cert.p12`). Create an App Store Connect API Key (`.p8`) under **App Store Connect → Users and Access → Integrations → App Store Connect API**.

| Type | Name | Description |
| :--- | :--- | :--- |
| Secret | `APPLE_TEAM_ID` | 10-character Apple Developer Team ID (e.g. `ABCDE12XYZ`) |
| Secret | `APPLE_MACOS_CERTIFICATE_BASE64` | Base64 `.p12` of **Developer ID Application** cert (for Steam macOS Gatekeeper) |
| Secret | `APPLE_MACOS_CERTIFICATE_PASSWORD` | Password for the macOS `.p12` export |
| Secret | `APPLE_IOS_CERTIFICATE_BASE64` | Base64 `.p12` of **Apple Distribution** cert (for iOS App Store) |
| Secret | `APPLE_IOS_CERTIFICATE_PASSWORD` | Password for the iOS `.p12` export |
| Secret | `APPLE_IOS_PROVISIONING_PROFILE_BASE64` | Base64 `.mobileprovision` App Store profile for `com.vectorchess.game` |
| Secret | `APPLE_API_KEY_ID` | App Store Connect API Key ID (used for macOS notarization & TestFlight upload) |
| Secret | `APPLE_API_ISSUER_ID` | App Store Connect Issuer UUID |
| Secret | `APPLE_API_PRIVATE_KEY` | Full contents of `AuthKey_<KEY_ID>.p8` |

---

### C. Steam — SteamPipe Multi-Depot Upload
In Steamworks (**SteamPipe → Depots**), create 3 depots (Windows 64-bit, Linux 64-bit, macOS) and link them to your package. To authorize headless `steamcmd` without interactive Steam Guard prompts, log in once locally with a dedicated build account (`steamcmd +login <builder_user> +quit`) and base64-encode the generated `Steam/config/config.vdf`.

| Type | Name | Description |
| :--- | :--- | :--- |
| Variable | `STEAM_APP_ID` | Your Steam App ID (e.g. `1234560`) |
| Variable | `STEAM_DEPOT_WINDOWS` | Windows Depot ID (e.g. `1234561`) |
| Variable | `STEAM_DEPOT_LINUX` | Linux / Steam Deck Depot ID (e.g. `1234562`) |
| Variable | `STEAM_DEPOT_MACOS` | macOS Depot ID (e.g. `1234563`) |
| Secret | `STEAM_USERNAME` | Dedicated Steamworks builder account username |
| Secret | `STEAM_CONFIG_VDF` | Base64-encoded `config.vdf` containing cached login token |
