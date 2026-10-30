# DSP

This document describes what happens to the samples between the tap and the
output unit. It assumes familiarity with convolution and the FFT.

## Signal path

```
planar float32 stereo
        │
        ▼
  IRSProcessor
   ├─ bypass? ────────────────────────────────▶ pass-through (no added latency)
   ├─ dry branch: delay by block latency ─────┐
   └─ wet branch: two PartitionedConvolvers ──┤
                                              ▼
                                    wet * IR + (1 - wet) * dry
                                              │
                                              ▼
                                      output gain (±24 dB)
                                              │
                                              ▼
                                        planar float32
```

The processor is stereo. A mono impulse response is used for both channels; a
stereo response keeps its two channels decorrelated. Input and output are planar
float32, non-interleaved, at the tap's sample rate. The output unit uses the same
client format, so any hardware rate conversion is Core Audio's responsibility.

## Uniform-partitioned overlap-save convolution

`PartitionedConvolver` implements the standard real-time scheme (Wefers, Gardner):
the impulse response is split into `blockSize`-sample partitions, each transformed
once at load time. Incoming audio is collected into hops of `blockSize` samples;
each completed hop is transformed once and accumulated against every impulse
response partition in a frequency-domain delay line.

For an impulse response of `L` samples and a partition size `B`:

- partition count = `ceil(L / B)`;
- FFT size = `2B` (the overlap-save window);
- frequency-domain multiply-accumulates per hop = `ceil(L / B)`.

Because the partitions are precomputed, cost per sample scales with
`L / B`. Doubling the partition halves the multiply-accumulates at the cost of
doubling the block latency.

Implementation details:

- `vDSP_fft_zrip` performs the real FFT; spectra are held in split-complex form.
- `vDSP_zvma` accumulates `D = A*B + C`; it does **not** conjugate.
- The packed bin 0 contains (DC, Nyquist) and is multiplied component-wise.
- The real-FFT round trip scales by `2 × fftSize`, so the inverse scaling is
  `1 / (4 × fftSize)`. These conventions were measured against a naive direct
  convolution, not assumed.

The convolver is fed and drained with equal frame counts, but input leads output
within a call. `output[i]` is the convolution of `input[i]` delayed by exactly
`blockSize` samples regardless of how the caller chunks its buffers. That
determinism is what keeps the dry/wet mix phase-aligned and the offline renderer
sample-accurate. The test suite compares the FFT path with a naive direct
convolution for several block sizes, impulse lengths, and chunk patterns.

## Latency and partitioning

`IRSProcessor` picks the partition size from the impulse response length:

| Response length | Block size | Convolver latency |
| --- | --- | --- |
| ≤ 0.55 s | 256 | 5.3 ms at 48 kHz |
| ≤ 1.7 s | 512 | 10.7 ms at 48 kHz |
| > 1.7 s | 1024 | 21.3 ms at 48 kHz |

The rationale: a long diffuse reverb already imposes perceptual delay, so paying
a few more milliseconds to halve its CPU cost is a good trade. Short colouration
responses stay snappy. The engine's `maxBlockSize` is 1024 in the live app and 256
in the offline renderer (where latency does not matter and sample accuracy does).

End-to-end latency is larger than the block latency because of the ring buffer:

```
added latency = convolver block latency + ring occupancy (at least the target)
```

In practice that is about 16 ms for short responses and 32–38 ms for a 4.4 s
cathedral, depending on device buffer sizes. The panel shows the measured figure.

To force the old fixed-256 behaviour, construct `IRSProcessor(maxBlockSize: 256)`
in `AudioEngine`; this gives 5.3 ms at the cost of roughly 4× the convolution CPU
for long responses.

## Silence fast path

Digitally silent input can skip the FFTs entirely. The check is applied to the
two-hop transform window, not the incoming hop: a silent hop whose predecessor is
still ringing out must **not** be skipped, because the window still contains
nonzero samples. Once every partition in the delay line has seen silence, the
output is provably zero and the engine bypasses the transform/multiply/inverse
work. `testSilenceFastPathIsExact` compares the result against direct convolution
sample for sample, and a companion test verifies that near-silence (nonzero
samples) does not take the fast path.

This matters for the common case of a Mac that is idle or between tracks: it
removes the convolver from the power budget when there is nothing to convolve.

## Dry/wet alignment

Both branches must be time-aligned for a mix to work. The wet branch is delayed by
the block engine; the dry branch therefore runs through a delay line of the same
length. The dry delay line is allocated at the maximum block size so switching
responses never allocates on the audio thread. At 0% wet the output is the dry
signal; at 100% it is the convolved signal; in between the two add.

