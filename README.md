# IRSVerb

A Viper4Android-style **impulse response convolver for macOS** — the "Convolver"
effect from V4A, and nothing else.

Load a `.irs` file and everything your Mac plays comes out as if it were
recorded in a cathedral, a small room, an old radio speaker, or whatever
response you feed it. It is system-wide: not a player, not a plugin host.

```
system audio ──▶ Core Audio process tap ──▶ ring buffer ──▶ FFT convolver ──▶ output unit
                     (other apps)                            (your .irs)
```

The tap mutes the original audio at the hardware for exactly as long as IRSVerb
is reading it, so you hear the convolved signal once — not the dry signal plus
an effect.

## Quick start

```sh
./build.sh                 # builds dist/IRSVerb.app and dist/irsconv
open dist/IRSVerb.app      # menu bar icon appears; audio processing starts
```

On first launch the app creates
`~/Library/Application Support/IRSVerb/Impulse Responses/` and fills it with five
generated impulse responses (Cathedral, Large Hall, Small Room, Old Radio
Speaker, Telephone), so there is something to listen to before you dig out your
own V4A files.

macOS will ask for **System Audio Recording** permission the first time. If you
miss the prompt, grant it in *System Settings › Privacy & Security › Screen &
System Audio Recording*, then restart the app.

To quit, use **Quit IRSVerb** at the bottom of the menu bar panel. Quitting
destroys the tap and immediately restores normal audio.

## The menu bar app

| Control | What it does |
| --- | --- |
| Impulse response picker | Every `.irs`/`.wav`/`.aif` file in the selected folder |
| Choose .irs… | Add a single file from anywhere (V4A's `ViPER4Android/Kernel` folder works) |
| Folder… | Point the library at your own impulse response folder |
| Reveal | Open that folder in Finder |
| Mix | Wet/dry. 100% is pure convolution; lower values blend the dry signal back in, time-aligned |
| Output gain | ±24 dB of make-up gain after the convolver |
| Bypass | Instant A/B, with no added latency |
| Normalize impulse response | Energy-normalize on load so switching responses does not jump in loudness |
| In / Out meters | Live levels, useful for confirming the tap is actually capturing |

The footer shows the running sample rate and output device, the loaded response,
the added latency, and ring-buffer diagnostics.

## Command line: `irsconv`

Also useful for checking the DSP without listening:

```sh
dist/irsconv selftest
#   PASS  unit impulse is a pure delay
#   PASS  FFT convolution matches direct convolution
#   PASS  ring buffer round trip
#   PASS  demo impulse responses write and reload (16-bit .irs)

dist/irsconv render song.wav --irs "Impulse Responses/Cathedral.irs" --out out/
dist/irsconv render song.wav --irs hall.irs --wet 0.5 --gain-db -3 --bits 24
dist/irsconv info "Impulse Responses"/*.irs
dist/irsconv make-ir --out "Impulse Responses"
```

`render` resamples the impulse response to the input file's sample rate (or to
`--rate`), streams the audio through the *same* convolver the live app uses, and
reports the level change:

```
song.wav: 71638 frames @ 48000 Hz
  in  peak +0.36  rms -29.55 dBFS
  out peak +0.23  rms -34.06 dBFS  (delta -4.51 dB)
  -> out/song - Large Hall.wav
     196437 frames, 488 partitions, block 256 (5.3 ms) latency
```

## Live diagnostics

```sh
dist/IRSVerb.app/Contents/MacOS/IRSVerb --diagnose 6
# or, so macOS attributes the permission to the app rather than your terminal:
open dist/IRSVerb.app --args --diagnose 6
```

It creates a real tap, plays a system sound, measures the captured and played
levels, and writes a report to `~/Library/Logs/IRSVerb/diagnostic.log`.

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

The running app also keeps a small log at `~/Library/Logs/IRSVerb/app.log`.

## How the convolution works

`PartitionedConvolver` is a uniform-partitioned overlap-save FFT convolver
(the standard real-time scheme): the impulse response is split into 256-sample
partitions, each transformed once with `vDSP_fft_zrip`, and each incoming hop is
transformed once and accumulated against every partition spectrum held in a
frequency-domain delay line.

* Cost is independent of impulse response *length* per hop, so a 4.4 s cathedral
  response stays cheap.
* Input always leads output within a call, so `output[i]` is the convolution of
  `input[i]` delayed by exactly 256 samples no matter how the caller chops up its
  buffers. That determinism is what keeps the dry/wet mix phase-aligned and the
  offline renderer sample-accurate.
* The vDSP conventions used here were measured rather than assumed: the real-FFT
  round trip scales by `2 × fftSize`, `vDSP_zvma` does not conjugate, and the
  packed bin 0 holds (DC, Nyquist) so it is multiplied component-wise. The test
  suite checks all of this against a naive direct convolution.

Loading a response is done on a background queue and published to the audio
thread with an atomic pointer swap; the previous response is kept alive for a
few seconds so an in-flight render callback can finish with it.

## Layout

```
Sources/IRSKit/          platform-independent DSP (also usable elsewhere)
  PartitionedConvolver   the FFT convolver
  IRSProcessor           stereo pair + dry/wet + gain + bypass
  IRFile                 .irs / WAV loading, resampling, writing
  ImpulseResponse        buffer type, biquads, deterministic noise
  IRSynthesis            generates the demo impulse responses
  RingBuffer             lock-free SPSC ring, atomic level meters
Sources/irsconv/         the CLI
Sources/IRSVerb/         the menu bar app
  SystemAudioTap         process tap + private tap-only aggregate device
  TapCapture             IO thread → ring buffer
  OutputUnit             AUHAL default output unit
  AudioEngine            glue, drift control, device-change handling, watchdog
  AppModel / PanelView   SwiftUI menu bar UI
  Diagnostics            --diagnose
Tests/IRSKitTests/       19 tests
```

## Notes and limits

* **Only the convolver.** No other Viper4Android effects (no EQ, bass boost,
  spectrum extend, cure, field surround, …). That was the requirement.
* **Added latency** is about 20–25 ms: 5.3 ms of block engine plus the ring
  buffer prefill. Fine for music and reverb; on the edge for lip-sync-critical
  video.
* **`.irs` files are plain WAV files** with an unusual extension; mono or stereo,
  any sample rate (resampled on load), 16/24/32-bit or float. Responses longer
  than 10 s are rejected.
* **Ad-hoc signing.** The bundle is signed with `-` (ad-hoc), which is enough for
  Core Audio taps, but the signature changes on every rebuild, so macOS may ask
  for the system audio permission again after you rebuild. Signing with a stable
  certificate instead removes that annoyance.
* **The permission prompt blocks Core Audio, not the UI.** `AudioHALCreateIOProc`
  (and therefore tap setup) can sit inside a synchronous IPC to `coreaudiod`
  while the permission dialog is unanswered, so setup runs on its own queue and
  the menu bar stays responsive. If you deny the prompt, the panel says so and
  nothing is muted.
* **One instance at a time.** Two IRSVerb instances would both tap and mute the
  same audio and fight over it. The diagnostic warns if one is already running.
* **Drift control.** The tap and the output unit normally share one hardware
  clock. If they ever drift apart, the ring is trimmed one frame at a time rather
  than letting latency creep; the menu panel shows the trim count.
* **Watchdog.** Because reading a tap mutes the system, a stalled output path
  would mean silence. The app watches the render callbacks and restarts the
  engine (releasing the mute) if they stop.
