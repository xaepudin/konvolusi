# Security policy

## Supported versions

Konvolusi is a local macOS application. Security fixes are applied to the latest
release on `main`; older releases are not maintained.

| Version | Supported |
| --- | --- |
| 1.x | Yes |
| < 1.0 | No |

## Reporting a vulnerability

Please report security issues privately through GitHub's **Security → Report a
vulnerability** flow on the repository, or by opening a draft security advisory.
Do not open a public issue for a vulnerability before a fix is available.

Include:

- affected version and macOS version;
- a description of the issue and its impact;
- reproduction steps, if safe to share;
- any relevant log lines, with personal paths redacted.

You should receive an acknowledgement within a few days. There is no bug bounty.

## Scope

Konvolusi requests the **System Audio Recording** permission, so the most important
security property is that captured audio stays on the machine:

- the app contains no network code and makes no outbound connections;
- audio is processed in memory and is not written to disk;
- logs contain lifecycle messages, file paths, and device names, not audio.

Useful reports include:

- any path that writes captured audio to disk or sends it off-device;
- memory-safety bugs in the real-time audio code (out-of-bounds access, use after
  free, unbounded allocation);
- a malformed `.irs`/WAV/AIFF/FLAC file that crashes the app or causes excessive
  memory use;
- a way to make the app leave system audio muted after a crash, quit, or failed
  startup;
- a packaging or update path that could execute unintended code.

The app is ad-hoc signed unless a release explicitly says otherwise. Gatekeeper
warnings and the documented `xattr` workaround are known limitations, not
vulnerabilities. Reports that require an attacker to already have local code
execution or the user's administrator password are usually out of scope.

## Hardening notes

- The app is not sandboxed; it needs Core Audio process-tap access.
- It does not include an auto-updater or a privileged helper.
- Release artifacts should be downloaded from the official GitHub release and
  verified with the published `.sha256` file.
- A Developer ID signed and notarized build is preferred for distribution; see
  [docs/building.md](docs/building.md#signing-and-notarization).
