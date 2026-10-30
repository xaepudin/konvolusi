# Changelog

All notable user-visible changes are recorded here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions use
[Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added

- A conventional main window with a sidebar for **Control**, **Library**,
  **Diagnostics**, and **About**, reachable from **Open IRSVerb…** in the menu bar
  panel.
- A first-run welcome sheet over the main window explaining the menu bar icon and
  the System Audio Recording permission. The engine is not started until the user
  continues, so the permission dialog no longer covers the explanation.
- Settings for **Show IRSVerb in the Dock** (on by default), a shortcut to the
  privacy pane, and resetting the welcome screen.
- `--show-main` launch option for opening the main window directly, useful when
  the menu bar icon is hidden.
- Accessibility labels and values for the menu bar icon, impulse response picker,
  mix and gain sliders, and input/output meters. The panel and main window share
  one control implementation.

### Fixed

- The app no longer terminates when its last window closes. That bug killed the
  process (and the menu bar item) just after the welcome screen was dismissed.
- Reopening the app from the Dock, Spotlight, or Finder while it is already running
  now opens the main window instead of doing nothing.
- The first launch opens the main window, so a crowded or hidden menu bar icon is
  never the only way to reach the UI.
- The Library page uses a fixed sidebar and detail layout. A restored
  `NavigationSplitView` frame could clip the list and hide the sidebar rows.
- Settings is reachable from a gear button at the bottom of the main sidebar.
- The main window regains focus after the welcome sheet closes instead of leaving
  the previous app in front.
- The output unit starts after about two seconds even when nothing is playing yet,
  instead of waiting up to a minute while the tap could mute system audio. Capture
  counters are reset on stop so a restart cannot reuse stale readiness data.
- The “no audio captured” hint is suppressed while the tap has not delivered any
  frames, so a silent Mac is not reported as a routing failure.

### Changed

- Meter updates are observed only by the meter views, and the 20 Hz meter timer
  stops when the main window closes. The menu bar-only profile is typically under
  1% CPU idle and 2–4% while playing a long response; leaving the main window open
  with live meters costs about 5–6%.
- The main window uses a modern sidebar and card layout with a clear status header,
  wider impulse response picker, and consistent spacing.
- The welcome sheet uses aligned icon rows, readable body text, and a card for the
  permission explanation.
- Added visible **ⓘ** buttons with click-to-open explanations for Mix, Output gain,
  Bypass, Normalize, and Levels. The impulse response, status, and diagnostics
  areas intentionally have no extra info buttons.
- Replaced folder selection with a fixed library: **Add IR…** copies files into
  IRSVerb's library, and **Remove** deletes added IRs. The built-in responses are
  always available. **Reveal Logs** is now **Show Logs in Finder**.
- The level meters are blank while there is no signal.
- Removed third-party branding references. The app is described only as a `.irs`
  impulse response convolver.
- The silent-input hint now appears only after output has started, so a quiet Mac
  that has not played anything is not described as a permission failure.

## [1.0.0] — 2026-10-29

First public release.

### Added

- System-wide impulse response convolution for macOS 15+, using a Core Audio
  process tap and a private aggregate device.
- Universal release bundle for Apple silicon and Intel Macs.
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
- Only the convolver is implemented; other audio effects are out of scope.
- Third-party impulse response packs are not bundled because their
  redistribution terms are usually unclear.

[1.0.0]: https://github.com/xaepudin/IRSVerb/releases/tag/v1.0.0
