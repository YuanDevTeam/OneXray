import os
import shutil
import tempfile
import unittest
import xml.etree.ElementTree as ET
import zipfile
from pathlib import Path
from unittest.mock import patch

from app.windows import (
    _VOLE_ARTIFACTS,
    _WINTUN_VERSION,
    VOLE_HEADERS,
    WindowsBuilder,
)
from app.windows_msix import pack_msix


class WindowsPackagingTest(unittest.TestCase):
    def setUp(self):
        fixtures = Path(__file__).resolve().parents[3] / "references/windows-build/tests"
        fixtures.mkdir(parents=True, exist_ok=True)
        temporary = tempfile.TemporaryDirectory(dir=fixtures)
        self.addCleanup(temporary.cleanup)
        self.workspace = Path(temporary.name)
        self.root = self.workspace / "OneXray"
        self.config = self.root / "windows/packaging/exe/make_config.yaml"
        self.config.parent.mkdir(parents=True)
        shutil.copy2(
            Path(__file__).resolve().parents[2] / "windows/packaging/exe/make_config.yaml",
            self.config,
        )
        self.pubspec = self.root / "pubspec.yaml"
        self.pubspec.write_bytes(b"name: onexray\nversion: 26.7.3+412\n")
        self.output = self.workspace / "output"
        self.output.mkdir()
        self.addCleanup(patch.stopall)
        patch.dict(
            os.environ,
            {
                "BUILD_NUMBER": "12",
                "ONEXRAY_DEV_SIGN": "0",
                "ONEXRAY_DEV_CERT_THUMBPRINT": "a" * 40,
                "ONEXRAY_DEV_PUBLISHER": "CN=Development Fixture",
            },
        ).start()

    def builder(self, architecture="x64", mode="msix", development=False):
        with patch.dict(
            os.environ,
            {"ONEXRAY_WINDOWS_ARCH": architecture, "ONEXRAY_DEV_SIGN": "1" if development else "0"},
        ):
            return WindowsBuilder("OneXray", "windows", str(self.root / "build_scripts"), mode=mode)

    def bundle(self, builder):
        source = self.root / "build/windows" / builder.target_architecture / "runner/Release"
        source.mkdir(parents=True, exist_ok=True)
        for name in ("OneXray.exe", "msvcp140.dll", *_VOLE_ARTIFACTS):
            (source / name).write_bytes(name.encode())
        for name in ("data/icudtl.dat", "data/app.so", "data/flutter_assets/AssetManifest.bin"):
            file = source / name
            file.parent.mkdir(parents=True, exist_ok=True)
            file.write_bytes(b"fixture")
        return source

    def test_exe_and_zip_share_one_build_and_restore_installer_inputs(self):
        original_config, original_pubspec = self.config.read_bytes(), self.pubspec.read_bytes()
        for architecture, inno, processor in (
            ("x64", "x64os", "AMD64"),
            ("arm64", "arm64", "ARM64"),
        ):
            builder = self.builder(architecture, "exe")
            calls = []

            def command(
                args, calls=calls, processor=processor, builder=builder, inno=inno, **kwargs
            ):
                calls.append(args)
                self.assertIn("exe,zip", args)
                self.assertIn("--skip-clean", args)
                self.assertIn("ONEXRAY_WINDOWS_MODE=exe", args)
                self.assertIn("build-number=412", args)
                self.assertEqual(kwargs["env"], {"PROCESSOR_ARCHITECTURE": processor})
                self.assertEqual(builder.read_version(), "26.7.3")
                self.assertIn(f"architectures_allowed: {inno}\n", self.config.read_text())
                self.assertIn(
                    f"architectures_install_in_64bit_mode: {inno}\n", self.config.read_text()
                )
                dist = self.root / "dist/26.7.3"
                dist.mkdir(parents=True, exist_ok=True)
                for extension in ("exe", "zip"):
                    (dist / f"OneXray-{builder.package_suffix}.{extension}").write_bytes(
                        extension.encode()
                    )
                (dist / "unrelated.msix").write_bytes(b"other channel")

            with patch("app.builder.run_command", side_effect=command):
                builder.build_app()
            self.assertEqual(len(calls), 1)
            for extension in ("exe", "zip"):
                self.assertEqual(
                    (self.output / f"OneXray-{builder.package_suffix}.{extension}").read_bytes(),
                    extension.encode(),
                )
            self.assertFalse((self.output / "unrelated.msix").exists())
            self.assertEqual(self.config.read_bytes(), original_config)
            self.assertEqual(self.pubspec.read_bytes(), original_pubspec)

    def test_failed_or_incomplete_fastforge_output_is_not_collected(self):
        builder = self.builder(mode="exe")
        original_config, original_pubspec = self.config.read_bytes(), self.pubspec.read_bytes()
        dist = self.root / "dist/26.7.3"
        dist.mkdir(parents=True)
        (dist / "OneXray-windows-amd64.exe").write_bytes(b"incomplete")
        for failure, expected in (
            (RuntimeError("packaging failed"), RuntimeError),
            (None, FileNotFoundError),
        ):
            with patch("app.builder.run_command", side_effect=failure), self.assertRaises(expected):
                builder.build_app()
            self.assertEqual(self.config.read_bytes(), original_config)
            self.assertEqual(self.pubspec.read_bytes(), original_pubspec)
            self.assertEqual(list(self.output.iterdir()), [])

    def test_msix_builds_stages_packs_once_and_signs_only_development_packages(self):
        for architecture in ("x64", "arm64"):
            for development in (False, True):
                with self.subTest(architecture=architecture, development=development):
                    builder = self.builder(architecture, development=development)
                    source = self.bundle(builder)
                    original_crt = (source / "msvcp140.dll").read_bytes()
                    stage = (
                        self.root / f"build/windows/{architecture}/{architecture}/runner/Release"
                    )
                    commands = []

                    def command(
                        args, commands=commands, architecture=architecture, stage=stage, **kwargs
                    ):
                        commands.append(args)
                        if "msix:build" in args:
                            self.assertIn("--build-windows", args)
                            self.assertIn("false", args)
                            self.assertIn("26.7.3.0", args)
                            self.assertEqual(args[args.index("--architecture") + 1], architecture)
                            (stage / "AppxManifest.xml").write_text(
                                MANIFEST.replace(
                                    'ProcessorArchitecture="x64"',
                                    f'ProcessorArchitecture="{architecture}"',
                                )
                            )
                        elif args[0] == "makeappx.exe":
                            self.assertEqual(args[1], "pack")
                            with zipfile.ZipFile(args[args.index("/p") + 1], "w") as package:
                                for file in stage.rglob("*"):
                                    if file.is_file():
                                        package.write(file, file.relative_to(stage))
                        elif args[0] == "signtool.exe":
                            self.assertNotIn("/f", args)
                            self.assertEqual(args[1], "sign")
                            self.assertIn("a" * 40, args)
                            with zipfile.ZipFile(args[-1], "a") as package:
                                package.writestr("AppxSignature.p7x", b"fixture signature")

                    with (
                        patch("app.windows.run_command", side_effect=command),
                        patch("app.windows_msix.run_command", side_effect=command),
                        patch("app.windows_msix._sdk_tool", side_effect=lambda name: name),
                    ):
                        builder.build_app()
                    flutter = commands[0]
                    self.assertIn("ONEXRAY_WINDOWS_MODE=msix", " ".join(flutter))
                    self.assertEqual(
                        "--dart-define=ONEXRAY_WINDOWS_DEVELOPMENT=true" in flutter, development
                    )
                    self.assertEqual(len(commands), 4 if development else 3)
                    package_path = self.output / f"OneXray-{builder.package_suffix}.msix"
                    with zipfile.ZipFile(package_path) as package:
                        self.assertTrue(set(_VOLE_ARTIFACTS).issubset(package.namelist()))
                        self.assertEqual("AppxSignature.p7x" in package.namelist(), development)
                        manifest = ET.fromstring(package.read("AppxManifest.xml"))
                        identity = manifest.find("f:Identity", NS)
                        self.assertEqual(
                            identity.get("Name"),
                            "OneXray.Dev" if development else "YuanDevLLC.OneXray",
                        )
                        self.assertEqual(identity.get("ProcessorArchitecture"), architecture)
                        self.assertEqual(
                            identity.get("Publisher"),
                            "CN=Development Fixture" if development else "CN=Store",
                        )
                        self.assertEqual(
                            len(manifest.findall("f:Applications/f:Application", NS)), 1
                        )
                        self.assertIsNotNone(
                            manifest.find(
                                ".//desktop:Extension[@Executable='vole-windows-session-host.exe']",
                                NS,
                            )
                        )
                        provider = manifest.find(
                            ".//f:Extension[@EntryPoint='Vole.VpnBackgroundTask']", NS
                        )
                        self.assertEqual(
                            provider.get(f"{{{NS['uap10']}}}TrustLevel"), "appContainer"
                        )
                        self.assertIsNotNone(
                            provider.find("f:BackgroundTasks/uap:Task[@Type='vpnClient']", NS)
                        )
                        self.assertEqual(
                            manifest.find(".//f:InProcessServer/f:Path", NS).text, "vole.dll"
                        )
                        self.assertIsNotNone(
                            manifest.find(
                                ".//desktop:StartupTask[@TaskId='VoleStartup'][@Enabled='false']",
                                NS,
                            )
                        )
                        self.assertIsNotNone(manifest.find(".//uap:Protocol[@Name='onexray']", NS))
                    self.assertFalse(stage.exists())
                    self.assertEqual((source / "msvcp140.dll").read_bytes(), original_crt)
                    self.assertFalse((source / "AppxManifest.xml").exists())

    def test_failed_msix_asset_generation_cleans_staging_but_preserves_bundle(self):
        builder = self.builder()
        source = self.bundle(builder)
        with (
            patch("app.windows.run_command", side_effect=RuntimeError("asset generation failed")),
            self.assertRaises(RuntimeError),
        ):
            builder.package_msix()
        self.assertTrue((source / "OneXray.exe").is_file())
        self.assertFalse((source.parents[1] / "x64/runner/Release").exists())
        self.assertEqual(list(self.output.iterdir()), [])

    def test_packaging_or_signing_failure_preserves_the_previous_package(self):
        stage = self.workspace / "stage"
        stage.mkdir()
        package = self.output / "OneXray.msix"
        package.write_bytes(b"previous package")
        for failure_at in ("pack", "sign"):
            (stage / "AppxManifest.xml").write_text(MANIFEST)

            def command(args, failure_at=failure_at, **kwargs):
                if args[1] == failure_at:
                    raise RuntimeError("packaging or signing failed")
                if args[1] == "pack":
                    Path(args[args.index("/p") + 1]).write_bytes(b"new package")

            with (
                patch("app.windows_msix._sdk_tool", side_effect=lambda name: name),
                patch("app.windows_msix.run_command", side_effect=command),
                self.assertRaises(RuntimeError),
            ):
                pack_msix(str(stage), str(package), local_development=True)
            self.assertEqual(package.read_bytes(), b"previous package")
            self.assertEqual(list(self.output.iterdir()), [package])

    def test_missing_development_signing_settings_fail_before_packaging(self):
        for settings in ({"ONEXRAY_DEV_PUBLISHER": ""}, {"ONEXRAY_DEV_CERT_THUMBPRINT": ""}):
            with patch.dict(os.environ, settings), self.assertRaises(ValueError):
                pack_msix("missing stage", "missing.msix", local_development=True)

    def test_windows_builds_download_latest_vole_uwp_files(self):
        files = {
            **{name: self.root / "windows/app" / name for name in _VOLE_ARTIFACTS},
            **{f"include/{name}": self.root / "c/include" / name for name in VOLE_HEADERS},
        }

        def download(url, destination):
            with zipfile.ZipFile(destination, "w") as package:
                for name in files:
                    package.writestr(name, url.encode())
                package.writestr("vole.dll.lib", b"unused import library")

        for architecture, suffix, mode in (("x64", "amd64", "exe"), ("arm64", "arm64", "msix")):
            with self.subTest(architecture=architecture, mode=mode):
                builder = self.builder(architecture, mode)
                with (
                    patch("app.builder.Builder.before_build"),
                    patch.object(builder, "install_wintun"),
                    patch("app.windows.download_file", side_effect=download) as fetch,
                ):
                    builder.before_build()
                    builder.before_build()
                url = (
                    "https://github.com/YuanDevTeam/Vole/releases/latest/download/"
                    f"vole-ffi-windows-uwp-{suffix}.zip"
                )
                self.assertEqual([call.args[0] for call in fetch.call_args_list], [url, url])
                for target in files.values():
                    self.assertEqual(target.read_bytes(), url.encode())
                self.assertFalse((self.root / "windows/app/vole.dll.lib").exists())

    def test_wintun_extracts_the_selected_architecture(self):
        archive = self.workspace / "references/windows-build" / f"wintun-{_WINTUN_VERSION}.zip"
        archive.parent.mkdir(parents=True)
        with zipfile.ZipFile(archive, "w") as package:
            for architecture, directory in (("x64", "amd64"), ("arm64", "arm64")):
                package.writestr(f"wintun/bin/{directory}/wintun.dll", architecture.encode())
        for architecture in ("x64", "arm64"):
            builder = self.builder(architecture)
            builder.install_wintun()
            self.assertEqual(
                (self.root / "windows/app/wintun.dll").read_bytes(), architecture.encode()
            )

    def test_installer_identity_remains_stable(self):
        config = self.config.read_text()
        for setting in (
            "app_id: 835d7bbd-85bb-4c73-97f8-ce0740f151a7",
            "executable_name: OneXray.exe",
            "privileges_required: lowest",
        ):
            self.assertIn(setting, config)