## Bypass

Bypass is a pass-through that does not touch the ring or the convolver state. It
adds no latency, so an A/B comparison does not shift time. Un-bypassing resumes
with the existing convolution history rather than a reset, which avoids a click
on the transition (the panel's Stop/Start path does reset).

## Normalization

A long impulse response spreads the same input energy over more samples, so
switching from a short room to a cathedral at the same gain would usually get
much quieter. `normalizeEnergy()` scales the impulse response so its total L2
energy is 1:

```
gain = 1 / sqrt(sum over channels and samples of x[n]²)
```

Convolving a signal with a unit-energy response preserves that signal's energy,
which keeps perceived loudness roughly constant across responses. Normalization is
on by default and can be disabled in the panel or with `--no-normalize` in
`irsconv`. A silent impulse response is rejected rather than normalized.

Normalization is not loudness matching in the psychoacoustic sense — a bright
plate and a dark room at the same energy can still differ in perceived level — but
it removes the large, obvious jumps.

## Resampling

Impulse responses can be any sample rate. `IRFile.load(targetSampleRate:)` uses
`AVAudioConverter` to resample to the running tap rate before the FFT partitions
are built. The audio input path is never resampled: the output unit uses the tap's
rate, and Core Audio handles the hardware conversion. In `irsconv render`, both
the input and the impulse response are brought to the requested rate (the input's
rate by default) with the same converter.

Responses longer than 10 seconds are rejected (`IRFile.maximumDuration`). This is
a memory/CPU guard as well as a usability one: a 10 s stereo response at 48 kHz is
about 3.8 MB of float samples before partitioning.

## Performance

Current profile, measured 2026-10-30 on this MacBook Pro with `top` (1-second
samples), Large Hall, macOS 27.2:

| State | CPU | Notes |
| --- | --- | --- |
| Menu bar only, engine running, nothing playing | 0.0–1.0% | output running with silence; FFT fast path skips work |
| Menu bar only, Large Hall playing | 0.6–5.9%, typically 2–4% | Core Audio callbacks plus convolution |
| Main window open, live meters | 5–6% | the 20 Hz meter redraw dominates, not the DSP |
| Main window closed | returns to menu-bar profile | the meter timer now stops on `NSWindow.willClose` |

The main window is the expensive part: its live input/output meters redraw twenty
times a second. The menu bar panel is cheap because it is only on screen while
opened. The `POWER` column in `top` here tracks `%CPU`; it is not a wattage
reading. On battery, expect a modest background drain when the menu bar item is
idle, rising while a long response is playing and noticeably more if the main
window is left open with live meters.

Earlier optimization milestone (same code path, before the current UI):

| State | CPU | Energy impact | Idle wakeups |
| --- | --- | --- | --- |
| Idle before the optimization work | 11.7% | 11.7 | 6/s |
| Idle after | 1.4% | 1.5 | 8/s |
| Playing Large Hall before | — | 26.7 | 228/s |
| Playing Large Hall after | 2.7% | 2.7 | 9/s |
| Panel never opened | 0.1% | — | — |

The idle cost was not the DSP: profiling showed zero samples in the audio code
while idle. SwiftUI was re-laying-out the whole `MenuBarExtra` scene twenty times
a second because meter values were published through `AppModel`. Moving meters
into `MeterStore`, running the 20 Hz timer only while the panel is visible, and
scaling DSP work to the impulse response brought the cost down.

`irsconv benchmark` measures convolution throughput without audio hardware or
permissions. For a 4.4 s response:

```
configuration         partitions  latency   noise         silence
fixed B=256 (before)  488         5.3 ms    59.5x   1.7%  3347x   0.0%
adaptive (now)        122         21.3 ms   225.4x   0.4% 3138x   0.0%
```

`xRT` is seconds of audio processed per second of CPU, so adaptive partitioning is
about 4.2× cheaper for this response. The apparent latency difference in the
benchmark is the convolver block only; the live app's ring buffer dominates the
real end-to-end figure.

## Test coverage

The 33 XCTest cases cover, among other things:

- FFT convolution vs. naive direct convolution, including non-multiple partition
  lengths and odd chunk sizes;
- the unit impulse being a pure delay;
- reset and history clearing;
- dry/wet phase alignment for long responses;
- bypass being latency-free;
- gain in dB round-tripping;
- the silence fast path being exact and only triggering on digital silence;
- ring-buffer wrap-around, underrun, and overrun accounting;
- the built-in library's measured character (band limits, shelves, head bump,
  flutter, modal vs. diffuse decay).

Run them with `swift test`; see [building.md](building.md).
