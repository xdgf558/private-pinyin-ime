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

## Later Stages

- UPDATE-02: download the declared signed/notarized pkg, verify byte size and
  SHA-256, re-check Developer ID/notarization, and hand it to macOS Installer
  with visible user consent. No silent privileged install.
- UPDATE-03: detect stale input-method processes after installation and provide
  the least disruptive supported action: reload guidance first, logout/login
  when required, and a restart prompt only when macOS actually requires it.
- Windows: keep its update channel separate until signed x64/x86 installer
  evidence and TSF upgrade/uninstall smoke tests are complete.
- iOS: continue to use App Store and TestFlight updates only.
