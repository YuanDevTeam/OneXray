import re
import shutil
from pathlib import Path

from app.builder import Builder


class LinuxBuilder(Builder):
    def build_app(self):
        arguments = ("--artifact-name", f"{self.project}-{self.package_suffix}." + "{{ext}}")
        self.fastforge_build("zip", arguments=arguments)
        self._build_deb(arguments)
        self.fastforge_build("rpm", arguments=arguments)
        packages = [
            Path(self.root_dir)
            / "dist"
            / self.read_version()
            / f"{self.project}-{self.package_suffix}.{extension}"
            for extension in ("zip", "deb", "rpm")
        ]
        for package in packages:
            if not package.is_file():
                raise FileNotFoundError(f"Fastforge package missing: {package}")
        for package in packages:
            shutil.copy2(package, self.output_dir)

    def _build_deb(self, arguments):
        config_path = Path(self.project_dir) / "packaging" / "deb" / "make_config.yaml"
        original_config = config_path.read_text(encoding="utf-8")
        installed_size = self._installed_size_kib()
        updated_config, replacements = re.subn(
            r"(?m)^installed_size:\s*\d+\s*$",
            f"installed_size: {installed_size}",
            original_config,
            count=1,
        )
        if replacements != 1:
            raise ValueError("Linux package installed_size is missing")

        config_path.write_text(updated_config, encoding="utf-8")
        try:
            self.fastforge_build("deb", arguments=arguments)
        finally:
            config_path.write_text(original_config, encoding="utf-8")

    def _installed_size_kib(self) -> int:
        build_root = Path(self.project_dir).parent / "build" / "linux"
        bundles = list(build_root.glob("*/release/bundle"))
        if not bundles:
            raise FileNotFoundError("Linux release bundle is missing")
        bundle = max(bundles, key=lambda path: path.stat().st_mtime_ns)
        total_bytes = sum(path.stat().st_size for path in bundle.rglob("*") if path.is_file())
        return max(1, (total_bytes + 1023) // 1024)
