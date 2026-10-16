# Build and release

This is the packaging guide. Use [FIRST_RUN](../readme/FIRST_RUN.md) for Flutter
Debug and [Validation](../docs/validation.md) for device/channel acceptance.

## Prepare the workspace

Keep `OneXray/` and `libXray/` as sibling checkouts. Windows also needs a compatible
Vole checkout at sibling `Vole/`, workspace `references/Vole/`, or `VOLE_DIR`.
The configured checkout must support custom VPN profiles and the retained Windows
host MTA lifetime. A local commit is not available to CI until published upstream.
Xray-core remains supplied by libXray's Go module.

Install Python 3.12+, `uv`, Flutter/Dart, Go and LLVM/libclang on `PATH`.
Platform tools and CI versions are defined in the [Build workflow](../.github/workflows/build.yml):

| Target | Additional requirements |
| --- | --- |
| Apple | macOS, Xcode, SwiftPM, Fastlane and signing credentials. |
| Android | Android SDK/NDK, compatible JDK, Fastlane and Play credentials; see [Gradle](../android/app/build.gradle.kts). |
| Windows | Native x64/ARM64 host, Visual Studio C++, Windows SDK, Rust and matching Go/C tools. EXE/ZIP also need Dart Fastforge; EXE needs Inno Setup (`INNO_SETUP_PATH`). |
| Linux | Native Linux toolchain, GTK/plugin dependencies and Dart Fastforge. |

From the App root:

```shell
uv sync --project build_scripts
# Only for Linux or Windows EXE/ZIP:
dart pub global activate fastforge
```

Keep `LIBXRAY_REF=main` unless explicitly instructed otherwise. Run Flutter/Dart
commands serially.

## GitHub Actions

Prefer maintained Actions for SDK/tool setup, downloads, artifacts and releases.
Keep scripts for OneXray's build commands, credentials, release policy and native
packaging. Check target architecture support before replacing a setup step.

Use the latest supported major tag for Actions. When upstream does not publish
major or minor aliases, use an available release tag: `setup-uv` currently needs
`v10.3.0` because neither `v10` nor `v10.3` exists. Keep tool versions within the
project's compatibility limits, including Java 26 for the current Gradle wrapper.

| Workload | Runner image |
| --- | --- |
| iOS, Mac App Store and macOS Developer ID | `xcode-27`: macOS 27 ARM64, currently public preview; select the latest stable installed Xcode. |
| Windows x64 builds and Microsoft Store bundling | `windows-2025-vs2026` |
| Windows ARM64 builds | `windows-11-vs2026-arm` |
| Android, validation, metadata, release publishing and WinGet | `ubuntu-26.04` |
| Linux x64 / ARM64 packages | `ubuntu-24.04` / `ubuntu-24.04-arm`, preserving the glibc 2.39 build baseline. |

GitHub's [macOS 27 image](https://github.com/actions/runner-images/blob/main/images/macos/xcode-27-arm64-Readme.md)
uses the `xcode-27` label; `macos-27` is not an available runner label.

| Workflow / jobs | Actions and retained project logic |
| --- | --- |
| [Build](../.github/workflows/build.yml): `release_metadata` | Checkout outputs supply dependency commits; a short script writes the shared run metadata. |
| Build: `ios`, `macos`, `macos_se`, `android`, `windows`, `linux` | Setup Actions provide SDKs and uv; Apple Actions import certificates; release-downloader fetches LLVM-MinGW and Inno Setup; upload-artifact stores packages. Build scripts retain signing, packaging and store uploads. |
| [Validate](../.github/workflows/validate.yml): `dart` | Setup Actions provide Python, uv and Flutter; commands run generation, analysis and project checks. |
| [Publish](../.github/workflows/publish.yml): `pre_release` | download-artifact retrieves the selected run; action-gh-release replaces matching assets. The release verifier selects channel files and checks source metadata. |
| [Microsoft Store](../.github/workflows/publish-microsoft-store.yml): `inspect`, `publish` | Artifact Actions transfer metadata, MSIX packages and the bundle. The verifier checks the Build run; MakeAppx creates the multi-architecture bundle. |
| [WinGet](../.github/workflows/update-winget.yml): `winget` | Rust, uv and cargo-install Actions provide tooling; Komac and the manifest helper retain release checks, generation and submission. |

