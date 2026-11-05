# /// script
# requires-python = ">=3.12"
# dependencies = ["PyYAML==6.0.3", "jsonschema==4.25.1"]
# ///
"""Fix and validate saved Komac manifests; never submit or regenerate them."""

import argparse
import json
import re
from collections import Counter
from copy import deepcopy
from pathlib import Path
from typing import ClassVar
from urllib.request import urlopen

PACKAGE_ID = "YuanDevLLC.OneXray"
DISPLAY_NAME = "OneXray"
INSTALL_DIRECTORY = r"%LOCALAPPDATA%\Programs\OneXray"
INSTALLER_NAMES = {
    "x64": "OneXray-windows-amd64.exe",
    "arm64": "OneXray-windows-arm64.exe",
}


def fix_installer(manifest):
    result = deepcopy(manifest)
    if result.get("PackageIdentifier") != PACKAGE_ID or result.get("ManifestType") != "installer":
        raise ValueError("Expected the OneXray installer manifest")
    for fields in [result, *result["Installers"]]:
        # Keep unrelated metadata, including per-architecture files/product codes.
        if fields is result or "Scope" in fields:
            fields["Scope"] = "user"
        if fields is result or "InstallationMetadata" in fields:
            fields.setdefault("InstallationMetadata", {})["DefaultInstallLocation"] = (
                INSTALL_DIRECTORY
            )
        if fields is result or "AppsAndFeaturesEntries" in fields:
            if not fields.get("AppsAndFeaturesEntries"):
                fields["AppsAndFeaturesEntries"] = [{}]
            for entry in fields["AppsAndFeaturesEntries"]:
                entry["DisplayName"] = DISPLAY_NAME
    return result


def validate_manifests(manifests, release):
    """Check package identity, effective installation policy and release assets."""
    tag = release["tag_name"]
    if not tag.startswith("v") or not tag[1:] or release["draft"] or release["prerelease"]:
        raise ValueError("Expected a stable v-prefixed release")
    version = tag[1:]
    types = Counter(item["ManifestType"] for item in manifests)
    if any(types[kind] != 1 for kind in ("installer", "defaultLocale", "version")):
        raise ValueError("Expected one installer, defaultLocale and version manifest")
    if types.keys() - {"installer", "defaultLocale", "version", "locale"}:
        raise ValueError("Unexpected manifest type")
    for item in manifests:
        if item.get("PackageIdentifier") != PACKAGE_ID or item.get("PackageVersion") != version:
            raise ValueError("Manifest package/version does not match the release")
        schema_version = item.get("ManifestVersion")
        if not isinstance(schema_version, str) or not re.fullmatch(
            r"[0-9]+\.[0-9]+\.[0-9]+", schema_version
        ):
            raise ValueError("Expected a numeric manifest schema version")
        if schema_version != manifests[0].get("ManifestVersion"):
            raise ValueError("All manifests must use the same schema version")
    by_type = {item["ManifestType"]: item for item in manifests}
    if by_type["version"]["DefaultLocale"] != by_type["defaultLocale"]["PackageLocale"]:
        raise ValueError("DefaultLocale does not match the default locale manifest")
    if by_type["defaultLocale"]["PackageName"] != DISPLAY_NAME:
        raise ValueError("PackageName must be OneXray")

    manifest = by_type["installer"]
    installers = manifest["Installers"]
    if Counter(item["Architecture"] for item in installers) != Counter(INSTALLER_NAMES.keys()):
        raise ValueError("Expected exactly one x64 and one arm64 EXE installer")
    for installer in installers:
        # Installer-level fields take precedence over the root manifest.
        effective = manifest | installer
        if effective.get("InstallerType") != "inno" or effective.get("Scope") != "user":
            raise ValueError("OneXray must use per-user Inno Setup installation")
        if (
            effective.get("InstallationMetadata", {}).get("DefaultInstallLocation")
            != INSTALL_DIRECTORY
        ):
            raise ValueError("Unexpected default install location")
        entries = effective.get("AppsAndFeaturesEntries", [])
        if not entries or any(entry.get("DisplayName") != DISPLAY_NAME for entry in entries):
            raise ValueError("DisplayName must be OneXray, without a version")
        if effective.get("ElevationRequirement") not in (None, "elevationProhibited"):
            raise ValueError("The per-user installer must not request elevation")
        name = INSTALLER_NAMES[installer["Architecture"]]
        assets = [asset for asset in release["assets"] if asset["name"] == name]
        if len(assets) != 1:
            raise ValueError(f"Expected one release asset: {name}")
        asset = assets[0]
        if installer["InstallerUrl"] != asset["browser_download_url"]:
            raise ValueError(f"Installer URL does not match the release: {name}")


def read_manifest(path):
    import yaml

    class ManifestLoader(yaml.SafeLoader):
        # ReleaseDate is a schema string, not a Python datetime.date.
        yaml_implicit_resolvers: ClassVar[dict] = {
            key: [rule for rule in rules if rule[0] != "tag:yaml.org,2002:timestamp"]
            for key, rules in yaml.SafeLoader.yaml_implicit_resolvers.items()
        }

    return yaml.load(path.read_text(encoding="utf-8"), Loader=ManifestLoader)


def fix_file(directory):
    import yaml

    path = directory / f"{PACKAGE_ID}.installer.yaml"
    original = path.read_text(encoding="utf-8")
    manifest = fix_installer(read_manifest(path))
    # Retain generator/schema comments and the repository's CRLF convention.
    header = "\n".join(line for line in original.splitlines() if line.startswith("#"))
    text = (
        header + "\n\n" + yaml.safe_dump(manifest, sort_keys=False, allow_unicode=True, width=1000)
    )
    path.write_bytes(text.replace("\n", "\r\n").encode("utf-8"))


def validate_directory(directory, release):
    import jsonschema

    paths = sorted(path for path in directory.rglob("*") if path.suffix.lower() == ".yaml")
    if any(path.parent != directory for path in paths):
        raise ValueError("Only one flat version directory may be submitted")
    manifests = [read_manifest(path) for path in paths]
    validate_manifests(manifests, release)
    for path, manifest in zip(paths, manifests):
        kind = manifest["ManifestType"]
        schema_version = manifest["ManifestVersion"]
        suffix = {
            "installer": ".installer",
            "version": "",
            "defaultLocale": f".locale.{manifest.get('PackageLocale')}",
            "locale": f".locale.{manifest.get('PackageLocale')}",
        }[kind]
        if path.name != f"{PACKAGE_ID}{suffix}.yaml":
            raise ValueError(f"Unexpected manifest filename: {path.name}")
        url = (
            "https://raw.githubusercontent.com/microsoft/winget-cli/master/schemas/JSON/manifests/"
            f"v{schema_version}/manifest.{kind}.{schema_version}.json"
        )
        with urlopen(url, timeout=30) as response:
            schema = json.load(response)
        jsonschema.Draft7Validator(schema).validate(manifest)
        print(f"Validated {path.name}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)
    fix = subparsers.add_parser("fix")
    fix.add_argument("directory", type=Path)
    validate = subparsers.add_parser("validate")
    validate.add_argument("directory", type=Path)
    validate.add_argument("--release", type=Path, required=True)
    args = parser.parse_args()
    if args.command == "fix":
        fix_file(args.directory)
    else:
        validate_directory(args.directory, json.loads(args.release.read_text(encoding="utf-8")))


if __name__ == "__main__":
    main()
