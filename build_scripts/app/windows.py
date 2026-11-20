import os
import re
import shutil
import zipfile
from pathlib import Path
from tempfile import TemporaryDirectory

from app.builder import Builder
from app.command_line import (
    dart_command,
    download_file,
    flutter_command,
    is_amd64,
    is_arm64,
    run_command,
)
from app.windows_msix import pack_msix

_VOLE_ARTIFACTS = (
    "vole.dll",
    "vole-windows-vpn-host.exe",
    "vole-windows-session-host.exe",
)
VOLE_HEADERS = ("vole.h", "vole_windows_uwp.h")
_VOLE_RELEASE_URL = "https://github.com/YuanDevTeam/Vole/releases/latest/download"
_WINTUN_VERSION = "0.14.1"


class WindowsBuilder(Builder):
    def __init__(
        self,
        project: str,
        system: str,
        build_scripts_dir: str,
        *,
        mode: str = "exe",
    ):
        if mode not in ("exe", "msix"):
            raise ValueError(f"Unsupported Windows mode: {mode}")
        super().__init__(project, system, build_scripts_dir)
        self.mode = mode
        self.local_development = mode == "msix" and os.environ.get("ONEXRAY_DEV_SIGN") == "1"
        self.target_architecture = self._target_architecture()
        self.package_architecture = "amd64" if self.target_architecture == "x64" else "arm64"
        self.package_suffix = f"windows-{self.package_architecture}"

    @staticmethod
    def _target_architecture() -> str:
        configured = os.environ.get("ONEXRAY_WINDOWS_ARCH")
        if configured in ("x64", "arm64"):
            return configured
        if configured:
            raise ValueError("ONEXRAY_WINDOWS_ARCH must be x64 or arm64")
        if is_amd64():
            return "x64"
        if is_arm64():
            return "arm64"
        raise ValueError("Windows builds only support x64 and arm64")

    def before_build(self):
        super().before_build()
        self.install_vole()
        self.install_wintun()

    def install_wintun(self):
        cache = Path(self.workspace_dir) / "references" / "windows-build"
        cache.mkdir(parents=True, exist_ok=True)
        archive = cache / f"wintun-{_WINTUN_VERSION}.zip"
        if not archive.is_file():
            download_file(f"https://www.wintun.net/builds/{archive.name}", str(archive))
        destination = Path(self.project_dir) / "app" / "wintun.dll"
        destination.parent.mkdir(parents=True, exist_ok=True)
        with zipfile.ZipFile(archive) as package:
            # Only the official DLL is bundled; attribution lives on the docs site.
            destination.write_bytes(
                package.read(f"wintun/bin/{self.package_architecture}/wintun.dll")
            )

    def install_vole(self):
        name = f"vole-ffi-windows-uwp-{self.package_architecture}.zip"
        with TemporaryDirectory() as directory:
            archive = Path(directory) / name
            download_file(f"{_VOLE_RELEASE_URL}/{name}", str(archive))
            with zipfile.ZipFile(archive) as package:
                for artifact in _VOLE_ARTIFACTS:
                    package.extract(artifact, Path(self.project_dir) / "app")
                for header in VOLE_HEADERS:
                    package.extract(f"include/{header}", Path(self.root_dir) / "c")

    def build_app(self):
        if self.mode == "msix":
            command = [
                flutter_command(),
                "build",
                "windows",
                "--dart-define=ONEXRAY_WINDOWS_MODE=msix",
            ]
            if self.local_development:
                command.append("--dart-define=ONEXRAY_WINDOWS_DEVELOPMENT=true")
            run_command(command, cwd=self.root_dir)
            self.package_msix()
        else:
            self.package_exe_and_zip()

    def package_exe_and_zip(self):
        config_path = Path(self.project_dir) / "packaging/exe/make_config.yaml"
        original_config = config_path.read_bytes()
        pubspec_path = Path(self.root_dir) / "pubspec.yaml"
        original_pubspec = pubspec_path.read_bytes()
        marketing_version, _, build_number = self.read_version().partition("+")
        config = original_config.decode("utf-8")
        architecture = "x64os" if self.target_architecture == "x64" else "arm64"
        for key in ("architectures_allowed", "architectures_install_in_64bit_mode"):
            config, count = re.subn(
                rf"(?m)^{key}:.*$",
                f"{key}: {architecture}",
                config,
                count=1,
            )
            if count != 1:
                raise ValueError(f"Fastforge EXE configuration is missing {key}")

        try:
            config_path.write_bytes(config.encode("utf-8"))
            # Inno Setup needs a numeric version; keep Flutter's build number
            # explicitly, while Fastforge builds once for both package targets.
            self.write_version(marketing_version)
            self.fastforge_build(
                "exe,zip",
                arguments=(
                    "--build-dart-define",
                    "ONEXRAY_WINDOWS_MODE=exe",
                    "--flutter-build-args",
                    f"build-number={build_number or self.build_number}",
                    "--artifact-name",
                    f"{self.project}-{self.package_suffix}." + "{{ext}}",
                ),
                # Fastforge resolves the bundle directory from this variable.
                env={"PROCESSOR_ARCHITECTURE": "AMD64" if architecture == "x64os" else "ARM64"},
            )
        finally:
            config_path.write_bytes(original_config)
            pubspec_path.write_bytes(original_pubspec)

        packages = [
            Path(self.root_dir)
            / "dist"
            / marketing_version
            / f"{self.project}-{self.package_suffix}.{extension}"
            for extension in ("exe", "zip")
        ]
        for package in packages:
            if not package.is_file():
                raise FileNotFoundError(f"Fastforge package missing: {package}")
        for package in packages:
            shutil.copy2(package, self.output_dir)

    def package_msix(self):
        source = Path(self.root_dir) / "build/windows" / self.target_architecture / "runner/Release"
        # msix 3.18 resolves architecture twice. Stage a separate bundle so its
        # asset/CRT generation cannot modify the original Flutter output.
        stage = source.parents[1] / self.target_architecture / "runner" / "Release"
        shutil.rmtree(stage, ignore_errors=True)
        try:
            shutil.copytree(source, stage)
            run_command(
                [
                    dart_command(),
                    "run",
                    "msix:build",
                    "--build-windows",
                    "false",
                    "--store",
                    "--architecture",
                    self.target_architecture,
                    "--version",
                    self.msix_version(),
                ],
                cwd=self.root_dir,
            )
            pack_msix(
                str(stage),
                os.path.join(self.output_dir, f"{self.project}-{self.package_suffix}.msix"),
                local_development=self.local_development,
            )
        finally:
            shutil.rmtree(stage, ignore_errors=True)

    def msix_version(self) -> str:
        return self.read_version().split("+", maxsplit=1)[0] + ".0"
