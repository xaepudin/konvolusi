# Architecture

IRSVerb is a macOS menu bar app that captures the audio of every other process,
convolves it with an impulse response, and plays the result through the default
output device.

```
┌────────────────────┐     ┌──────────────┐     ┌──────────────────┐     ┌──────────────┐
│ other applications │────▶│ process tap  │────▶│ lock-free ring   │────▶│ IRSProcessor │
│ (system audio)     │     │ (Core Audio) │     │ (SPSC stereo)    │     │ (FFT conv.)  │
└────────────────────┘     └──────────────┘     └──────────────────┘     └──────┬───────┘
                                                                                │
                                                       default output unit ◀────┘
                                                       (AUHAL)
```

The process tap is created with `muteBehavior = .mutedWhenTapped`. While IRSVerb
reads the tap, macOS mutes the original audio at the hardware, so the user hears
the convolved signal exactly once. Destroying the tap restores normal audio.

## Components

| Component | File | Responsibility |
| --- | --- | --- |
| `SystemAudioTap` | `Sources/IRSVerb/SystemAudioTap.swift` | Creates a global stereo process tap excluding IRSVerb's own process, then wraps it in a private aggregate device so it can be read with an IOProc |
| `TapCapture` | `Sources/IRSVerb/TapCapture.swift` | The aggregate device's IOProc. Converts whatever sample layout Core Audio delivers into planar float, writes it to the ring, updates input level and counters |
| `AudioRingBuffer` | `Sources/IRSKit/RingBuffer.swift` | Lock-free single-producer/single-consumer ring. Producers never block; underruns and overruns are counted |
| `OutputUnit` | `Sources/IRSVerb/OutputUnit.swift` | AUHAL default output unit at the tap's sample rate; its render callback pulls from the ring |
| `AudioEngine` | `Sources/IRSVerb/AudioEngine.swift` | Lifecycle, startup sequencing, sample-rate matching, drift control, device-change handling, watchdog counters |
| `IRSProcessor` | `Sources/IRSKit/IRSProcessor.swift` | Owns two partitioned convolvers (L/R), applies dry/wet, output gain, and bypass; publishes new impulse responses atomically |
| `PartitionedConvolver` | `Sources/IRSKit/PartitionedConvolver.swift` | The real-time FFT convolver; see [dsp.md](dsp.md) |
| `IRFile` | `Sources/IRSKit/IRFile.swift` | Decodes `.irs`/WAV/AIFF/CAF/FLAC/M4A via AVFoundation, resamples with `AVAudioConverter`, writes 16/24/32-bit WAV |
| `IRSynthesis` | `Sources/IRSKit/IRSynthesis.swift` | Deterministic generators for the 15 built-in responses |
| `AppModel` | `Sources/IRSVerb/AppModel.swift` | UI state, library folder, selection, timers, watchdog policy, copied diagnostic report |
| `PanelView` | `Sources/IRSVerb/PanelView.swift` | Compact `MenuBarExtra` panel plus entry points to the main window and Settings |
| `ControlViews` | `Sources/IRSVerb/ControlViews.swift` | Shared controls, status header, sliders, and accessible level meters used by both surfaces |
| `MainWindowView` | `Sources/IRSVerb/MainWindowView.swift` | Conventional window with Control, Library, Diagnostics, and About tabs |
| `OnboardingView` | `Sources/IRSVerb/OnboardingView.swift` | First-run explanation of the menu bar icon and audio permission |
| `SettingsView` | `Sources/IRSVerb/SettingsView.swift` | Dock visibility, permission shortcut, welcome-screen reset, version |
| `DockVisibility` | `Sources/IRSVerb/SettingsView.swift` | Applies the optional `.regular` activation policy; default is `.accessory` |
| `MeterStore` / `StatusStore` | `Sources/IRSVerb/Stores.swift` | High-rate meter values and rare status changes, kept out of `AppModel` so they do not invalidate the menu bar scene |
| `Diagnostics` | `Sources/IRSVerb/Diagnostics.swift` | `--diagnose` end-to-end check |

## UI surfaces

| Surface | Scene | Entry point |
| --- | --- | --- |
| Menu bar panel | `MenuBarExtra` (`.window` style) | Waveform icon |
| Main window | `Window("IRSVerb", id: "main")` | First launch, **Open IRSVerb…** in the panel, Dock/Spotlight reopen, or `--show-main` |
| Welcome sheet | `.sheet` on `MainWindowView` | First launch, or **Show the welcome screen again** in Settings |
| Settings | `Settings` scene | **Settings…** in the panel or the standard app menu |

The main window is `.defaultLaunchBehavior(opensMainAtLaunch || !hasCompletedOnboarding ? .presented : .suppressed)`:
first launch opens a real window, while later launches stay menu-bar-only. The
Settings scene is suppressed at launch. The welcome flow is a sheet over the main
window rather than a separate window, so dismissing it cannot leave the app with
no window or trigger AppKit's last-window termination.

`AppDelegate.applicationShouldTerminateAfterLastWindowClosed` returns `false`. This
is essential for a menu bar agent: without it, closing the welcome sheet could
terminate the whole app and remove the menu bar item. Reopening the app from the
Dock or Spotlight posts `.irsVerbOpenMainWindow`; the menu bar label observes it
and calls `openWindow(id: "main")`, so a hidden or crowded menu bar icon is never
the only way to reach the UI.

The app is declared as an agent (`LSUIElement` in `Info.plist`) but `DockVisibility`
defaults to `.regular` so it is findable in the Dock and ⌘-Tab. Turning off
**Show IRSVerb in the Dock** switches the activation policy to `.accessory`; the
preference is applied at launch and when it changes.

