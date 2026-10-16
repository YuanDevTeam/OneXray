import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

from app.builder import Builder
from app.command_line import run_command
from app.flutter import build
from app.linux import LinuxBuilder
from main import main


class BuilderTest(unittest.TestCase):
    def setUp(self):
        fixtures = Path(__file__).resolve().parents[3] / "references/onexray-tests/build-scripts"
        fixtures.mkdir(parents=True, exist_ok=True)
        temporary = tempfile.TemporaryDirectory(dir=fixtures)
        self.addCleanup(temporary.cleanup)
        self.workspace = Path(temporary.name)
        self.root = self.workspace / "OneXray"
        self.root.mkdir()
        self.pubspec = self.root / "pubspec.yaml"
        self.original = b'name: onexray\r\nversion: "26.8.5+1" # build\r\ndependencies:\r\n'
        self.pubspec.write_bytes(self.original)
        self.addCleanup(mock.patch.stopall)
        mock.patch.dict(os.environ, {"BUILD_NUMBER": "1"}).start()

    def test_cli_preserves_mode_selection_and_rejects_it_for_other_platforms(self):
        for options, mode in (([], "exe"), (["--windows-mode", "msix"], "msix")):
            with (
                mock.patch.object(sys, "argv", ["build", "OneXray", "windows", *options]),
                mock.patch("main.build") as run,
            ):
                main()
                self.assertEqual(run.call_args.args[:2], ("OneXray", "windows"))
                self.assertEqual(run.call_args.kwargs["windows_mode"], mode)
        with (
            mock.patch.object(sys, "argv", ["build", "OneXray", "linux", "--windows-mode", "exe"]),
            mock.patch("main.build") as run,
            mock.patch("sys.stderr"),
        ):
            with self.assertRaises(SystemExit):
                main()
            run.assert_not_called()

    def test_build_refreshes_headers_before_ffi_and_restores_pubspec_on_success_or_failure(self):
        header = self.root / "c/include/libXray.h"
        events = []

        def native_build(builder):
            header.parent.mkdir(parents=True, exist_ok=True)
            header.write_text("fresh native header")
            events.append("native")

        def command(args, **kwargs):
            if "tool/ffigen.dart" in args:
                self.assertEqual(header.read_text(), "fresh native header")
                self.assertIn(b"26.8.5+401", self.pubspec.read_bytes())
                events.append("ffi")
                if fail:
                    raise RuntimeError("generation failed")
            elif "appbundle" in args:
                self.assertEqual(events, ["native", "ffi"])
                aab = self.root / "build/app/outputs/bundle/release/app-release.aab"
                aab.parent.mkdir(parents=True, exist_ok=True)
                aab.write_bytes(b"release bundle")
                (aab.parent / "unrelated.log").write_bytes(b"do not collect")
                events.append("flutter")
            elif args[0] == "fastlane":
                self.assertEqual(kwargs["env"], {"ONEXRAY_BUILD_NUMBER": "401"})
                (self.workspace / "output/OneXray-android-universal.apk").write_bytes(
                    b"downloaded APK"
                )

        for fail in (False, True):
            events.clear()
            with (
                mock.patch.object(Builder, "build_core", native_build),
                mock.patch("app.flutter.run_command", side_effect=command),
                mock.patch("app.android.run_command", side_effect=command),
            ):
                if fail:
                    with self.assertRaisesRegex(RuntimeError, "generation failed"):
                        build("OneXray", "android", str(self.root / "build_scripts"))
                    self.assertEqual(events, ["native", "ffi"])
                else:
                    build("OneXray", "android", str(self.root / "build_scripts"))
                    self.assertEqual(
                        {path.name for path in (self.workspace / "output").iterdir()},
                        {"app-release.aab", "OneXray-android-universal.apk"},
                    )
                self.assertEqual(self.pubspec.read_bytes(), self.original)

    def test_core_build_copies_native_library_binary_and_complete_geodata(self):
        for system in ("windows", "linux", "macos"):
            with self.subTest(system=system):
                builder = Builder("OneXray", system, str(self.root / "build_scripts"))
                lib = self.workspace / "libXray"
                files = builder.project_config[f"core.lib.src.files.{system}"]
                for name in files:
                    source = lib / name
                    if name.endswith(".xcframework"):
                        source /= "libXray.a"
                    source.parent.mkdir(parents=True, exist_ok=True)
                    source.write_bytes(b"library fixture")
                for name in ("geoip.dat", "geoip.json", "timestamp.txt"):
                    source = lib / "dat" / name
                    source.parent.mkdir(parents=True, exist_ok=True)
                    source.write_bytes(name.encode())
                if system != "macos":
                    binary = lib / builder.project_config[f"core.bin.src.file.{system}"]
                    binary.parent.mkdir(exist_ok=True)
                    binary.write_bytes(b"core fixture")
                with mock.patch("app.builder.run_command"):
                    builder.build_core()
                for name in files:
                    target = (
                        Path(builder.project_dir)
                        / builder.project_config[f"core.lib.dst.dir.{system}"]
                        / Path(name).name
                    )
                    if name.endswith(".xcframework"):
                        target /= "libXray.a"
                    self.assertEqual(target.read_bytes(), b"library fixture")
                for name in ("geoip.dat", "geoip.json", "timestamp.txt"):
                    self.assertEqual((self.root / "assets/dat" / name).read_bytes(), name.encode())
                if system != "macos":
                    target = (
                        Path(builder.project_dir)
                        / builder.project_config[f"core.bin.dst.file.{system}"]
                    )
                    self.assertEqual(target.read_bytes(), b"core fixture")

    def test_failed_native_build_leaves_existing_artifacts_untouched(self):
        builder = Builder("OneXray", "windows", str(self.root / "build_scripts"))
        native = self.root / "windows/app/libXray.dll"
        native.parent.mkdir(parents=True)
        native.write_bytes(b"previous library")
        with (
            mock.patch(
                "app.builder.run_command",
                side_effect=subprocess.CalledProcessError(1, ["core-build"]),
            ),
            self.assertRaises(subprocess.CalledProcessError),
        ):
            builder.build_core()
        self.assertEqual(native.read_bytes(), b"previous library")

    def test_linux_collects_current_packages_and_restores_debian_configuration(self):
        config = self.root / "linux/packaging/deb/make_config.yaml"
        config.parent.mkdir(parents=True)
        original = "installed_size: 1\n"
        config.write_text(original)
        bundle = self.root / "build/linux/x64/release/bundle"
        bundle.mkdir(parents=True)
        (bundle / "OneXray").write_bytes(b"x" * 4096)
        output = self.workspace / "output"
        output.mkdir()
        stale = self.root / "dist/old-version/old.deb"
        stale.parent.mkdir(parents=True)
        stale.write_bytes(b"old package")
        with (
            mock.patch("app.builder.platform.system", return_value="Linux"),
            mock.patch("app.builder.platform.machine", return_value="x86_64"),
        ):
            builder = LinuxBuilder("OneXray", "linux", str(self.root / "build_scripts"))

            def package(args, **kwargs):
                extension = args[args.index("--targets") + 1]
                self.assertEqual(args[-2:], ["--artifact-name", "OneXray-linux-x86_64.{{ext}}"])
                if extension == "deb":
                    self.assertIn("installed_size: 4", config.read_text())
                    if fail:
                        raise RuntimeError("DEB packaging failed")
                path = (
                    self.root
                    / "dist"
                    / builder.read_version()
                    / f"OneXray-linux-x86_64.{extension}"
                )
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_bytes(extension.encode())

            for fail in (True, False):
                with mock.patch("app.builder.run_command", side_effect=package):
                    if fail:
                        with self.assertRaisesRegex(RuntimeError, "DEB packaging failed"):
                            builder.build_app()
                        self.assertEqual(list(output.iterdir()), [])
                    else:
                        builder.build_app()
                        self.assertEqual(
                            {path.name for path in output.iterdir()},
                            {"OneXray-linux-x86_64.zip", "OneXray-linux-x86_64.deb"},
                        )
                self.assertEqual(config.read_text(), original)

    @unittest.skipUnless(sys.platform == "win32", "Windows executable lookup")
    def test_run_command_finds_pub_tool_and_preserves_arguments_cwd_and_environment(self):
        pub_cache = self.workspace / "Pub cache"
        tool = pub_cache / "bin/onexray-pub-test.bat"
        tool.parent.mkdir(parents=True)
        tool.write_text('@echo off\n>"%RESULT%" echo %~1\n>>"%RESULT%" cd\n', encoding="utf-8")
        result = self.root / "result.txt"
        with mock.patch.dict(os.environ, {"PATH": "", "PUB_CACHE": str(pub_cache)}):
            run_command(
                [tool.name, "argument with spaces"], cwd=str(self.root), env={"RESULT": str(result)}
            )
        argument, directory = result.read_text().splitlines()
        self.assertEqual(argument, "argument with spaces")
        self.assertEqual(Path(directory).resolve(), self.root.resolve())


if __name__ == "__main__":
    unittest.main()
