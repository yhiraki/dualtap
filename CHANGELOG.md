# Changelog

All notable changes to this project are documented here.
The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.4] - 2026-07-09
### Fixed
- `record -o PATH`: when PATH has no extension, the container extension
  (`.m4a`/`.wav`) is now appended, matching the default output name.
  Previously the file was written without an extension.

## [0.1.3] - 2026-07-04
### Added
- Scheduled start for `record`: `--delay DUR` (relative) and `--start-at TIME`
  (wall-clock `HH:mm[:ss]`), shown as a countdown until recording begins.
- Auto-stop for `record`: `--duration DUR` (alias `--for`) and `--stop-at TIME`;
  when both are given, recording stops at whichever comes first.

## [0.1.2] - 2026-07-04
### Added
- `-x, --exec CMD` option for `record`: run a command via `/bin/sh` after the
  recording is saved. `{}` and `$DUALTAP_OUTPUT` expand to the output path.

## [0.1.1] - 2026-07-01
### Added
- Release workflow: tag push (`v*`) builds a universal binary and attaches it to
  a GitHub Release.

## [0.1.0] - 2026-07-01
### Added
- Initial release: record microphone and system audio together on macOS via the
  Core Audio process-tap API, no BlackHole. `record`, `monitor`, `devices`, and
  `menubar` subcommands.

[Unreleased]: https://github.com/yhiraki/dualtap/compare/v0.1.4...HEAD
[0.1.4]: https://github.com/yhiraki/dualtap/compare/v0.1.3...v0.1.4
[0.1.3]: https://github.com/yhiraki/dualtap/compare/v0.1.2...v0.1.3
[0.1.2]: https://github.com/yhiraki/dualtap/compare/v0.1.1...v0.1.2
[0.1.1]: https://github.com/yhiraki/dualtap/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/yhiraki/dualtap/releases/tag/v0.1.0
