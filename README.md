# Konvolusi

**Rediscover the songs you love.**

Put a room, a tape machine, a telephone, or a cathedral in the path of everything
your Mac plays. Konvolusi is a small menu bar app for macOS that applies an `.irs`
impulse response to system audio. It is a convolver and nothing else: no player, no
plugin host, no account, no subscription.

```
 every app's audio ──▶ Konvolusi ──▶ your speakers or headphones
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
- **Your own `.irs` files.** Add `.irs`, WAV, AIFF, CAF, FLAC, or M4A files; they
  are copied into Konvolusi's library and can be removed again.
- **Wet/dry mix, output gain, bypass, and normalization**, plus live input and
  output meters.
- **Two ways in.** A menu bar panel for quick changes and a conventional window
  with Control, Library, Diagnostics, Settings, and About sections in a fixed
  sidebar. Launching Konvolusi opens the window; closing it returns the app to
  menu-bar-only background operation.
- **Low overhead.** With only the menu bar item, idle is typically under 1% of a CPU
  core and a long response is about 2–4%. The main window's live meters cost about
  5–6% while it is open; close it for the lowest battery use.
- **Local only.** No network access, no telemetry, no accounts. Audio is processed
  on your Mac and never leaves it.

## Requirements

- macOS 15 Sequoia or later
- Apple silicon or Intel Mac
- Permission for **System Audio Recording** (macOS asks on first launch)

## Install

1. Download `Konvolusi-<version>-macos.zip` from the
   [latest release](https://github.com/xaepudin/konvolusi/releases/latest).
2. Unzip it and drag **Konvolusi.app** into `/Applications`.
3. The app is ad-hoc signed and not notarized by Apple, so the first launch needs
   one extra step:
   - In Finder, **Control-click** (or right-click) **Konvolusi.app** and choose
     **Open**, then confirm **Open**; or
   - if macOS still blocks it, run:

     ```sh
     xattr -dr com.apple.quarantine /Applications/Konvolusi.app
     ```

4. Start the app. The main window opens with a welcome sheet explaining the menu
   bar icon and the audio permission.
5. Choose **Open Konvolusi** in the welcome sheet, then allow **System Audio
   Recording** when macOS asks. If you miss the prompt, enable Konvolusi under
   **System Settings › Privacy & Security › Screen & System Audio Recording**,
   then click **Start** in Konvolusi.
6. Play something and pick **Large Hall** to hear the effect immediately.

> **Why the warning?** Apple notarization requires a paid Developer ID
> certificate. This build is signed ad-hoc so it can run, but Gatekeeper cannot
> verify its origin. If you prefer, build it yourself — see
> [docs/building.md](docs/building.md).

## First run

On first launch Konvolusi creates:

```
~/Library/Application Support/Konvolusi/Impulse Responses/
```

and fills it with 15 generated responses. Nothing is downloaded. The first
selection is **Large Hall**; try **Small Room** at 30% for something subtle, or
**Telephone** at 100% for the obvious effect.

A welcome sheet explains the menu bar icon and the permission the first time the
main window opens. If you dismiss it with **Not now**, both the window and the
welcome sheet return on the next launch. You can also reopen it from
**Settings… → Setup → Show the welcome screen again**.

## Using Konvolusi

There are two surfaces:

- **Main window.** Opened on first launch, or from **Open Konvolusi…** in the menu
  bar panel. It has five sections in a fixed sidebar: Control, Library, Diagnostics,
  Settings, and About. The sidebar cannot collapse.
- **Menu bar panel.** Click the Konvolusi ring icon for quick access to the response
  picker, mix, gain, bypass, normalization, and meters.

The app appears in the Dock and ⌘-Tab while the main window is open. Closing the
window removes it from both, but it is not quitting: audio processing keeps
running, the menu bar icon stays, and the live meters stop so the app drops back to
its menu-bar CPU profile. To show the window again, use the menu bar or launch
Konvolusi again from Spotlight/Finder — the existing process is reused, not
duplicated. **Quit Konvolusi** from the menu bar panel stops audio and exits.

The menu bar panel and the main window share the same controls, so a change in one
is reflected in the other.

| Control | What it does |
| --- | --- |
| **Impulse response** | Pick a built-in response or one you added |
| **Add IR…** | Choose one or more files; they are copied into the library |
| **Remove** | Delete the selected added IR; built-ins cannot be removed |
| **ⓘ buttons** | Click for explanations of Mix, Output gain, Bypass, Normalize, and Levels |
| **Mix** | Wet/dry blend. 100% is fully convolved; lower values mix the dry signal back in, time-aligned |
| **Output gain** | Make-up gain after the effect, from −24 dB to +24 dB |
| **Bypass** | Instant A/B without unloading the response |
| **Normalize impulse response** | Match perceived level between responses so switching does not jump in loudness |
| **In / Out meters** | Confirm that audio is being captured and played back |
| **Start / Stop** | Enable or disable processing without quitting |
| **Open Konvolusi…** | Open the main window |
| **Settings…** | Open the Settings section: background behavior, permission shortcut, welcome screen, version |
| **Quit Konvolusi** | Stop processing and restore normal audio immediately |

The footer shows the sample rate, output device, loaded response, added latency,
and buffer diagnostics. Dropouts and drift trims should stay at zero. A level
meter is blank while no audio is being captured.

Click the **ⓘ** button next to Mix, Output gain, Bypass, Normalize, or Levels for a
short explanation. The impulse response, status, and diagnostics areas intentionally
stay free of extra info.

The **Library** section lists the built-in responses plus the IRs you added, with
buttons to add, remove, normalize, and refresh. The **Diagnostics** section shows
the same status as the footer, with buttons to open the privacy pane, open the log,
show the logs in Finder, and copy a support report. The **About** section has the
version and licence links. **Settings** is a normal sidebar section, so it uses the
same main window as the rest of the app; the menu bar panel's **Settings…** button
opens that section directly.

### Keyboard and VoiceOver

- Every window control is reachable with **Full Keyboard Access** (Control-F7 to
  enable it in some macOS versions) and has a VoiceOver label; sliders announce
  their current values and the meters announce decibel levels.
- The menu bar icon announces “Konvolusi, Running” or “Konvolusi, Stopped”.
- The main window uses a standard sidebar, buttons, lists, and text fields, so the
  usual VoiceOver navigation works.
- The main window is independent of the menu bar panel; closing it does not quit
  the app or stop audio processing. The app stays in the menu bar.

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

1. Click **Add IR…** and choose one or more files.
2. Konvolusi copies them into its library and selects the first one.
3. Use **Remove** to delete an added IR. The built-in responses stay available.

Supported formats are `.irs`, `.wav`, `.wave`, `.aif`, `.aiff`, `.caf`, `.flac`,
and `.m4a`. Mono and stereo are both fine, any sample rate is resampled on load,
and responses longer than 10 seconds are rejected. Adding a file does not change
the built-in library or move your original file.

Only use impulse responses you have the right to use. **A file being free to
download does not mean it is free to redistribute.** The repository ships only
responses generated by Konvolusi itself; third-party packs are not included because
their licences are often unclear or absent. See
[docs/impulse-responses.md](docs/impulse-responses.md#licensing-and-provenance).

## Troubleshooting

### The app does not open

Gatekeeper is blocking the ad-hoc build. Control-click the app and choose
**Open**, or remove the quarantine flag:

```sh
xattr -dr com.apple.quarantine /Applications/Konvolusi.app
```

### There is no menu bar icon

The menu bar can hide items when it is crowded or when a notch is present.
Launch Konvolusi again from Spotlight or Finder: the existing process comes forward
and opens the main window, without starting a second instance. Closing that window
returns the app to the menu bar only.

### No audio is processed

- Open the panel. If it says **Waiting for System Audio Recording permission**,
  enable Konvolusi in **System Settings › Privacy & Security › Screen & System Audio
  Recording** and click **Start**.
- If the panel says **Engine stopped**, click **Start**.
- Make sure only one copy of Konvolusi is running. Two copies fight over the same
  audio and will mute it.
- Play something for a few seconds. Core Audio may not deliver tap buffers until
  audio actually starts.

### System audio became silent

Konvolusi mutes the original audio while it reads the system tap, so a failure in
the output path would otherwise mean silence. A watchdog restarts the engine if
audio keeps arriving but output callbacks stop. If you still hear silence, click
**Stop** and then **Start**, or quit Konvolusi with **Quit Konvolusi** — quitting
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

Konvolusi captures the audio your Mac is playing so it can convolve it and play the
result back. That is the whole data flow:

- no network code, no analytics, no crash reporting, no accounts;
- audio is processed in memory and is not written to disk;
- the app writes only local logs under `~/Library/Logs/Konvolusi/`, and the
  built-in responses under `~/Library/Application Support/Konvolusi/`.

The System Audio Recording permission is powerful — treat it like screen
recording. You can revoke it at any time in **System Settings › Privacy &
Security › Screen & System Audio Recording**.

## Uninstall

1. Open the panel and choose **Quit Konvolusi** (this releases the audio mute).
2. Drag **Konvolusi.app** to the Trash.
3. Optionally remove your settings, logs, and generated responses:

   ```sh
   rm -rf ~/Library/Application\ Support/Konvolusi
   rm -rf ~/Library/Logs/Konvolusi
   ```

## Build from source

```sh
git clone https://github.com/xaepudin/konvolusi.git
cd Konvolusi
./build.sh
open dist/Konvolusi.app
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

- **Source code:** [GPL-3.0-only](LICENSE).
- **Generated impulse responses** in `Impulse Responses/`: [CC0 1.0](LICENSE-IRS)
  (public domain dedication). Use them in music, videos, and anything else
  without attribution.
