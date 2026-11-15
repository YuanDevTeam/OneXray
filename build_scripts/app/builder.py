import os
import platform
import re
import shutil
import sys

from app.command_line import (
    check_and_create_dir,
    check_and_delete_dir,
    fastforge_command,
    run_command,
)
from app.config import PROJECT_CONFIG

# Rewrite only the top-level version, preserving comments and line endings.
_PUBSPEC_VERSION = re.compile(
    r"^(?P<prefix>version:[ \t]*)(?P<quote>[\"']?)"
    r"(?P<value>[^\"'#\s]+)(?P=quote)"
    r"(?P<suffix>[ \t]*(?:#[^\r\n]*)?)(?P<cr>\r?)$",
    re.MULTILINE,
)


def _find_pubspec_version(text: str) -> re.Match[str]:
    matches = list(_PUBSPEC_VERSION.finditer(text))
    if len(matches) != 1:
        raise ValueError("pubspec.yaml must contain exactly one top-level version")
    return matches[0]


class Builder:
    def __init__(
        self,
        project: str,
        system: str,
        build_scripts_dir: str,
    ):
        self.project = project
        self.system = system
        self.root_dir = os.path.abspath(os.path.join(build_scripts_dir, ".."))
        self.project_dir = os.path.join(self.root_dir, system)
        self.output_dir = os.path.abspath(os.path.join(self.root_dir, "..", "output"))
        self.workspace_dir = os.path.dirname(self.root_dir)

        try:
            self.project_config = PROJECT_CONFIG[project]
        except KeyError as error:
            raise ValueError(f"unsupported project: {project}") from error

        try:
            build_number = int(os.environ["BUILD_NUMBER"])
        except (KeyError, ValueError) as error:
            raise ValueError("BUILD_NUMBER must be a positive integer") from error
        if build_number <= 0:
            raise ValueError("BUILD_NUMBER must be a positive integer")
        self.build_number = self.project_config["build_number.base"] + build_number

        machine = platform.machine().lower()
        self.package_suffix = f"{platform.system().lower()}-{machine}"

    def before_build(self):
        check_and_create_dir(self.output_dir)
        self.build_core()

    def build_core(self):
        lib_dir = os.path.join(self.workspace_dir, self.project_config["core.dir"])
        cmd_system = "apple" if self.system in ("macos", "ios") else self.system
        cmd = [sys.executable, "build/main.py", cmd_system]
        if cmd_system == "apple":
            cmd.append("go")
        run_command(cmd, cwd=lib_dir)

        lib_dst_path = os.path.join(
            self.project_dir, self.project_config[f"core.lib.dst.dir.{self.system}"]
        )
        check_and_create_dir(lib_dst_path)
        for src in self.project_config[f"core.lib.src.files.{self.system}"]:
            lib_src_path = os.path.join(lib_dir, src)
            if self.system in ("ios", "macos"):
                dst_dir_path = os.path.join(lib_dst_path, src)
                check_and_delete_dir(dst_dir_path)
                shutil.copytree(lib_src_path, dst_dir_path, symlinks=True)
            else:
                shutil.copy(lib_src_path, lib_dst_path)

        dat_src_path = os.path.join(lib_dir, "dat")
        dat_dst_path = os.path.join(self.project_dir, self.project_config["core.dat.dst.dir"])
        check_and_delete_dir(dat_dst_path)
        shutil.copytree(dat_src_path, dat_dst_path, symlinks=True)

        self.build_core_binary()

    def build_core_binary(self):
        src_key = f"core.bin.src.file.{self.system}"
        dst_key = f"core.bin.dst.file.{self.system}"
        if src_key not in self.project_config or dst_key not in self.project_config:
            return

        lib_dir = os.path.join(self.workspace_dir, self.project_config["core.dir"])
        src_path = os.path.join(lib_dir, self.project_config[src_key])
        dst_path = os.path.join(self.project_dir, self.project_config[dst_key])
        check_and_create_dir(os.path.dirname(dst_path))
        shutil.copy(src_path, dst_path)
        if self.system != "windows":
            os.chmod(dst_path, 0o755)

    def fastforge_build(
        self,
        targets: str,
        *,
        arguments: tuple[str, ...] = (),
        env: dict[str, str] | None = None,
        executable: str | None = None,
    ):
        run_command(
            [
                executable or fastforge_command(),
                "package",
                "--platform",
                platform.system().lower(),
                "--targets",
                targets,
                "--skip-clean",
                *arguments,
            ],
            cwd=self.root_dir,
            env=env,
        )

    def read_version(self) -> str:
        with open(
            os.path.join(self.root_dir, "pubspec.yaml"),
            encoding="utf-8",
            newline="",
        ) as pubspec:
            return _find_pubspec_version(pubspec.read()).group("value")

    def write_version(self, version: str):
        if not version or any(character.isspace() for character in version):
            raise ValueError("pubspec version must not contain whitespace")
        if any(character in version for character in "\"'#"):
            raise ValueError("pubspec version contains an unsupported character")

        file_path = os.path.join(self.root_dir, "pubspec.yaml")
        with open(file_path, encoding="utf-8", newline="") as pubspec:
            text = pubspec.read()
        match = _find_pubspec_version(text)
        replacement = "".join(
            (
                match.group("prefix"),
                match.group("quote"),
                version,
                match.group("quote"),
                match.group("suffix"),
                match.group("cr"),
            )
        )
        updated = text[: match.start()] + replacement + text[match.end() :]
        with open(file_path, mode="w", encoding="utf-8", newline="") as pubspec:
            pubspec.write(updated)