On a first launch the engine is **not** started automatically: doing so would put
the System Audio Recording dialog on top of the welcome explanation before it can
be read. `AppModel.startIfReady` starts audio only after
`HasCompletedOnboarding` is true. The welcome sheet's **Open IRSVerb** button sets
that flag and calls `startIfNeeded`; the menu bar **Start** button and the
**Choose/Folder** actions remain explicit user starts at any time.

`--show-main` opens the main window at launch. It is a recovery path for a hidden
menu bar icon and a way to drive the UI in development; it suppresses the welcome
sheet so the requested window is not buried.

## Threads

| Thread / queue | Runs | Real-time? |
| --- | --- | --- |
| Main actor | SwiftUI, `AppModel`, panel timers, engine state publication | No |
| Core Audio IO thread (tap) | `TapCapture.receive` | **Yes** |
| Core Audio render thread (output unit) | `AudioEngine.renderOutput` | **Yes** |
| `io.github.xaepudin.IRSVerb.engine-setup.*` | Tap/aggregate/output creation, which can block on the permission dialog | No |
| `io.github.xaepudin.IRSVerb.ir-loader` | Decoding, resampling, FFT precomputation, then atomic publication | No |

Rules enforced by the code:

- The two real-time callbacks do not allocate, lock, log, or touch AppKit. Logging
  happens at startup/shutdown and on the main queue.
- Impulse responses are decoded and transformed off the audio thread. The finished
  `ConvolverPair` is published with an atomic pointer swap.
- The previous `ConvolverPair` is retained for several seconds after a swap so an
  in-flight render callback can finish reading it.
- UI state that changes quickly (`MeterStore`) is observed by the meter views only.
  Publishing it through `AppModel` would invalidate the entire `MenuBarExtra`
  scene twenty times a second.

## Startup sequence

1. `IRSVerbApp.init` handles `--diagnose` before any UI exists, then creates
   `AppModel` but does not start audio.
2. On `NSApplication.didFinishLaunchingNotification`, `AppModel.start()` runs once.
3. `AppModel` creates the library folder if needed and generates the built-in
   responses on a background queue if the folder is empty.
4. `AudioEngine.start()` moves to `.starting` and performs setup on a private
   queue. This matters because `AudioHardwareCreateProcessTap` can block inside
   `coreaudiod` while the permission prompt is unanswered; the menu bar must stay
   responsive and quittable.
5. Setup creates the tap, the private aggregate device, the ring, the capture
   IOProc, and the output unit.
6. `startOutputWhenReady` waits for evidence that the tap is delivering audio
   (`capturedFrames > 0` and enough ring fill) rather than a fixed delay. It gives
   up after about 60 seconds, trims the startup backlog so it does not become
   permanent latency, and starts the output unit.
7. State becomes `.running` on the main queue. If anything throws, the engine
   moves to `.failed`, destroys the tap, and reports the error.

If the user denies the permission, tap creation fails before the output unit
starts, so nothing is muted and the panel shows a permission hint.

## Buffering and drift

The tap and output unit normally share one hardware clock, so the ring should
stay near its target occupancy. The target is measured from what the devices
actually deliver:

```
base = max(maxTapCallbackFrames, 256)
bufferTargetFrames = base + (maxRenderCallbackFrames > 0 ? maxRenderCallbackFrames : base)
```

Core Audio does not always honor the requested buffer size, which is why the
engine measures the largest callback seen on each side instead of trusting the
HAL's reported size.

If the ring rises above `target + target/2` for five consecutive render
callbacks, the oldest frame is dropped and `driftDrops` increments. The panel
shows this count; a few trims at startup are normal, a steadily climbing count is
not. The ring counts underruns (`missingFrames`, filled with silence) and
overruns (`droppedFrames`) separately.

`totalLatencyFrames` is the convolver's block latency plus the current ring
occupancy (at least the target). That is the honest end-to-end figure shown in
the panel.

## Failure handling

| Failure | Behavior |
| --- | --- |
| System Audio Recording denied or prompt unanswered | Setup throws, state `.failed`, tap destroyed, original audio untouched; panel shows a hint and a settings button |
| Output unit fails to start | The engine stops itself, which destroys the tap and restores audio; state `.failed` |
| Tap keeps delivering but render callbacks stop | The 1 Hz watchdog restarts the engine after roughly 6 seconds, releasing the mute |
| Default output device changes | A 0.5 s debounced listener rebuilds the engine at the new device |
| Impulse response fails to decode | The previous response is kept; the panel shows the error |
| Two instances run at once | Not prevented at runtime. Both taps mute the same audio and compete; `--diagnose` warns if another instance is running |
| App quits | `AppModel.quit()` stops the engine before terminating, destroying the tap and restoring audio |

## State and files

| Item | Location |
| --- | --- |
| Built-in responses and default library | `~/Library/Application Support/IRSVerb/Impulse Responses/` |
| Selected folder, selected response, mix, gain, bypass, normalize | `UserDefaults` (`IRSFolder`, `SelectedIR`, `Wet`, `GainDB`, `Bypassed`, `Normalize`, `SeededDemoLibrary`) |
| Dock visibility | `UserDefaults` (`ShowInDock`) |
| Welcome screen completed | `UserDefaults` (`HasCompletedOnboarding`) |
| App log | `~/Library/Logs/IRSVerb/app.log` |
| Last diagnostic run | `~/Library/Logs/IRSVerb/diagnostic.log` |

The app does not use the network and does not write audio to disk. See
[diagnostics.md](diagnostics.md) for how to inspect a running system.
