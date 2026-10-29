# IRSVerb

**Put a room, a tape machine, a telephone, or a cathedral in the path of everything your Mac plays.**

IRSVerb is a small menu bar app for macOS that applies a Viper4Android-style
`.irs` impulse response to system audio. It is a convolver and nothing else: no
player, no plugin host, no account, no subscription.

```
 every app's audio ──▶ IRSVerb ──▶ your speakers or headphones
                        (your .irs)
```

Load a response and music, videos, calls, and games all come out as if they were
recorded in that space — or through that radio speaker, tape deck, or phone line.

## What you get

- **System-wide processing.** Works with any app that plays audio. There is no
  per-app setup and no virtual audio driver to install.
- **15 built-in impulse responses**, generated on first launch: rooms, halls, a
  cathedral, a plate, a stairwell, a car cabin, a cassette tape, an old radio, a
  telephone, and more.
- **Your own `.irs` files.** Viper4Android `Kernel` folders work as-is. WAV, AIFF,
  CAF, FLAC, and M4A files work too.
- **Wet/dry mix, output gain, bypass, and normalization**, plus live input and
  output meters.
- **Two ways in.** A menu bar panel for quick changes and a conventional window
  with Control, Library, Diagnostics, and About sections in a sidebar. IRSVerb appears in the Dock
  by default so it stays findable when the menu bar is crowded; you can turn that
  off in Settings for a menu-bar-only utility.
- **Low overhead.** Idle cost is around 0.1% of a CPU core; convolution is a few
  percent on Apple silicon.
- **Local only.** No network access, no telemetry, no accounts. Audio is processed
  on your Mac and never leaves it.

## Requirements

- macOS 15 Sequoia or later
- Apple silicon or Intel Mac
- Permission for **System Audio Recording** (macOS asks on first launch)

## Install

