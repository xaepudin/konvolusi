# Changelog

All notable user-visible changes are recorded here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions use
[Semantic Versioning](https://semver.org/).

## [1.0.0] — 2026-10-29

First public release.

### Added

- System-wide impulse response convolution for macOS 15+, using a Core Audio
  process tap and a private aggregate device.
- Menu bar panel with impulse response picker, folder selection, wet/dry mix,
  output gain, bypass, normalization, and live input/output meters.
- 15 synthesized impulse responses, generated on first launch: Identity, Speech
  Lift, Night Mode, Warm Desk, Studio Room, Plate, Small Room, Car Cabin,
  Stairwell, Cassette Tape, Old Radio Speaker, Telephone, Large Hall, Cathedral,
  and Tin Can.
- `irsconv` command-line tool for offline rendering, inspection, bench-marking,
  library generation, and self-tests.
- `--diagnose` end-to-end audio-path check.
- Adaptive partition sizing, a silence fast path, and energy normalization.
- Documentation for users (`README.md`) and developers (`docs/`).

### Performance

- Idle CPU cost reduced from about 12% of a core to about 1.4% with the engine
  running, and about 0.1% when the panel has never been opened.
- Convolution CPU for long responses reduced by roughly 4× through adaptive
  partitioning.

### Known limitations

- The release is ad-hoc signed and not notarized. Gatekeeper requires
  Control-click → Open or removing the quarantine attribute.
- The app is not sandboxed.
- Only the convolver is implemented; other Viper4Android effects are out of
  scope.
- Third-party impulse response packs are not bundled because their
  redistribution terms are usually unclear.

[1.0.0]: https://github.com/xaepudin/IRSVerb/releases/tag/v1.0.0
