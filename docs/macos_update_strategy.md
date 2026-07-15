# macOS Update Strategy

This document defines the privacy and security boundary for updating the
website-distributed macOS input method. The update client belongs to the thin
macOS host. The shared Rust input engine remains network-free.

## UPDATE-01: Check And Notify

UPDATE-01 provides version discovery only:

- The input-method menu exposes `检查更新...`.
- Preferences show the current update state and an automatic-check toggle.
- The first-run guide offers the same toggle and leaves it off by default.
- An automatic check runs at most once every 24 hours after the user opts in.
- Strict privacy mode pauses automatic checks. A manual check requires an
  explicit confirmation while strict privacy mode is active.
- An available update opens the trusted release page. UPDATE-01 does not
  download or execute a package.

No network request is made by default. A check sends only a normal HTTPS GET
for a public JSON file. It does not send raw keys, pinyin, candidates, committed
text, user-lexicon data, document context, an account identifier, or telemetry.

## Fixed Endpoint

The app reads exactly this release channel:

```text
https://wwwstationcat.org/updates/private-pinyin/macos/stable.json
```

The URL and allowed host are packaged in `Info.plist`; users cannot configure
an arbitrary endpoint. The client uses an ephemeral `URLSession` with no URL
cache or cookie store, short timeouts, a 128 KiB response limit, and same-host
HTTPS redirect enforcement.

## Manifest Contract

The stable manifest uses schema version 1:

```json
{
  "schema_version": 1,
  "channel": "stable",
  "version": "0.1.21",
  "build": 21,
  "minimum_macos_version": "14.0",
  "published_at": "2026-07-14T08:00:00Z",
  "title": "猫栈拼音 0.1.21",
  "release_notes": ["一条简短更新说明。"],
  "release_page_url": "https://wwwstationcat.org/zh-hans/private-pinyin/",
  "package_url": "https://wwwstationcat.org/downloads/PrivatePinyin-0.1.21.pkg",
  "package_sha256": "64 lowercase or uppercase hexadecimal characters",
  "package_size_bytes": 12345678
}
```

Validation rejects unsupported schemas or channels, malformed numeric
versions, invalid timestamps, empty or oversized user-facing text, non-HTTPS
URLs, foreign hosts, non-PKG package paths, invalid SHA-256 values, and package
sizes outside the declared two-gigabyte ceiling. The package fields are
validated now so later installation stages cannot silently weaken the feed
contract.

## Publisher Order

For each public macOS release:

1. Build, Developer-ID sign, notarize, and staple the pkg.
2. Pass `scripts/check_macos_public_release.sh` and clean-user smoke tests.
3. Upload the immutable versioned pkg and release page.
4. Confirm the downloaded pkg SHA-256 and byte size.
5. Publish `stable.json` last using an atomic website deployment.
6. Fetch the live manifest and pkg from a clean network before announcing the
   release.

If a release must be withdrawn, restore the previous valid manifest. The app
never treats a lower version/build as an update, so rollback requires publishing
a newly signed build with a higher version/build number.

## UPDATE-02: Verified Download And Installer Handoff

UPDATE-02 starts only after the user selects `下载并验证` for a supported newer
version. Automatic version checks never start a package download. The macOS
host then:

1. Downloads only the validated same-host HTTPS `.pkg` URL with an ephemeral
   session, no cookies or URL cache, same-host redirect enforcement, and a
   15-minute resource timeout.
2. Cancels if the transfer exceeds the declared size or if a positive HTTP
   content length disagrees with the manifest. The completed regular file must
   match the declared byte size exactly.
3. Stores at most one package in a private `0700` cache directory with `0600`
   file permissions and deletes failed or superseded packages.
4. Streams the local file through CryptoKit SHA-256 and compares the digest
   with the manifest.
5. Runs `/usr/sbin/pkgutil --check-signature` without a shell and requires the
   Apple distribution status, a `Developer ID Installer` chain, and the pinned
   Station Cat Team ID.
6. Runs `/usr/sbin/spctl --assess --type install --verbose=4` without a shell
   and requires Gatekeeper to report `Notarized Developer ID`.
7. Shows a second confirmation after verification, repeats all local security
   checks immediately before handoff, and opens the package with Apple's system
   Installer application.

No silent privileged installation is permitted. The host never invokes the
`installer` command, never supplies administrator credentials, and never
claims installation success. macOS Installer owns the visible authorization
and installation UI. Any size, digest, signer, notarization, storage, or system
tool failure blocks handoff, removes an untrusted package, and leaves typing
available.

Strict privacy mode cancels an active package transfer when it is enabled.
Local verification may finish because the app starts no additional
application-controlled request. Gatekeeper may consult Apple security services
according to macOS policy; the app supplies only the downloaded package and no
input content, user-learning data, account identifier, or telemetry.

## UPDATE-03: Post-Install Process Refresh

The package `postinstall` script records its completion time and launches the
installed bundle's signed executable as a new UI-only process in the current
console user's Aqua session. It does not use LaunchServices `open`, because
Input Method bundles are not regular launchable apps and can return
`kLSNoExecutableErr`. That helper does not create an `IMKServer` and therefore
cannot compete with the system-owned input-method instance. It
enumerates only running applications whose bundle identifier exactly matches
`com.privatepinyin.inputmethod.PrivatePinyin`, excludes its own PID, and marks
only processes launched no later than package completion as stale.

The recovery order is deliberately narrow:

1. If no stale process exists, continue to the normal setup guide. No process
   action, logout prompt, or restart prompt is shown.
2. If a stale process exists, explain that the user should finish the current
   composition and offer `重新加载猫栈拼音`. Nothing is terminated before this
   explicit click.
3. Immediately before acting, re-enumerate the same bundle identifier and
   intersect it with the originally detected PID set. Request normal
   `NSRunningApplication.terminate()` only for that still-valid set.
4. If those PIDs exit, tell the user to switch away from and back to 猫栈拼音.
   No logout or restart is required.
5. If a PID remains after the bounded wait, ask the user to save work and log
   out, then log back in. The helper never performs the logout itself. A restart
   is not suggested unless a later manual support check proves logout/login was
   insufficient.

No unrelated application is terminated. UPDATE-03 never calls force-terminate,
`kill`, `killall`, `pkill`, AppleScript logout, or system restart commands. The
installer timestamp is accepted only for a short post-install window, and the
helper closes when its last guidance window closes.

## Other Platforms

- Windows: keep its update channel separate until signed x64/x86 installer
  evidence and TSF upgrade/uninstall smoke tests are complete.
- iOS: continue to use App Store and TestFlight updates only.
