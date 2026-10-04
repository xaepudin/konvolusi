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

## Energy

The first version sat at ~12% of a CPU core doing nothing at all, and ~35% while
convolving, which Activity Monitor reported as an energy impact of ~196. Profiling
(`sample`) showed **zero** samples in the audio code while idle — all threads
blocked — but plenty in `CUICatalog _resolvedRenditionKeyFromThemeRef`,
`NSISEngine` and `NSPerformVisuallyAtomicChange`. The cost was SwiftUI: the 20 Hz
meter timer published into `AppModel`, which the `MenuBarExtra` scene observes, so
every meter tick re-laid-out and re-rendered the whole panel **twenty times a
second even while it was closed**.

Three fixes, all in `optimize-energy`:

1. **Meter levels moved out of `AppModel`** into a separate `MeterStore` that only
   the meter views observe, so the menu bar scene is no longer invalidated by them
   (`Sources/IRSVerb/Stores.swift`).
2. **The 20 Hz meter timer only runs while the panel is on screen**; a 1 Hz health
   timer keeps the safety watchdog alive the rest of the time.
3. **DSP work scaled to what the impulse response justifies** — see below.

Measured with `top` (4-sample averages), engine running, panel closed:

| | CPU | POWER | idle wakeups |
| --- | --- | --- | --- |
| Idle, before | 11.7% | 11.7 | 6/s |
| Idle, after | **1.4%** | **1.5** | 8/s |
| Playing (Large Hall), before | — | 26.7 | 228/s |
| Playing (Large Hall), after | **2.7%** | **2.7** | 9/s |

With the panel never opened at all, the same build sits at **0.1%**: the remainder
while playing is the Core Audio IO wakeups, not the convolver (which the benchmark
puts at 0.4% of a core).

One residual caveat: the 20 Hz meter timer starts in `onAppear` and stops in
`onDisappear`. If SwiftUI ever keeps the panel in the hierarchy while hidden,
`onDisappear` may not fire, and the meters keep publishing. That is bounded and
cheap — `MeterStore` is observed only by the two level meters, not by the menu bar
scene that caused the original 11.7% — but it has not been measured with the panel
having been opened and closed.

### Adaptive partitioning

Cost per sample in a uniform-partitioned convolver scales as
`impulseResponseLength / blockSize`: doubling the partition size halves the
frequency-domain multiply-accumulates. The block size is therefore chosen from the
response's length, since a long diffuse reverb already imposes far more perceptual
delay than the block itself:

| Response length | Block | Added latency |
| --- | --- | --- |
| ≤ 0.55 s | 256 | 5.3 ms |
| ≤ 1.7 s | 512 | 10.7 ms |
| longer | 1024 | 21.3 ms |

`irsconv benchmark` measures this without needing audio hardware or permissions:

```
$ dist/irsconv benchmark --irs "Impulse Responses/Large Hall.irs" --seconds 12

  configuration         partitions  latency   noise         silence
  fixed B=256 (before)  488         5.3 ms    59.5x   1.7%  3347x   0.0%
  adaptive (now)        122         21.3 ms   225.4x   0.4% 3138x   0.0%
```

`xRT` is seconds of audio processed per second of CPU, so **4.2x less CPU** for
this response (2.8% -> 0.7% for the 4.4 s Cathedral), and short responses keep
their snappy 5.3 ms block. If you would rather have the old behaviour, use
`IRSProcessor(maxBlockSize: 256)` in `AudioEngine.swift`.

### Silence fast path

Digitally silent input lets the convolver skip its FFTs entirely. The test is
applied to the transform window rather than the incoming hop: the window spans two
hops, so a silent hop whose predecessor is still ringing out must **not** be
skipped. Once every partition in the delay line has been cleared the output is
provably zero, and `testSilenceFastPathIsExact` checks the result against a naive
direct convolution sample for sample.

## The built-in library, and what a useful collection looks like

