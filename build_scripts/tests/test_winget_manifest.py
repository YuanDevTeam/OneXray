import unittest
from copy import deepcopy

from winget_manifest import (
    DISPLAY_NAME,
    INSTALL_DIRECTORY,
    INSTALLER_NAMES,
    PACKAGE_ID,
    fix_installer,
    validate_manifests,
)


class WingetManifestTest(unittest.TestCase):
    def setUp(self):
        self.release = {
            "tag_name": "v26.9.3",
            "draft": False,
            "prerelease": False,
            "assets": [
                {
                    "name": name,
                    "browser_download_url": f"https://github.com/YuanDevTeam/OneXray/releases/download/v26.9.3/{name}",
                }
                for name in INSTALLER_NAMES.values()
            ],
        }
        base = {
            "PackageIdentifier": PACKAGE_ID,
            "PackageVersion": "26.9.3",
            "ManifestVersion": "1.12.0",
        }
        self.generated = base | {
            "ManifestType": "installer",
            "InstallerType": "inno",
            "Scope": "machine",
            "ProductCode": "onexray_is1",
            "ReleaseDate": "2026-09-16",
            "InstallationMetadata": {"DefaultInstallLocation": r"%ProgramFiles%\OneXray"},
            "AppsAndFeaturesEntries": [{"ProductCode": "onexray_is1"}],
            "Installers": [
                {
                    "Architecture": arch,
                    "InstallerUrl": asset["browser_download_url"],
                    "InstallerSha256": "A" * 64,
                }
                for arch, asset in zip(INSTALLER_NAMES, self.release["assets"])
            ],
        }
        self.manifests = [
            fix_installer(self.generated),
            base
            | {"ManifestType": "defaultLocale", "PackageLocale": "en-US", "PackageName": "OneXray"},
            base | {"ManifestType": "version", "DefaultLocale": "en-US"},
        ]

    def test_fixes_only_installation_policy_and_is_idempotent(self):
        original = deepcopy(self.generated)
        fixed = fix_installer(self.generated)
        expected = deepcopy(original)
        expected["Scope"] = "user"
        expected["InstallationMetadata"]["DefaultInstallLocation"] = INSTALL_DIRECTORY
        expected["AppsAndFeaturesEntries"][0]["DisplayName"] = DISPLAY_NAME
        self.assertEqual(fixed, expected)
        self.assertEqual(self.generated, original)
        self.assertEqual(fix_installer(fixed), fixed)
        validate_manifests(self.manifests, self.release)

    def test_fixes_per_installer_overrides_without_dropping_metadata(self):
        installer = self.generated["Installers"][0]
        installer.update(
            {
                "Scope": "machine",
                "InstallationMetadata": {
                    "DefaultInstallLocation": r"%ProgramFiles%\OneXray",
                    "Files": [],
                },
                "AppsAndFeaturesEntries": [
                    {"DisplayName": "OneXray 26.9.3", "ProductCode": "x64_is1"}
                ],
            }
        )
        fixed = fix_installer(self.generated)
        self.assertEqual(
            fixed["Installers"][0]["InstallationMetadata"],
            {"DefaultInstallLocation": INSTALL_DIRECTORY, "Files": []},
        )
        self.assertEqual(
            fixed["Installers"][0]["AppsAndFeaturesEntries"],
            [{"DisplayName": DISPLAY_NAME, "ProductCode": "x64_is1"}],
        )
        self.manifests[0] = fixed
        validate_manifests(self.manifests, self.release)

    def test_restores_missing_display_name(self):
        del self.generated["AppsAndFeaturesEntries"]
        fixed = fix_installer(self.generated)
        self.assertEqual(fixed["AppsAndFeaturesEntries"], [{"DisplayName": DISPLAY_NAME}])

    def test_rejects_wrong_effective_installer_policy(self):
        for field, value in (
            ("Scope", "machine"),
            ("InstallerType", "msix"),
            ("InstallationMetadata", {"DefaultInstallLocation": r"%ProgramFiles%\OneXray"}),
            ("AppsAndFeaturesEntries", [{"DisplayName": "OneXray 26.9.3"}]),
            ("ElevationRequirement", "elevatesSelf"),
        ):
            with self.subTest(field=field):
                changed = deepcopy(self.manifests)
                changed[0]["Installers"][0][field] = value
                with self.assertRaises(ValueError):
                    validate_manifests(changed, self.release)

    def test_rejects_wrong_url_or_architecture(self):
        for field, value in (
            ("InstallerUrl", "https://example.org/unrelated.exe"),
            ("Architecture", "arm64"),
        ):
            with self.subTest(field=field):
                changed = deepcopy(self.manifests)
                changed[0]["Installers"][0][field] = value
                with self.assertRaises(ValueError):
                    validate_manifests(changed, self.release)

    def test_rejects_missing_architecture_or_manifest(self):
        missing_arch = deepcopy(self.manifests)
        missing_arch[0]["Installers"].pop()
        for manifests in (
            missing_arch,
            self.manifests[:2],
            self.manifests + self.manifests[:1],
            [],
        ):
            with self.subTest(manifests=manifests), self.assertRaises(ValueError):
                validate_manifests(manifests, self.release)

    def test_rejects_mixed_package_version_and_locale(self):
        for index, field, value in (
            (1, "PackageVersion", "26.9.2"),
            (0, "PackageIdentifier", "Other.Package"),
            (0, "ManifestVersion", "1.10.0"),
            (2, "DefaultLocale", "zh-CN"),
        ):
            with self.subTest(field=field):
                changed = deepcopy(self.manifests)
                changed[index][field] = value
                with self.assertRaises(ValueError):
                    validate_manifests(changed, self.release)

    def test_rejects_non_release(self):
        for field in ("draft", "prerelease"):
            with self.subTest(field=field), self.assertRaises(ValueError):
                validate_manifests(self.manifests, self.release | {field: True})

    def test_accepts_a_consistent_generator_schema_version(self):
        for version in ("1.10.0", "1.12.0", "1.28.0"):
            with self.subTest(version=version):
                manifests = deepcopy(self.manifests)
                for manifest in manifests:
                    manifest["ManifestVersion"] = version
                validate_manifests(manifests, self.release)

    def test_rejects_unsafe_or_missing_schema_versions(self):
        for version in (None, "", "v1.12.0", "../1.12.0", "1.12.0?raw=1", 1.12):
            with self.subTest(version=version):
                manifests = deepcopy(self.manifests)
                for manifest in manifests:
                    manifest["ManifestVersion"] = version
                with self.assertRaises(ValueError):
                    validate_manifests(manifests, self.release)


if __name__ == "__main__":
    unittest.main()
