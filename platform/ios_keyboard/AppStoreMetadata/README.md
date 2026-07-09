# App Store Metadata

This directory records owner-provided App Store Connect metadata for the iOS
container app and keyboard extension.

Stage 14 includes signing configuration templates and release gates. Do not
treat these files as final marketing copy or privacy declarations until the
owner confirms product name, license, screenshots, support URL, privacy
nutrition labels, and provisioning setup.

## Required Owner Inputs

- Apple Developer team ID.
- App bundle ID: `com.privatepinyin.ios`.
- Keyboard extension bundle ID: `com.privatepinyin.ios.keyboard`.
- App Group identifier: `group.com.privatepinyin.ios`.
- Provisioning profiles for the app and extension with the App Group capability.
- Support URL and privacy policy URL.
- App Store category, age rating, screenshots, subtitle, description, keywords,
  and review notes.
- Product decision for whether iOS learning may require Full Access.

## Local Signing Files

Copy `Signing.env.example` to ignored `Signing.env` and update the values for
the Apple Developer account. Copy `ExportOptions.plist.template` to ignored
`ExportOptions.plist` and make sure the `teamID` and `provisioningProfiles`
keys match the same bundle IDs used in `Signing.env`.

The release script refuses to archive unless all four identifiers are supplied:

- `PRIVATE_PINYIN_IOS_TEAM_ID`
- `PRIVATE_PINYIN_IOS_APP_BUNDLE_ID`
- `PRIVATE_PINYIN_IOS_KEYBOARD_BUNDLE_ID`
- `PRIVATE_PINYIN_IOS_APP_GROUP_ID`

## Privacy Notes

- The keyboard extension requests `RequestsOpenAccess=false` by default.
- The source tree does not use Swift network APIs.
- User learning is off by default and should remain disabled if the keyboard
  cannot access shared App Group storage without Full Access.
- App Store privacy labels should report no data collection unless future work
  adds an explicitly opted-in feature that changes that posture.
