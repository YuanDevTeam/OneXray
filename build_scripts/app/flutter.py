"""The shared build sequence; platform builders own packaging and deployment."""

import shutil
from pathlib import Path

from app.android import AndroidBuilder
from app.apple import AppleBuilder
from app.command_line import dart_command, flutter_command, run_command
from app.linux import LinuxBuilder
from app.windows import WindowsBuilder

BUILDERS = {
    "ios": AppleBuilder,
    "macos": AppleBuilder,
    "macos_se": AppleBuilder,
    "android": AndroidBuilder,
    "linux": LinuxBuilder,
    "windows": WindowsBuilder,
}


def build(project: str, target: str, build_scripts_dir: str, *, windows_mode: str = "exe"):
    system = "macos" if target == "macos_se" else target
    options = {"mode": windows_mode} if system == "windows" else {}
    builder = BUILDERS[target](project, system, build_scripts_dir, **options)
    root = Path(builder.root_dir)
    pubspec = root / "pubspec.yaml"
    original_pubspec = pubspec.read_bytes()
    try:
        if target == "macos_se":
            source, destination = root / "macos_se", root / "macos"
            if not source.is_dir():
                raise FileNotFoundError(f"macos_se source not found: {source}")
            if destination.exists():
                shutil.rmtree(destination)
            # Preserve framework and pub-cache symlinks.
            shutil.copytree(source, destination, symlinks=True)

        marketing_version = builder.read_version().split("+", maxsplit=1)[0]
        builder.write_version(f"{marketing_version}+{builder.build_number}")
        run_command([flutter_command(), "pub", "get"], cwd=builder.root_dir)
        builder.before_build()
        # Native builds must refresh headers before FFI generation.
        run_command([dart_command(), "run", "tool/ffigen.dart"], cwd=builder.root_dir)
        builder.build_app()
    finally:
        pubspec.write_bytes(original_pubspec)
