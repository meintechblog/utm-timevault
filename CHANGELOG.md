# Changelog

All notable changes to this project will be documented in this file.

## [0.1.3] - 2026-03-04

### Changed

- Added hard-link capability checks for backup targets.
- Added `HARDLINK_AUTO_FALLBACK` (default `1`) to auto-switch snapshot mode to archive mode when hard links are unavailable.
- Extended `doctor` output with backup-target hard-link support diagnostics.
- Updated documentation for SMB/NAS targets without hard-link support.

## [0.1.2] - 2026-03-04

### Fixed

- Refined CLI numeric argument validation to satisfy strict CI shellcheck checks.

## [0.1.1] - 2026-03-04

### Changed

- VM stop strategy now requests graceful guest shutdown first (`request`) and escalates to force stop only if shutdown times out.

## [0.1.0] - 2026-03-04

### Added

- Initial public release of UTM TimeVault
- Interactive menu mode and scriptable CLI commands
- Backup state safety model (stop check + post-backup state restore)
- Snapshot and archive backup modes
- Global rotation per VM
- Installer script
- Documentation set for onboarding, configuration, automation, troubleshooting, and FAQ
- GitHub CI with bash syntax checks and shellcheck