`irsconv make-ir` writes all fifteen; the app generates them on first run. They
are synthesised (`Sources/IRSKit/IRSynthesis.swift`), which costs no download and
makes room for things nobody records: perception curves and physical models.

The useful realisation is that you do not need five hundred files. You need about
a dozen covering six jobs:

| File | Length | Job | Try at |
| --- | --- | --- | --- |
| Identity (control) | 1 tap | Prove the engine is transparent; A/B reference | 100% |
| Speech Lift | 0.16 s | Rumble out, consonant band up: calls and podcasts on laptop speakers | 100% |
| Night Mode | 0.16 s | Equal-loudness bass/treble lift for quiet listening | 100% |
| Warm Desk | 0.24 s | Barely-there space so headphones stop feeling sealed | 20–30% |
| Studio Room | 0.42 s | General-purpose small space for music | 25–40% |
| Plate | 1.35 s | Dense, bright, no discrete early reflections: classic mix glue | 30–60% |
| Small Room | 0.70 s | Everyday room: obvious but unobtrusive | 20–40% |
| Car Cabin | 0.22 s | Glass comb plus low-end boom; instantly recognisable | 40–70% |
| Stairwell | 1.70 s | Flutter echo off parallel hard surfaces | 25–50% |
| Cassette Tape | 0.12 s | Head bump and a dull top: warm and forgiving | 60–100% |
| Old Radio Speaker | 0.18 s | 1930s box: 60 Hz sits 46 dB below 2.6 kHz | 100% |
| Telephone | 0.12 s | 300 Hz–3.4 kHz band: the "on the phone" effect | 100% |
| Large Hall | 2.60 s | The canonical big reverb | 40–80% |
| Cathedral | 4.40 s | Enormous and slow; impressive, then tiring | 20–40% |
| Tin Can | 0.30 s | Physical model of a thin metal shell: inharmonic modes | 100% |

The six jobs, and why each earns its place:

1. **A control.** `Identity` convolving to nothing is how you prove the effect is
   off, and it separates "the engine is wrong" from "this impulse response is
   wrong" when debugging.
2. **Perception rather than place.** `Night Mode` and `Speech Lift` cannot be
   downloaded, because nobody records an equal-loudness curve. They are ordinary
   filter curves expressed as impulse responses: a way to get EQ out of a
   convolver that has none.
3. **Everyday spaces.** Short and direct-heavy, so they colour without smearing
   timing or destroying speech. These are the ones you leave switched on.
4. **Character.** Radio, telephone, tape, cabin: the Viper4Android-style joy, and
   the reason to own a convolver at all.
5. **Big spaces.** Hall and cathedral. Use them deliberately and at low mix.
6. **One physical model.** `Tin Can` is a bank of damped inharmonic resonances
   rather than a space, and sounds like nothing else here. Its magnitude response
   is three times as ragged as any of the reverberant ones, which is exactly what
   makes it sound like a struck object.

Honest caveat: synthesised *spaces* are plausible rather than measured. A
synthesised short room has a more ragged magnitude response than a real one, so if
one sounds honky, drop the mix or reach for a measured library. The perceptual
curves and the physical model are where synthesis actually wins.

`LibraryTests` asserts this character rather than trusting it: that Speech Lift
really does push 3 kHz up while pulling 60 Hz down, that Night Mode lifts both
extremes, that radio and telephone are band limited, that tape has its head bump,
that the flutter train measurably changes a response, and that Tin Can is modal
rather than diffuse.

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
* **Added latency** is 16 ms for short responses and 32–38 ms for long ones
  (adaptive block engine plus the ring buffer; measured for the 4.4 s Cathedral).
  Long responses are the ones that need the bigger partition to stay cheap — see
  *Energy* below. Use `IRSProcessor(maxBlockSize: 256)` if you would rather have
  5.3 ms and pay 4x the CPU.
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
