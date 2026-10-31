# Scoop

[onexray.json](onexray.json) is the candidate manifest for
[Scoop Extras](https://github.com/ScoopInstaller/Extras), requested in
[OneXray #247](https://github.com/YuanDevTeam/OneXray/issues/247). The
[Extras package request](https://github.com/ScoopInstaller/Extras/issues/19187)
has been submitted; inclusion requires maintainer approval under the
[official contribution process](https://github.com/ScoopInstaller/.github/blob/main/.github/CONTRIBUTING.md).

The manifest uses the existing stable Windows x64 and ARM64 ZIP packages. They
include Core, Wintun, Flutter plugins and the matching MSVC runtime; no Inno Setup
extraction or separate runtime installation is needed. Scoop creates the Start
menu shortcut and uses its `current` directory across updates by default.

App settings and profiles remain in `%APPDATA%\YuanDevLLC\OneXray`, shared with
the regular Windows EXE/ZIP edition. They are outside Scoop's version directories,
so the manifest does not use `persist` or delete App data during uninstall.

## Validate on Windows

From the App checkout, with Scoop already installed:

```powershell
scoop install .\windows\packaging\scoop\onexray.json
```

Open OneXray from the Start menu and check setup, the tray and configuration
loading. The local manifest can be tested before it is submitted to Extras.

To make this installation handle `onexray://` links for the current user:

```powershell
reg import "$(scoop prefix onexray)\install-url-protocol.reg"
```

Installation only generates this file; importing it selects the Scoop copy as
the protocol handler. Uninstall removes a matching Scoop registration and App
startup shortcut, preserving entries owned by another installation. An update
does not run this cleanup.

Before updating or uninstalling, disconnect and close OneXray. Test an upgrade
from an earlier stable manifest to the current one, then `scoop cleanup onexray`:
the Start menu shortcut and optional protocol handler should open the new copy,
settings and subscriptions should remain, and an enabled App startup shortcut
should still work. Also test with startup disabled and with another installation
owning the protocol registration. Finally run:

```powershell
scoop uninstall onexray
```

Check that only Scoop-owned integration is removed and App data remains. Schema,
archive and mocked hook checks on another OS do not replace these Windows checks.

## Version updates and Extras submission

`checkver` reads the latest stable GitHub release. `autoupdate` selects each
architecture's versioned ZIP and lets Scoop download it to calculate SHA-256.
The end-user `scoop update` command does not rewrite a manifest using these rules.

For local maintenance, regenerate the manifest using Scoop's updater:

```powershell
& "$(scoop prefix scoop)\bin\checkver.ps1" onexray -Dir .\windows\packaging\scoop -ForceUpdate
```

Review both package URLs and hashes and perform the Windows checks above. Once
the Extras package request is approved, copy only `onexray.json` to
`bucket/onexray.json` in an Extras feature branch and follow its verification
process. Extras' scheduled updater maintains the accepted manifest; OneXray does
not need an additional package-update workflow. The copy in this repository is
maintained separately and must be refreshed when used for a new submission.