The shared [Flutter Action](../.github/actions/setup-flutter/action.yml) uses
[subosito/flutter-action](https://github.com/subosito/flutter-action) for macOS
and x64 hosts. Windows/Linux ARM64 have no stable SDK archives in Flutter's
release index, so `actions/checkout` obtains `flutter/flutter@stable` and Flutter
bootstraps its native Dart SDK. Both paths expose `FLUTTER_ROOT`, `PUB_CACHE` and
the Pub executable directory, including Fastforge.

[setup-uv](https://github.com/astral-sh/setup-uv) replaces pip-based installation.
[release-downloader](https://github.com/robinraju/release-downloader) handles
release asset downloads and LLVM-MinGW extraction. Inno Setup remains on the
latest stable 7.x release; its silent installation uses a short PowerShell step.

## Build

Set a positive `BUILD_NUMBER`; the [configured base](app/config.py) is added to it.
Outputs go to sibling `output/`. Use an isolated checkout/output directory.

```shell
export BUILD_NUMBER=1
uv run --project build_scripts python build_scripts/main.py OneXray <system>
```

PowerShell uses `$env:BUILD_NUMBER = "1"`; the build command is otherwise the same.
`--help` lists targets and options.

| `system` | Result / external action |
| --- | --- |
| `ios` | IPA and TestFlight upload. |
| `macos` | Mac App Store package and App Store Connect upload. |
| `macos_se` | Developer ID signed, notarized universal ZIP. |
| `android` | Play internal draft AAB upload and universal APK download. |
| `windows` | EXE + ZIP, or MSIX with `--windows-mode msix`. |
| `linux` | ZIP + DEB for the host architecture. |

**Apple/Android deployment and notarization are not local checks.** The sequence is
version/pub get → native libraries/Core/Geodata → FFI generation → platform build/package.
`pubspec.yaml` is restored on success or failure. Android passes its effective
build number through the environment, without rewriting Fastfile. Linux collects
only the current version's ZIP/DEB.

FFI generation runs `dart run tool/ffigen.dart` after refreshing the native
headers. Use the same command from the App root after changing `c/include/` or
the generator configuration; do not edit the generated bindings manually.

Native outputs and Geodata are refreshed. Apple updates Xcode build numbers;
`macos_se` also replaces `macos/` with `macos_se/`, preserving framework symlinks.
Use a disposable checkout for those operations.

## Windows

`--windows-mode exe|msix` selects both packaging and the compiled runtime; default
is `exe`, never a package-identity fallback. `ONEXRAY_WINDOWS_ARCH=x64|arm64` defaults
to the host and requires matching toolchains.

- **EXE/ZIP:** Xray native TUN/Wintun and current-user Startup shortcut. Fastforge
  builds once for both packages; temporary Inno architecture/version changes are
  restored even on failure. Keep the released installer identity and user scope.
- **MSIX:** Vole UWP Provider and Session Host supervise Core through private SOCKS;
  the package uses `VoleStartup`. Run it installed, not as a bare EXE.
- Both modes currently ship the same native file set via [app.cmake](../windows/app.cmake),
  including target MSVC CRT DLLs. ZIP users must extract the complete bundle.
  Never substitute DLLs from System32.

[windows.py](app/windows.py) builds Vole with `--backend uwp` and copies its runtime
files and public headers from `dist/windows/<arch>/uwp/`. Wintun is extracted for
the selected architecture from its official archive. Missing inputs fail during
copying or CMake installation; compiler and packager failures propagate directly.
There is no additional hash, PE scan, or source-header comparison.

### MSIX and development signing

MSIX uses `msix:build --build-windows false` to generate assets/manifest, adds VPN
activation, then runs MakeAppx **once**. The temporary double-architecture staging
path is required by msix 3.18 and is removed on success/failure. Bare `msix:create`
does not produce the required VPN package.

Store packages remain unsigned with the production identity. Local signing uses
an existing Code Signing certificate in the current user's `My` store:

```powershell
$certificate = Get-Item "Cert:\CurrentUser\My\<thumbprint>"
$env:BUILD_NUMBER = "1"
$env:ONEXRAY_DEV_SIGN = "1"
$env:ONEXRAY_DEV_CERT_THUMBPRINT = $certificate.Thumbprint
$env:ONEXRAY_DEV_PUBLISHER = $certificate.Subject
uv run --project build_scripts python build_scripts/main.py OneXray windows --windows-mode msix
```

The certificate must have its private key. Trust a self-signed public CER on the
test machine through `LocalMachine\TrustedPeople` with normal administrator
approval, not the Root store. Scripts do not manage certificates or accept PFX
passwords. MakeAppx and, for development builds, SignTool must succeed before
replacing an output. Windows checks signature trust on installation.
Set `ONEXRAY_DEV_SIGN=0` for an unsigned Store build.

Development identity `OneXray.Dev` and profile `OneXray Dev` are separate from
Store identity `YuanDevLLC.OneXray` and profile `OneXray`. No old profile or session
token is adopted or renamed automatically; stop an old active profile before switching. EXE/ZIP and
MSIX are different data/upgrade channels; see [App behavior](../docs/app.md).

## Publishing

Build resolves dependency refs once and checks out those commits in every job.
Only lightweight run/source metadata accompanies packages; local builds do not
collect Git status, tool versions, input hashes or per-platform receipts.
[verify_release.py](verify_release.py) checks the selected successful Build run,
release tag/commit and required channel files, without reading package contents.
Retrying failed jobs can retain successful metadata and packages from an earlier
attempt of the same run. The metadata attempt must be positive and no newer than
the selected successful Build attempt; run/source/repository/tag checks still
apply. If rerunning metadata to resolve dependencies again, rerun its dependent
build jobs together.

- [Publish](../.github/workflows/publish.yml) selects GitHub pre-release files,
  excluding Store packages. Stable promotion is separate.
- [Microsoft Store](../.github/workflows/publish-microsoft-store.yml) selects x64
  and ARM64 MSIX files for MakeAppx bundling; Partner Center submission is manual.
- [WinGet](../.github/workflows/update-winget.yml) uses stable published EXE assets.
  [cargo-install](https://github.com/baptiste0928/cargo-install) builds Komac from
  upstream `main` with stable Rust and `locked: true`, using that branch's Cargo
  lockfile. The Action resolves `main` on each run and caches binaries by the
  resolved revision. This includes Inno Setup 7 support missing from Komac 2.16.0.
  The workflow pipes `komac update --dry-run` output through `awk` to save separate
  YAML files by manifest type and locale; dry-run returns before handling `--output`.
  [winget_manifest.py](winget_manifest.py) retains identity, release URL and user
  installation policy checks. Komac supplies the schema-required `InstallerSha256`;
  no extra comparison with GitHub asset digests is performed. Before submission,
  `komac sync-fork` updates the organization fork using the same PAT and
  `KOMAC_FORK_OWNER` as the final submit. Fork synchronization changes GitHub;
  the final Komac submit opens an external PR. Use `--dry-run` for local validation.

For script checks, run `python -m unittest discover -s tests` from `build_scripts/`.
Tests simulate external packagers; they do not prove signed installation, VPN,
upgrade or other-host acceptance. Those remain separate platform checks.
