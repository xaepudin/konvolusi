# Release and publication

This document records how IRSVerb is published. It is also the checklist to
follow for the next release.

## Repository identity

- **GitHub account:** [`xaepudin`](https://github.com/xaepudin)
- **Repository:** `xaepudin/IRSVerb` (public)
- **Default branch:** `main`
- **Commit author and committer:** `xaepudin`
- **Commit email:** the GitHub-provided private address
  (`<id>+xaepudin@users.noreply.github.com`), never a personal address
- **Signatures:** every commit and tag is SSH-signed with the account's signing
  key. GitHub shows **Verified** once that public key is registered under
  **Settings → SSH and GPG keys → New SSH key → Signing key**.

The repository history was rewritten before the first publication so that no
personal email address appears in any commit, signed or otherwise. If history is
ever imported from another machine, check it before pushing:

```sh
git log --format='%h %an <%ae> | %cn <%ce>' --all
git log --show-signature --oneline
```

## Local git configuration

The repository is configured locally, not through a global identity that could
leak into other projects:

```sh
git config --local user.name "xaepudin"
git config --local user.email "<id>+xaepudin@users.noreply.github.com"
git config --local commit.gpgsign true
git config --local tag.gpgsign true
git config --local gpg.format ssh
git config --local user.signingkey ~/.ssh/id_ed25519.pub
```

Replace `<id>` with the numeric GitHub account ID. GitHub displays the exact
private address under **Settings → Emails → Keep my email addresses private**; use
that value verbatim. Do not invent an address, and do not use a personal address
even if it is already in the account.

To verify locally:

```sh
git log --show-signature -1
git verify-commit HEAD
git verify-tag v1.0.0
```

If a signing key is not registered with GitHub, the commit still has a valid local
signature but GitHub cannot mark it **Verified**. Register the public key as a
**signing key** (not only an authentication key) before publishing.

## Pre-release checklist

1. **Clean tree.** `git status --short` is empty apart from ignored build output.
2. **No personal data.** Search the whole tree and history:
   ```sh
   grep -RInE '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}' \
     --exclude-dir=.git --exclude-dir=.build --exclude-dir=dist .
   git log --format='%an <%ae> | %cn <%ce>' --all
   ```
   The only addresses allowed are GitHub noreply addresses and documentation
   placeholders such as `you@example.com`.
3. **No unlicensed impulse responses.** Only the 15 generated responses are
   tracked. See [impulse-responses.md](impulse-responses.md#licensing-and-provenance).
4. **Tests pass.** `swift test` (33 tests) and `dist/irsconv selftest`.
5. **Docs links resolve.** Every relative link in `README.md`, `docs/`, and
   `CONTRIBUTING.md` points to an existing file or anchor.
6. **UI checked.** First-run welcome, main window tabs (Control, Library,
   Diagnostics, About), Settings, and the Dock icon (on by default). Run VoiceOver
   and Full Keyboard Access through the panel and main window.
7. **Version bumped.** `CFBundleShortVersionString`, `CFBundleVersion`, and
   `CHANGELOG.md`.
8. **Release built.** `scripts/package-release.sh`.
9. **Artifacts checked.** Unzip the app, launch it, grant permission, play audio,
   and run the installed copy's `--diagnose`.
10. **Checksums recorded.** The `.sha256` files are attached to the release.

## Build the artifacts

```sh
swift test
./build.sh
dist/irsconv selftest
scripts/package-release.sh
```

The script produces:

```
dist/IRSVerb-1.0.0-macos.zip
dist/IRSVerb-1.0.0-macos.zip.sha256
dist/IRSVerb-1.0.0.dmg
dist/IRSVerb-1.0.0.dmg.sha256
```

The app is ad-hoc signed. If a Developer ID certificate is available, follow
[building.md](building.md#signing-and-notarization) before zipping, then rebuild
the artifacts and verify with `spctl` and `codesign`.

## Publish on GitHub

Create the empty repository once, point `origin` at the `xaepudin` identity, then
push `main` and the annotated, signed tag:

```sh
gh repo create xaepudin/IRSVerb --public \
  --description "System-wide impulse response convolver for macOS"

# On this machine the default git@github.com key authenticates as another
# account, so the remote uses the github-xaepudin SSH alias. Elsewhere, use an
# HTTPS remote with credentials for xaepudin, or add the same alias.
git remote add origin git@github-xaepudin:xaepudin/IRSVerb.git

git push -u origin main
git push origin v1.0.0
```

The tag already exists and is signed. If it needs to be recreated:

```sh
git tag -f -s v1.0.0 -m "IRSVerb 1.0.0"
```

Create the release with the artifacts and generated notes:

```sh
gh release create v1.0.0 \
  dist/IRSVerb-1.0.0-macos.zip \
  dist/IRSVerb-1.0.0-macos.zip.sha256 \
  dist/IRSVerb-1.0.0.dmg \
  dist/IRSVerb-1.0.0.dmg.sha256 \
  --title "IRSVerb 1.0.0" \
  --notes-file docs/release-notes/1.0.0.md
```

If the release notes are kept in `CHANGELOG.md`, use `--notes-from-tag` or pass
`--notes` instead.

## What users download

- **`IRSVerb-<version>-macos.zip`** — the app bundle. Preferred; `ditto` preserves
  the bundle structure.
- **`IRSVerb-<version>.dmg`** — a disk image with the app and an `/Applications`
  shortcut.
- **`.sha256` files** — users can verify with `shasum -a 256 -c <file>.sha256`.

The app is not notarized unless a Developer ID was used. The release notes and
README must say so, and give the Control-click → Open / `xattr` workaround. Do not
describe an ad-hoc build as “signed and notarized”.

## Repository settings

- Description: “System-wide impulse response convolver for macOS.”
- Topics: `macos`, `audio`, `convolution`, `impulse-response`, `viper4android`,
  `swift`, `core-audio`, `menu-bar`.
- Enable Issues; Discussions optional.
- Releases: attach the zip, DMG, and checksums.
- CI: `.github/workflows/ci.yml` on pushes and pull requests; release workflow on
  `v*` tags.
- Do not add a licence that conflicts with `LICENSE` (MIT for code) or
  `LICENSE-IRS` (CC0 for generated responses).

## After publication

- Confirm the repository landing page renders the end-user README.
- Confirm the release assets download and the checksums match.
- Confirm `git log --show-signature` shows the expected signer and that GitHub
  marks commits **Verified**.
- Clone into a fresh directory and follow the README install steps as a new user.
- Run `swift test` and `dist/irsconv selftest` from the fresh clone.
- Check that no email address other than a GitHub noreply address appears on the
  contributors page or in commit metadata.
