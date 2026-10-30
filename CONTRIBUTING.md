# Contributing

Thanks for taking a look at Konvolusi. This is a small, focused project: a
system-wide impulse response convolver for macOS, with no other audio effects and
no network features.

## Before you start

- Read [docs/architecture.md](docs/architecture.md) and [docs/dsp.md](docs/dsp.md)
  so changes fit the existing design.
- The DSP must stay allocation-free and lock-free on the audio thread. If a change
  touches `TapCapture`, `AudioEngine.renderOutput`, `PartitionedConvolver.process`,
  or `IRSProcessor.process`, explain how it avoids blocking and allocation.
- Keep the app local-only. Pull requests that add analytics, accounts, automatic
  updates that phone home, or network calls will be declined.

## Build and test

```sh
swift build
swift test
./build.sh
dist/irsconv selftest
```

The test suite must pass. Add a test for every behaviour change, especially in
`IRSKit`. Tests that compare against a naive direct convolution are preferred over
tests that only check “it did not crash”.

## Impulse response policy

**Do not commit a third-party impulse response unless you can prove it may be
redistributed.**

That means a licence file or written permission, with the source recorded next to
the file. “It is all over the internet”, “the pack was free”, and “the author's
README says they do not own it” are not licences. Many popular third-party packs
fall into that category, and some contain measurements of commercial hardware.

Acceptable contributions:

- new generators in `Sources/IRSKit/IRSynthesis.swift`;
- responses you measured yourself and are willing to license under CC0;
- third-party responses with an explicit redistribution licence, placed in a
  clearly named directory with a `LICENSE`/`README` describing the terms.

The repository's generated responses are dedicated to CC0; see
[LICENSE-IRS](LICENSE-IRS). Code contributions are licensed under GPL-3.0-only; see
[LICENSE](LICENSE).

## Commit identity

Commits in the main repository are authored and signed by the maintainer as
`xaepudin`, using a GitHub noreply address and an SSH signing key. Contributors
should use their own identity. Please do not add a personal email address to the
repository, documentation, or test fixtures.

For your own commits, enabling signing is welcome but not required:

```sh
git config commit.gpgsign true
git config gpg.format ssh
git config user.signingkey ~/.ssh/id_ed25519.pub
```

## Pull requests

A good pull request:

- is small enough to review;
- states the user-visible problem and the fix;
- includes tests;
- updates the relevant document under `docs/` if behaviour or limits change;
- does not reformat unrelated code;
- does not include build output (`dist/`, `.build/`), `.DS_Store`, or generated
  iconsets.

For UI changes, include a screenshot or a short description of the panel state.
For audio changes, include the `irsconv benchmark` before/after numbers and the
machine you measured on.

## Code style

- Follow the surrounding Swift style; no formatter is enforced.
- Prefer clear names and comments that explain *why*, not *what*.
- Keep `IRSKit` free of AppKit/SwiftUI; it is the platform-independent DSP layer.
- Do not add dependencies without discussing it first. The project builds with
  Apple frameworks only.

## Reporting bugs

Open an issue with:

- macOS version and Mac model;
- Konvolusi version and whether it was built from source;
- output device and sample rate;
- the relevant lines from `~/Library/Logs/Konvolusi/app.log`;
- the `--diagnose` report if audio is involved.

Redact local paths and device names if you prefer. Do not attach copyrighted
impulse response files.

Security issues should follow [SECURITY.md](SECURITY.md) instead of a public
issue.