NS = {
    "f": "http://schemas.microsoft.com/appx/manifest/foundation/windows10",
    "uap": "http://schemas.microsoft.com/appx/manifest/uap/windows10",
    "uap10": "http://schemas.microsoft.com/appx/manifest/uap/windows10/10",
    "desktop": "http://schemas.microsoft.com/appx/manifest/desktop/windows10",
}
MANIFEST = f'''<Package xmlns="{NS["f"]}" xmlns:uap="{NS["uap"]}" xmlns:desktop="{NS["desktop"]}"
 xmlns:rescap="http://schemas.microsoft.com/appx/manifest/foundation/windows10/restrictedcapabilities"
 IgnorableNamespaces="uap desktop rescap">
 <Identity Name="YuanDevLLC.OneXray" Publisher="CN=Store" Version="26.7.3.0" ProcessorArchitecture="x64" />
 <Capabilities>
  <Capability Name="internetClientServer" /><Capability Name="privateNetworkClientServer" />
  <rescap:Capability Name="runFullTrust" /><rescap:Capability Name="networkingVpnProvider" />
 </Capabilities>
 <Applications><Application Id="OneXray" Executable="OneXray.exe" EntryPoint="Windows.FullTrustApplication">
  <Extensions>
   <uap:Extension Category="windows.protocol"><uap:Protocol Name="onexray" /></uap:Extension>
   <desktop:Extension Category="windows.startupTask" Executable="OneXray.exe" EntryPoint="Windows.FullTrustApplication">
    <desktop:StartupTask TaskId="VoleStartup" Enabled="false" DisplayName="OneXray" />
   </desktop:Extension>
  </Extensions>
 </Application></Applications>
</Package>'''


if __name__ == "__main__":
    unittest.main()
