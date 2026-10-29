# Building and testing

## Requirements

- macOS 15 Sequoia or later
- Xcode 16 or a Swift 6.0+ toolchain (`swift --version`)
- No third-party packages, no CocoaPods, no Homebrew dependencies

The audio path uses Core Audio process taps, which require macOS 14.2+ at
runtime; the package targets macOS 15.

## Quick build

```sh
git clone https://github.com/xaepudin/IRSVerb.git
cd IRSVerb
swift build -c release
swift test
./build.sh
open dist/IRSVerb.app
```

`./build.sh` does a release build of both products, assembles
`dist/IRSVerb.app`, ad-hoc signs it, regenerates the 15 demo responses into
`Impulse Responses/`, and copies `irsconv` to `dist/irsconv`. It builds for the
host architecture by default, so pass `debug` for a debug build:

```sh
./build.sh debug
```

For a release that runs on both Apple silicon and Intel Macs, build universal
binaries:

```sh
./build.sh universal
lipo -info dist/IRSVerb.app/Contents/MacOS/IRSVerb
# Architectures in the fat file: ... are: x86_64 arm64
```

This cross-builds both `arm64-apple-macosx15.0` and
`x86_64-apple-macosx15.0` with SwiftPM, combines each product with `lipo`, and
then assembles and signs the bundle. It doubles the build time; day-to-day
development can use the native build.

The bundle is assembled by copying `Resources/Info.plist`, `Resources/AppIcon.icns`,
and the two executables; there is no Xcode project. `Package.swift` is the source
of truth:

| Product | Target | Kind |
| --- | --- | --- |
| `IRSKit` | `Sources/IRSKit` | Library (DSP) |
| `irsconv` | `Sources/irsconv` | Command-line executable |
| `IRSVerb` | `Sources/IRSVerb` | Menu bar app executable |

## Tests

```sh
swift test
# or a single suite:
swift test --filter ConvolutionTests
```

The suite has 33 XCTest cases. It covers the FFT convolver against a naive direct
convolution, chunked processing, reset, dry/wet alignment, bypass, gain,
normalization, the silence fast path, ring-buffer accounting, and the measured
character of the synthesized library. Expect about 15 seconds on Apple silicon.

Tests do not require audio hardware, permissions, or a GUI.

## Running

```sh
open dist/IRSVerb.app
```

The app is a menu bar agent (`LSUIElement` is true) but switches to `.regular` at
launch so it is in the Dock by default; turn off **Show IRSVerb in the Dock** to
test the menu-bar-only configuration. To see its log while developing:

```sh
tail -f ~/Library/Logs/IRSVerb/app.log
```

To run the executable directly (useful for debugger output):

```sh
dist/IRSVerb.app/Contents/MacOS/IRSVerb
```

A direct launch from Terminal may attribute the System Audio Recording permission
to Terminal rather than the app, so prefer `open dist/IRSVerb.app` when testing
permissions.

## The `irsconv` CLI

`irsconv` uses the same `IRSKit` code as the app, so it is the quickest way to
check DSP changes without listening.

```sh
# Built-in checks (no hardware or permissions)
dist/irsconv selftest

# Apply an impulse response to one or more files
dist/irsconv render song.wav --irs "Impulse Responses/Large Hall.irs" --out out/
dist/irsconv render song.wav --irs hall.irs --wet 0.5 --gain-db -3 --bits 24
dist/irsconv render *.wav --irs "Impulse Responses/Telephone.irs" --out out/

# Inspect responses
dist/irsconv info "Impulse Responses"/*.irs

# Regenerate the built-in library
dist/irsconv make-ir --out "Impulse Responses"
dist/irsconv make-ir --out /tmp/irs --rate 48000

# Measure convolution throughput (no hardware)
dist/irsconv benchmark --irs "Impulse Responses/Large Hall.irs" --seconds 12
```

`render` options:

| Option | Meaning |
| --- | --- |
| `--irs <file>` | Impulse response to apply (required) |
| `--out <dir\|file.wav>` | Output directory, or a `.wav` path for a single input |
| `--wet <0..1>` | Wet/dry mix, default 1.0 |
| `--gain-db <db>` | Output gain, default 0 |
| `--bits <16\|24\|32>` | Output bit depth, default 24 |
| `--rate <hz>` | Render rate; defaults to each input's rate |
| `--normalize` / `--no-normalize` | Energy-normalize the response (on by default) |

`render` streams the audio through the same convolver as the live app, resamples
the impulse response to the render rate, flushes the convolution tail, and trims
the block latency so the output lines up with the input. It reports input/output
peak and RMS levels and the block size used.

`benchmark` prints two rows: a fixed 256-sample block (the old behaviour) and the
adaptive block used now. `xRT` is seconds of audio per second of CPU; `%` is the
share of one core. `noise` is continuous input, `silence` is digitally silent
input where the FFT fast path applies. It needs no audio device.

## Packaging a release

```sh
scripts/package-release.sh
```

The script builds a universal release app, adds the icon and metadata, and writes
to `dist/`:

