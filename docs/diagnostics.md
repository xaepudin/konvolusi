# Diagnostics

Konvolusi touches a privileged part of macOS: it taps all system audio and mutes
the original while it reads it. When something is wrong, start with the app's own
panel and logs rather than guessing.

## First checks

1. **Is the engine running?** The menu bar icon gains a filled waveform and the
   panel header says **Running** when `.running`.
2. **Is the permission granted?** The panel says **Waiting for System Audio
   Recording permission** if setup failed. Enable Konvolusi under **System Settings
   › Privacy & Security › Screen & System Audio Recording**, then click **Start**.
3. **Is another copy running?** Two instances both tap and mute the same audio.
   Quit the other copy (Activity Monitor → Konvolusi → Quit).
4. **Is anything playing?** Core Audio may not deliver tap buffers until audio
   starts. A silent Mac legitimately produces no callbacks.

The main window's **Diagnostics** section shows the same status lines as the panel
footer and adds buttons to open the privacy pane, open or reveal the log, and copy
a support report. The report contains version, device, sample rate, latency, and
error text — never audio.

## Logs

| File | Contents |
| --- | --- |
| `~/Library/Logs/Konvolusi/app.log` | Lifecycle, engine state, loaded responses, latency, watchdog restarts |
| `~/Library/Logs/Konvolusi/diagnostic.log` | The last `--diagnose` run |

Both are plain text and are appended, not rotated. They contain no audio and no
personal data beyond local file paths and device names. Delete them at any time;
the app recreates them.

```sh
tail -n 50 ~/Library/Logs/Konvolusi/app.log
```

## `--diagnose`

This exercises the real audio path end to end: it creates a tap, plays a system
sound, measures captured and played levels, checks dropouts and latency, and
writes a pass/fail report.

```sh
# Ask LaunchServices to run the app, so the permission is attributed to the app:
open dist/Konvolusi.app --args --diagnose 6

# Or run the executable directly (permission may be attributed to Terminal):
dist/Konvolusi.app/Contents/MacOS/Konvolusi --diagnose 6
```

The argument is the measurement window in seconds (1–60, default 5). The app
exits after the run, so it does not conflict with a running copy.

A passing run looks like:

```
RESULT: PASS — system audio was captured and convolved.
  tap format       : 48000 Hz, 2ch, 32-bit float, interleaved
  peak input level : 0.121902
  peak output level: 0.097533
  ring fill range  : 0…549 frames
  dropouts         : 0 under, 0 over
  drift trims      : 0
  buffers          : tap 256 frames, output 558 frames
  added latency    : 22 ms
```

Exit codes:

| Code | Meaning |
| --- | --- |
| 0 | Pass: audio captured and output produced |
| 2 | The tap could not be created (usually permission) |
| 3 | The tap delivered silence |
| 4 | Captured audio but the output unit produced nothing |
| 5 | Core Audio setup did not finish within 15 seconds |

The command prints to stdout and to `diagnostic.log`. It also warns if another
Konvolusi instance is running, because the two would compete for the mute.

## `irsconv` checks

These need no audio device and no permissions:

```sh
dist/irsconv selftest
dist/irsconv benchmark --seconds 10
dist/irsconv info "Impulse Responses"/*.irs
```

`selftest` checks the unit impulse, FFT-vs-direct convolution, ring-buffer
round-trip, and that all built-in responses write and reload with unit energy. It
exits nonzero on failure, so it is suitable for CI.

`benchmark` reports real-time throughput and CPU share for continuous input and
for digital silence. A healthy Apple-silicon machine should show roughly 50–250×
real time for a 2.6 s response depending on the block size; the absolute numbers
vary by machine and thermal state.

`info` prints channels, sample rate, length, peak, energy, and partition count for
each file. Use it to confirm that a third-party `.irs` actually decodes and is not
silent.

## Reading the panel

| Line | Normal | Investigate if |
| --- | --- | --- |
| Sample rate / device | The current output device | It changes unexpectedly when you switch devices |
| `IR: <name>` | The selected response | `IR error: …` appears, or `IR: none loaded` while audio plays |
| `Added latency` | About 16 ms short, 32–38 ms long | It climbs over time (ring filling without drift control) |
| `Dropouts` | `0 under, 0 over` | Underruns rise during playback (CPU starvation or device trouble) |
| `drift trims` | A few at startup, then stable | It keeps climbing (clock drift or a stalled consumer) |
| `Waiting for audio to play…` | Briefly at startup | It persists while audio is playing (permission or tap problem) |

Input and output meters should move while audio plays. If input moves and output
does not, the convolver or output unit is the problem; if neither moves, the tap
is not delivering.

## Common failures

### Permission prompt never appears

The system may have remembered a denial. Open System Settings → Privacy &
Security → Screen & System Audio Recording, enable Konvolusi (or remove it with the
minus button and relaunch), then click **Start**.

If you rebuilt the app, the ad-hoc signature changed and macOS may treat it as a
new app; the old permission entry may no longer apply.

### Tap created but silence

Check that the output device is not muted and that the app is actually playing.
Try `--diagnose`, which plays a system sound itself. If the diagnostic passes but
normal playback is silent, the issue is the source app or the output route, not
the convolver.

### Dropouts under load

Underruns mean the render callback did not get frames in time. Try a shorter
impulse response (smaller block, less CPU), close other real-time audio apps, or
increase the device buffer. The adaptive block size already trades latency for CPU
on long responses; there is no user-facing buffer-size setting.

### Watchdog restarts

The engine restarts if the tap keeps delivering frames but render callbacks stop
for about 6 seconds. This is a safety net: without it, the system could stay muted
with nothing replacing the audio. A restart appears in `app.log` as
`watchdog: audio arriving but no render callbacks`. If it repeats, check the output
device and `coreaudiod`.

### Logs contain paths

Logs include local file paths and device names. Remove or redact them before
posting publicly. There is no email address, account identifier, or audio content
in the logs.
