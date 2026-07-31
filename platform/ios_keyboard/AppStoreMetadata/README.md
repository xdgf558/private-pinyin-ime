# App Store Metadata

This directory records owner-provided App Store Connect metadata for the iOS
container app and keyboard extension.

STORE-01 adds the reviewed Simplified Chinese listing, privacy audit, screenshot
matrix, review notes, and final submission checklist for the `1.0.0 (27)` App
Store candidate. Owner-only contact, tax, banking, agreement, territory, and
release-control fields remain in App Store Connect and must not be committed.

## Required Owner Inputs

- Apple Developer team ID.
- App bundle ID: `com.privatepinyin.ios`.
- Keyboard extension bundle ID: `com.privatepinyin.ios.keyboard`.
- App Group identifier: `group.com.privatepinyin.ios`.
- Provisioning profiles for the app and extension with the App Group capability.
- Confirm the published support and privacy policy URLs.
- Capture and approve the iPhone and iPad screenshots listed in
  `screenshot_checklist.md`.
- Complete the review contact, age rating, agreements, tax, banking, pricing,
  territories, and release-control fields in App Store Connect.
- Product decision for whether iOS learning may require Full Access.

## Local Signing Files

Copy `Signing.env.example` to ignored `Signing.env` and update the values for
the Apple Developer account. Copy `ExportOptions.plist.template` to ignored
`ExportOptions.plist` for a local export, or copy
`ExportOptions.upload.plist.template` for TestFlight upload. Make sure the
`teamID` and `provisioningProfiles` keys match the same bundle IDs used in
`Signing.env`.

The release script refuses to archive unless all four identifiers are supplied:

- `PRIVATE_PINYIN_IOS_TEAM_ID`
- `PRIVATE_PINYIN_IOS_APP_BUNDLE_ID`
- `PRIVATE_PINYIN_IOS_KEYBOARD_BUNDLE_ID`
- `PRIVATE_PINYIN_IOS_APP_GROUP_ID`

For upload mode, set `destination` to `upload` in `ExportOptions.plist`.
External TestFlight builds must not set `testFlightInternalTestingOnly=true`;
that key makes the uploaded build internal-only and prevents external test group
assignment. Provide all three App Store Connect API key variables when using the
scripted upload path:

- `PRIVATE_PINYIN_IOS_ASC_KEY_PATH`
- `PRIVATE_PINYIN_IOS_ASC_KEY_ID`
- `PRIVATE_PINYIN_IOS_ASC_ISSUER_ID`

After a successful upload, update `docs/ios_testflight_upload_record.md` with
the App Store Connect build number, processing state, and distribution status.

## Privacy Notes

- The keyboard extension requests `RequestsOpenAccess=false` by default.
- The keyboard extension does not use Swift network APIs.
- User learning is off by default and should remain disabled if the keyboard
  cannot access shared App Group storage without Full Access.
- App Store privacy labels should report no data collection unless future work
  adds an explicitly opted-in feature that changes that posture.
