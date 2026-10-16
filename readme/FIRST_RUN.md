# Local development setup

[English](./FIRST_RUN.md) · [简体中文](./FIRST_RUN.zh_CN.md) · [Русский](./FIRST_RUN.ru.md)

Prepare one target for Flutter Debug. Packaging and store deployment belong in
[Build and release](../build_scripts/README.md), not this setup procedure.

## 1. Tools and checkouts

Install Flutter stable with a Dart SDK satisfying [pubspec.yaml](../pubspec.yaml),
Git, Python 3.12+, Go matching libXray's `go.mod`, and LLVM/libclang for FFI.
Add Flutter, Go and Go-installed tools (`GOBIN`, or `GOPATH/bin`) to `PATH`.

| Target | Additional requirements |
| --- | --- |
| iOS / macOS | macOS, full Xcode and the target SDK/simulator runtime. |
| Android | Android SDK/NDK from [Gradle configuration](../android/app/build.gradle.kts), and a JDK compatible with the [Gradle wrapper](../android/gradle/wrapper/gradle-wrapper.properties). Set `ANDROID_HOME` and `ANDROID_NDK_HOME`. |
| Linux | Native Linux toolchain and GTK/plugin packages below. |
| Windows | Native Windows, Visual Studio C++ tools, Windows SDK, Rust, `uv`, and matching-architecture Go/C compiler tools; see [Windows preparation](../build_scripts/README.md#windows). |

From your workspace, clone only missing repositories:

```shell
git clone https://github.com/YuanDevTeam/OneXray.git
git clone https://github.com/XTLS/libXray.git
cd OneXray
```

Keep them as siblings; Windows also needs Vole (see [checkout layout](../build_scripts/README.md#prepare-the-workspace)). All commands
below start in the App root. Use compatible dependency revisions from the
[Build workflow](../.github/workflows/build.yml); a separate Xray-core checkout
is unnecessary. Check `flutter doctor -v` before continuing. Run Flutter/Dart
commands serially; stop an active `flutter run` before generation/checks.

## 2. Native libraries and Geodata

Run only your platform's preparation. These libXray commands prepare native
artifacts and `../libXray/dat/`; they do not publish the App.

### iOS / macOS

```shell
python3 ../libXray/build/main.py apple go
rsync -a --delete ../libXray/LibXray.xcframework/ swift/All/LibXray.xcframework/
```

Replace only this generated framework, not the rest of `swift/All/`. Apple
projects use SwiftPM, with no Podfile setup or `pod install`. Flutter prepares
its plugin package; if globally disabled, use
`flutter config --enable-swift-package-manager`.

### Android

```shell
python3 ../libXray/build/main.py android
mkdir -p android/app/libs
cp ../libXray/libXray.aar ../libXray/libXray-sources.jar android/app/libs/
```

Use PowerShell equivalents on Windows. The App supports arm64-v8a/x86_64;
local Debug uses the debug keystore, not Play upload credentials.

### Linux

On Debian/Ubuntu:

```shell
sudo apt-get install -y build-essential clang libclang-dev cmake ninja-build pkg-config libgtk-3-dev liblzma-dev libblkid-dev libsecret-1-dev libayatana-appindicator3-dev libcap2-bin procps file
python3 ../libXray/build/main.py linux
mkdir -p linux/app
cp ../libXray/linux_so/libXray.so linux/app/
cp ../libXray/bin/xray linux/app/OneXrayCore
chmod +x linux/app/OneXrayCore
```

### Windows

Prepare the complete native bundle using [the build guide](../build_scripts/README.md#windows).
Copying only libXray is insufficient: the current bundle also includes Core, Wintun and Vole.
Once `windows/app/` is ready, ordinary Debug uses EXE mode.

### Copy the complete Geodata directory

Manual builds must copy indexes and timestamp along with the `.dat` files:

```shell
mkdir -p assets/dat
cp -R ../libXray/dat/. assets/dat/
```

PowerShell: `New-Item -ItemType Directory -Force assets/dat`, then
`Copy-Item ../libXray/dat/* assets/dat/ -Force`. The directory is Git-ignored;
a fresh clone needs these bundled defaults. App packaging already copies it.
Native artifact architecture must match the App.

## 3. Generate and run

```shell
flutter pub get
flutter gen-l10n
dart run tool/ffigen.dart
flutter devices
flutter run -d DEVICE_ID
```

Replace `DEVICE_ID` with the actual device, or `macos` / `windows` on those hosts.
Localization and FFI outputs are Git-ignored; generate them even for Apple/Android
because shared Dart imports them. FFI headers/configuration are in `pubspec.yaml`.
Checked-in model/database/asset/Pigeon outputs need regeneration only after their
sources change.

- Apple signing: align Runner/tunnel Bundle IDs, App Groups and
  [Swift identifiers](../swift/All/Constants.swift) with your own team. Real
  devices need development signing and Network Extension capabilities.
- iOS Simulator uses Swift's local SOCKS adaptation and skips VPN authorization;
  this is not real system-VPN acceptance.
- Linux: first build Debug and grant the actual Core network capabilities:
  ```shell
  flutter build linux --debug
  sudo setcap cap_net_admin,cap_net_raw+eip build/linux/x64/debug/bundle/OneXrayCore
  flutter run -d linux --no-enable-impeller
  ```
  Use `arm64` on ARM64; reapply capabilities when rebuilding replaces Core.
- Windows MSIX requires an installed, signed development package and its identity;
  follow [development signing](../build_scripts/README.md#msix-and-development-signing),
  not a bare EXE or `msix:create` shortcut.

## 4. After changes

| Source | Regenerate |
| --- | --- |
| ARB | `flutter gen-l10n` |
| JSON/Drift models or declared assets | `dart run build_runner build --delete-conflicting-outputs` |
| `pigeon/message.dart` | `dart run pigeon --input pigeon/message.dart` |
| FFI headers/configuration | `dart run tool/ffigen.dart` |

Replace rebuilt native libraries and fully relaunch; hot reload cannot replace
them. Keep isolated test data in workspace `references/`, not your main database.
See [App](../docs/app.md), [Validation](../docs/validation.md) and
[External interfaces](../docs/external-interfaces.md) for the relevant contracts.
Ordinary Debug does not need `BUILD_NUMBER`, Fastlane or store-upload credentials;
platform development signing is separate. For packaging, use the build guide.

[Back to README](../README.md)
