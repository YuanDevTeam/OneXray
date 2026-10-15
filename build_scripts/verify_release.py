#!/usr/bin/env python3
"""Select a Build run's complete package set for the requested release channel."""

import argparse
import json
from pathlib import Path

_GITHUB_PACKAGES = {
    "ios": ("ios/OneXray-ios.ipa",),
    "macos": ("macos_se/OneXray-macos-universal.zip",),
    "android": ("android-universal/OneXray-android-universal.apk",),
    "linux": (
        "linux-x64/OneXray-linux-x86_64.zip",
        "linux-x64/OneXray-linux-x86_64.deb",
        "linux-arm64/OneXray-linux-aarch64.zip",
        "linux-arm64/OneXray-linux-aarch64.deb",
    ),
    "windows": (
        "windows-x64/OneXray-windows-amd64.exe",
        "windows-x64/OneXray-windows-amd64.zip",
        "windows-arm64/OneXray-windows-arm64.exe",
        "windows-arm64/OneXray-windows-arm64.zip",
    ),
}
_STORE_PACKAGES = (
    "windows-store-x64/OneXray-windows-amd64.msix",
    "windows-store-arm64/OneXray-windows-arm64.msix",
)


def verify_release(
    artifacts: Path,
    run: dict,
    *,
    tag: str | None = None,
    tag_sha: str | None = None,
    windows_only: bool = False,
) -> list[Path]:
    metadata = artifacts / "release-metadata"

    def value(name: str) -> str:
        result = (metadata / f"{name}.txt").read_text(encoding="utf-8").strip()
        if not result:
            raise ValueError(f"Empty release metadata: {name}")
        return result

    metadata_attempt = value("run-attempt")
    run_attempt = run.get("run_attempt")
    if (
        run.get("path") != ".github/workflows/build.yml"
        or run.get("conclusion") != "success"
        or str(run.get("id")) != value("run-id")
        # Retrying failed jobs retains successful earlier jobs and their artifacts.
        or type(run_attempt) is not int
        or not metadata_attempt.isdecimal()
        or not 1 <= int(metadata_attempt) <= run_attempt
        or run.get("head_sha") != value("sha")
        or run.get("repository", {}).get("full_name") != value("repository")
    ):
        raise ValueError("Release metadata does not match the successful Build run")
    if tag and (not tag.startswith("v") or tag_sha != run["head_sha"]):
        raise ValueError("Release tag does not point to the built App commit")
    if tag and (metadata / "tag.txt").exists() and value("tag") != tag:
        raise ValueError("Release tag does not match build metadata")

    target = value("target")
    if windows_only:
        if target not in {"all", "windows"}:
            raise ValueError("Build target does not include Windows Store packages")
        names = _STORE_PACKAGES
    elif target == "all":
        names = tuple(name for group in _GITHUB_PACKAGES.values() for name in group)
    elif target in _GITHUB_PACKAGES:
        names = _GITHUB_PACKAGES[target]
    else:
        raise ValueError(f"Unknown release target: {target}")

    files = [artifacts / name for name in names]
    for path in files:
        if not path.is_file() or path.is_symlink():
            raise FileNotFoundError(f"Missing release package: {path.relative_to(artifacts)}")
    return files


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("artifacts", type=Path)
    parser.add_argument("run_json", type=Path)
    parser.add_argument("--tag")
    parser.add_argument("--tag-sha")
    parser.add_argument("--windows-only", action="store_true")
    args = parser.parse_args()
    files = verify_release(
        args.artifacts,
        json.loads(args.run_json.read_text(encoding="utf-8")),
        tag=args.tag,
        tag_sha=args.tag_sha,
        windows_only=args.windows_only,
    )
    print("\n".join(str(path) for path in files))


if __name__ == "__main__":
    main()
