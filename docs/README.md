# IRSVerb documentation

This directory is for people who want to understand, modify, build, or publish
IRSVerb. End-user instructions live in the [main README](../README.md).

## Contents

| Document | What it covers |
| --- | --- |
| [building.md](building.md) | Toolchain, build script, tests, CLI, packaging, signing, CI |
| [architecture.md](architecture.md) | Audio pipeline, components, threading, lifecycle, failure handling |
| [dsp.md](dsp.md) | Partitioned convolution, latency, dry/wet alignment, normalization, performance |
| [impulse-responses.md](impulse-responses.md) | `.irs` format, the built-in library, synthesis, licensing, third-party files |
| [diagnostics.md](diagnostics.md) | Permissions, logs, `--diagnose`, `irsconv` checks, metrics |
| [release.md](release.md) | Release checklist, repository identity, signing, publication |

## Conventions

- **Platform:** macOS 15 or later. The audio path uses Core Audio process taps
  (`AudioHardwareCreateProcessTap`), which are unavailable on older releases.
- **Language:** Swift 6 toolchain, Swift 5 language mode. The real-time code is
  pointer-heavy and callback-driven; the package opts into Swift 5 language mode
  in `Package.swift` so the concurrency checker does not reject legitimate
  `@unchecked Sendable` audio objects.
- **No third-party dependencies.** Everything is built from Swift, Accelerate,
  Core Audio, AVFoundation, SwiftUI, and AppKit.
- **No network code.** The app is local-only by design.

## Source map

```
Sources/IRSKit/          platform-independent DSP library
  ImpulseResponse        sample buffers, biquads, deterministic noise
  IRFile                 decode/encode, resampling, .irs reading and writing
  IRSynthesis            built-in impulse response generators
  PartitionedConvolver   uniform-partitioned FFT convolver
  IRSProcessor           stereo convolver pair, dry/wet, gain, bypass
  RingBuffer             lock-free SPSC ring and atomic meters
Sources/irsconv/         command-line renderer and diagnostics
Sources/IRSVerb/         menu bar application
  SystemAudioTap         process tap + private aggregate device
  TapCapture             Core Audio IO thread → ring buffer
  OutputUnit             AUHAL default output unit
  AudioEngine            lifecycle, drift control, watchdog
  AppModel               UI state, library, timers, diagnostics
  PanelView              compact MenuBarExtra panel
  ControlViews           shared controls and accessible meters
  MainWindowView         Control, Library, Diagnostics, About sections
  OnboardingView         first-run explanation
  SettingsView           Background behavior and setup
  Stores                 low-frequency UI state isolated from the scene
  Diagnostics            --diagnose implementation
Tests/IRSKitTests/       33 XCTest cases
Resources/Info.plist     bundle metadata
scripts/                 packaging and icon generation
```

## Reading order

1. [architecture.md](architecture.md) for the big picture.
2. [dsp.md](dsp.md) for how the samples actually change.
3. [impulse-responses.md](impulse-responses.md) for the data format and library.
4. [building.md](building.md) and [diagnostics.md](diagnostics.md) for working on
   the code.
5. [release.md](release.md) when cutting a release.