- `IRSVerb-<version>-macos.zip` — app bundle, zipped with `ditto`;
- `IRSVerb-<version>.dmg` — drag-to-Applications disk image;
- `IRSVerb-<version>-macos.zip.sha256` and `.dmg.sha256` — checksums.

The version comes from `CFBundleShortVersionString` in `Resources/Info.plist`.
Run `scripts/package-release.sh` only after `swift test` and
`dist/irsconv selftest` pass.

## Signing and notarization

`build.sh` signs ad-hoc:

```sh
codesign --force --sign - --timestamp=none dist/IRSVerb.app
```

That is enough for local use and for the system-audio permission prompt, but it
has two consequences:

1. The signature changes on every build, so macOS may treat a rebuilt app as a
   different app and ask for permission again.
2. Gatekeeper cannot verify the download; users must Control-click → Open or
   remove the quarantine attribute. The README explains this.

For a smoother download, sign with a Developer ID Application certificate and
notarize:

```sh
codesign --force --deep --options runtime \
  --sign "Developer ID Application: Your Name (TEAMID)" dist/IRSVerb.app

ditto -c -k --keepParent dist/IRSVerb.app dist/IRSVerb.zip
xcrun notarytool submit dist/IRSVerb.zip \
  --apple-id "you@example.com" --team-id TEAMID \
  --password "@keychain:AC_PASSWORD" --wait
xcrun stapler staple dist/IRSVerb.app
```

Then rebuild the zip/DMG and verify:

```sh
spctl --assess --type execute --verbose dist/IRSVerb.app
codesign --verify --deep --strict --verbose=2 dist/IRSVerb.app
```

Do not commit a Developer ID private key or an app-specific password. Keep
notarization credentials in the login keychain or CI secrets.

The app is not sandboxed. A sandboxed build would need the audio-capture
entitlement and a different distribution path; that is out of scope.

## CI

`.github/workflows/ci.yml` runs on `macos-15` for pushes to `main` and pull
requests:

```sh
swift build
swift test
dist/irsconv selftest   # after building the CLI
```

The release workflow builds and attaches the zip/DMG on a `v*` tag. It uses the
repository's `GITHUB_TOKEN`; it does not need a Developer ID unless you add
notarization secrets.

## Versioning

- `Resources/Info.plist` → `CFBundleShortVersionString` is the user-facing
  version (`1.0.0`).
- `CFBundleVersion` is the build number (`1`).
- Git tags use `v1.0.0`.
- `CHANGELOG.md` records user-visible changes.

Bump all three when cutting a release. The package has no version constant of its
own; the bundle is the authority.

## Troubleshooting the build

| Symptom | Likely cause |
| --- | --- |
| `error: unable to find utility "swift"` | Install Xcode and select it with `xcode-select`; the Command Line Tools alone may not include the macOS SDK |
| `AudioHardwareCreateProcessTap` is unavailable | The SDK/target is older than macOS 14.2; check the platform in `Package.swift` |
| App builds but exits immediately | Run the executable from Terminal to see the error; check `~/Library/Logs/IRSVerb/app.log` |
| `codesign` fails with “resource fork, Finder information, or similar detritus” | Remove extended attributes: `xattr -cr dist/IRSVerb.app`, then re-sign |
| Tests pass but the app cannot capture audio | Permissions are per-bundle; use the app bundle, not the raw executable, and check System Settings |

## UI development

The app has four UI surfaces: the menu bar panel, the main window, the welcome
sheet, and Settings. The main window opens on first launch and is suppressed on
later launches so the app stays a menu bar utility. Open it directly while
developing:

```sh
open dist/IRSVerb.app --args --show-main
```

`--show-main` also suppresses the welcome sheet, which makes it useful for
screenshotting the Control, Library, Diagnostics, and About tabs without resetting
preferences. Quit any running instance first; `open --args` does not re-apply the
option to an existing process. To see the welcome flow again:

```sh
defaults delete io.github.xaepudin.IRSVerb HasCompletedOnboarding
open dist/IRSVerb.app
```

The welcome sheet intentionally does not start the audio engine; it starts when the
user chooses **Open IRSVerb** or presses **Start**. This keeps the System Audio
Recording dialog from covering the explanation. IRSVerb defaults to a Dock icon
(`ShowInDock`), so closing every window does not hide the app; turn that off in
Settings to test the menu-bar-only path. Test VoiceOver and Full Keyboard Access
on both the panel and the main window; the shared `ControlViews` carry the slider,
meter, and picker labels, so a change there affects both surfaces.

## Project layout

```
Package.swift              SwiftPM manifest, three products, one test target
build.sh                   release/debug app bundle + demo IRs
scripts/package-release.sh zip, DMG and checksums
scripts/make-icon.swift    regenerates Resources/AppIcon.icns
Sources/IRSKit/            DSP and file I/O
Sources/irsconv/           CLI
Sources/IRSVerb/           menu bar app, main window, onboarding, settings
Tests/IRSKitTests/         33 tests
Resources/Info.plist       bundle metadata
docs/                      technical documentation
```