1. Download `IRSVerb-<version>-macos.zip` from the
   [latest release](https://github.com/xaepudin/IRSVerb/releases/latest).
2. Unzip it and drag **IRSVerb.app** into `/Applications`.
3. The app is ad-hoc signed and not notarized by Apple, so the first launch needs
   one extra step:
   - In Finder, **Control-click** (or right-click) **IRSVerb.app** and choose
     **Open**, then confirm **Open**; or
   - if macOS still blocks it, run:

     ```sh
     xattr -dr com.apple.quarantine /Applications/IRSVerb.app
     ```

4. Start the app. The main window opens with a welcome sheet explaining the menu
   bar icon and the audio permission.
5. Choose **Open IRSVerb** in the welcome sheet, then allow **System Audio
   Recording** when macOS asks. If you miss the prompt, enable IRSVerb under
   **System Settings › Privacy & Security › Screen & System Audio Recording**,
   then click **Start** in IRSVerb.
6. Play something and pick **Large Hall** to hear the effect immediately.

> **Why the warning?** Apple notarization requires a paid Developer ID
> certificate. This build is signed ad-hoc so it can run, but Gatekeeper cannot
> verify its origin. If you prefer, build it yourself — see
> [docs/building.md](docs/building.md).

## First run

On first launch IRSVerb creates:

```
~/Library/Application Support/IRSVerb/Impulse Responses/
```

and fills it with 15 generated responses. Nothing is downloaded. The first
selection is **Large Hall**; try **Small Room** at 30% for something subtle, or
**Telephone** at 100% for the obvious effect.

A welcome sheet explains the menu bar icon and the permission the first time the
main window opens. If you dismiss it with **Not now**, both the window and the
welcome sheet return on the next launch. You can also reopen it from
**Settings… → Setup → Show the welcome screen again**.

## Using IRSVerb

There are two surfaces:

- **Main window.** Opened on first launch, or from **Open IRSVerb…** in the menu
  bar panel. It has four sections in a sidebar: Control, Library, Diagnostics, and About.
- **Menu bar panel.** Click the waveform icon for quick access to the response
  picker, mix, gain, bypass, normalization, and meters.

IRSVerb is in the Dock by default, so you can reopen the main window by clicking
its Dock icon (or by launching it again from Spotlight/Finder). If you prefer a
menu-bar-only app, turn off **Show IRSVerb in the Dock** in Settings.

The menu bar panel and the main window share the same controls, so a change in one
is reflected in the other.

| Control | What it does |
| --- | --- |
| **Impulse response** | Pick any supported response in the current folder |
| **Add File…** | Use one file from anywhere on disk without changing the folder |
| **Change Folder…** | Point the whole library at your own folder of responses |
| **Open Folder** | Show the current folder in Finder |
| **ⓘ buttons** | Click any info button for an explanation of that control |
| **Mix** | Wet/dry blend. 100% is fully convolved; lower values mix the dry signal back in, time-aligned |
| **Output gain** | Make-up gain after the effect, from −24 dB to +24 dB |
| **Bypass** | Instant A/B without unloading the response |
| **Normalize impulse response** | Match perceived level between responses so switching does not jump in loudness |
| **In / Out meters** | Confirm that audio is being captured and played back |
| **Start / Stop** | Enable or disable processing without quitting |
| **Open IRSVerb…** | Open the main window |
| **Settings…** | Open Settings: Dock visibility, permission shortcut, welcome screen, version |
| **Quit IRSVerb** | Stop processing and restore normal audio immediately |

The footer shows the sample rate, output device, loaded response, added latency,
and buffer diagnostics. Dropouts and drift trims should stay at zero. The level
meters show **Silent** when no audio is being captured.

Hover any control for a one-line explanation, or click the **ⓘ** button next to a
control for a short description. The impulse response picker, Add File, Change
Folder, Open Folder, Mix, Output gain, Bypass, Normalize, Levels, Start/Stop, and
the diagnostic actions all have info.

The **Library** section lists every supported response in the current folder, with
buttons to add a file, change the folder, show it in Finder, normalize, and
refresh. The **Diagnostics** section shows the same status as the footer, with buttons
to open the privacy pane, open the log, show the logs in Finder, and copy a support
report. The **About** section has the version and licence links.

### Keyboard and VoiceOver

- Every window control is reachable with **Full Keyboard Access** (Control-F7 to
  enable it in some macOS versions) and has a VoiceOver label; sliders announce
  their current values and the meters announce decibel levels.
- The menu bar icon announces “IRSVerb, Running” or “IRSVerb, Stopped”.
- The main window uses a standard sidebar, buttons, lists, and text fields, so the
  usual VoiceOver navigation works.
- The main window is independent of the menu bar panel; closing it does not quit
  the app or stop audio processing. The app stays in the Dock and menu bar.

### Mixing tips

- **Rooms, halls, and cathedrals:** 20–50% wet. More sounds impressive for a
  minute and tiring after ten.
- **Character effects** (telephone, radio, tape, tin can): often best at 100%.
- **Headphones:** a little **Warm Desk** at 20–30% takes the sealed-in feeling
  away without sounding like an effect.
- **Laptop speakers:** **Speech Lift** or **Night Mode** at 100% can make quiet
  listening and dialogue clearer.

### The built-in library

| Response | Length | Character | Try at |
| --- | --- | --- | --- |
| Identity (control) | 1 tap | Transparent; useful for A/B tests | 100% |
| Speech Lift | 0.16 s | Cuts rumble, lifts the consonant band | 100% |
| Night Mode | 0.16 s | Equal-loudness bass/treble lift for quiet listening | 100% |
| Warm Desk | 0.24 s | Barely-there space for headphones | 20–30% |
| Studio Room | 0.42 s | General-purpose small room | 25–40% |
| Plate | 1.35 s | Dense, bright mix glue | 30–60% |
| Small Room | 0.70 s | Everyday room | 20–40% |
| Car Cabin | 0.22 s | Glass comb and low-end boom | 40–70% |
| Stairwell | 1.70 s | Flutter echo off hard parallel walls | 25–50% |
| Cassette Tape | 0.12 s | Warm, dull top, gentle head bump | 60–100% |
| Old Radio Speaker | 0.18 s | 1930s box, very band-limited | 100% |
| Telephone | 0.12 s | 300 Hz–3.4 kHz phone line | 100% |
| Large Hall | 2.60 s | The canonical big reverb | 40–80% |
| Cathedral | 4.40 s | Enormous and slow | 20–40% |
| Tin Can | 0.30 s | Struck metal shell, inharmonic modes | 100% |

These are **synthesised**, not recordings of real places. The spaces are
plausible rather than measured; the perceptual curves and the physical model are
where synthesis works best. See
[docs/impulse-responses.md](docs/impulse-responses.md) for how they are made and
how to use your own files.

## Using your own impulse responses

1. Click **Change Folder…** and choose a folder, or **Add File…** for a single file.
2. Select the response in the picker.

For Viper4Android collections, copy the `Kernel` folder to your Mac first, then
point IRSVerb at it:

```
/storage/emulated/0/ViPER4Android/Kernel/                              (Android 9 and earlier)
/storage/emulated/0/Android/data/com.pittvandewitt.viperfx/files/Kernel/  (Android 10+)
```

Supported formats are `.irs`, `.wav`, `.wave`, `.aif`, `.aiff`, `.caf`, `.flac`,
and `.m4a`. Mono and stereo are both fine, any sample rate is resampled on load,
and responses longer than 10 seconds are rejected.

Only use impulse responses you have the right to use. **A file being free to
download does not mean it is free to redistribute.** The repository ships only
responses generated by IRSVerb itself; third-party packs are not included because
their licences are often unclear or absent. See
[docs/impulse-responses.md](docs/impulse-responses.md#licensing-and-provenance).

## Troubleshooting

### The app does not open

Gatekeeper is blocking the ad-hoc build. Control-click the app and choose
**Open**, or remove the quarantine flag:

```sh
xattr -dr com.apple.quarantine /Applications/IRSVerb.app
```

### There is no menu bar icon

The menu bar can hide items when it is crowded or when a notch is present.
IRSVerb is in the Dock by default: click its Dock icon, or open IRSVerb again from
Spotlight/Finder, and the main window appears.

If you turned off **Show IRSVerb in the Dock** and cannot find the menu bar icon,
open the main window directly:

```sh
open -a IRSVerb --args --show-main
```

If IRSVerb is already running, quit it first (the panel's **Quit IRSVerb**, or
Activity Monitor) so the launch option is applied. Then re-enable **Show IRSVerb
in the Dock** in Settings so the app is easy to reach next time.

### No audio is processed

- Open the panel. If it says **Waiting for System Audio Recording permission**,
  enable IRSVerb in **System Settings › Privacy & Security › Screen & System Audio
  Recording** and click **Start**.
- If the panel says **Engine stopped**, click **Start**.
- Make sure only one copy of IRSVerb is running. Two copies fight over the same
  audio and will mute it.
- Play something for a few seconds. Core Audio may not deliver tap buffers until
  audio actually starts.

### System audio became silent

IRSVerb mutes the original audio while it reads the system tap, so a failure in
the output path would otherwise mean silence. A watchdog restarts the engine if
audio keeps arriving but output callbacks stop. If you still hear silence, click
**Stop** and then **Start**, or quit IRSVerb with **Quit IRSVerb** — quitting
always releases the mute.

### Crackles, dropouts, or drift trims

Open the panel and look at the footer. A few trims at startup are normal; a
steadily climbing count is not. Try:

- a shorter impulse response (the **Added latency** line shows the trade-off);
- closing other audio-heavy apps;
- switching the output device once to rebuild the audio graph.

For a detailed report, see [docs/diagnostics.md](docs/diagnostics.md).

### macOS asks for permission again after an update

The ad-hoc signature changes whenever the app is rebuilt, so macOS may treat it as
a new app. Enable it again in System Settings, or build with a stable signing
identity. See [docs/building.md](docs/building.md#signing-and-notarization).

### Latency feels high

Added latency depends on the response length and is chosen automatically:

| Response length | Added latency |
| --- | --- |
| 0.55 s or shorter | about 5 ms |
| 0.55–1.7 s | about 11 ms |
| longer than 1.7 s | about 21 ms |

plus output buffering (roughly 11–17 ms in practice). Use a shorter response if
you need tighter timing. The technical details are in
[docs/dsp.md](docs/dsp.md#latency-and-partitioning).

## Privacy

IRSVerb captures the audio your Mac is playing so it can convolve it and play the
result back. That is the whole data flow:

- no network code, no analytics, no crash reporting, no accounts;
- audio is processed in memory and is not written to disk;
- the app writes only local logs under `~/Library/Logs/IRSVerb/`, and the
  built-in responses under `~/Library/Application Support/IRSVerb/`.

The System Audio Recording permission is powerful — treat it like screen
recording. You can revoke it at any time in **System Settings › Privacy &
Security › Screen & System Audio Recording**.

## Uninstall

1. Open the panel and choose **Quit IRSVerb** (this releases the audio mute).
2. Drag **IRSVerb.app** to the Trash.
3. Optionally remove your settings, logs, and generated responses:

   ```sh
   rm -rf ~/Library/Application\ Support/IRSVerb
   rm -rf ~/Library/Logs/IRSVerb
   ```

## Build from source

```sh
git clone https://github.com/xaepudin/IRSVerb.git
cd IRSVerb
./build.sh
open dist/IRSVerb.app
```

Full instructions, CLI usage, testing, and release packaging are in
[docs/building.md](docs/building.md).

## Documentation

| Document | Contents |
| --- | --- |
| [docs/README.md](docs/README.md) | Documentation index |
| [docs/building.md](docs/building.md) | Build, test, CLI, packaging, signing |
| [docs/architecture.md](docs/architecture.md) | Audio pipeline, threading, lifecycle |
| [docs/dsp.md](docs/dsp.md) | Convolution, latency, normalization, performance |
| [docs/impulse-responses.md](docs/impulse-responses.md) | `.irs` format, built-in library, licensing |
| [docs/diagnostics.md](docs/diagnostics.md) | Permissions, logs, `--diagnose`, benchmarks |
| [docs/release.md](docs/release.md) | Release checklist and publication |

## Contributing

Issues and pull requests are welcome. Please read
[CONTRIBUTING.md](CONTRIBUTING.md) first, especially the rule about not
committing impulse responses without a clear redistribution licence.

## Licence

- **Source code:** [MIT](LICENSE).
- **Generated impulse responses** in `Impulse Responses/`: [CC0 1.0](LICENSE-IRS)
  (public domain dedication). Use them in music, videos, and anything else
  without attribution.

IRSVerb is not affiliated with Viper4Android or its authors. “Viper4Android” is
used only to describe the `.irs` file format and workflow.
