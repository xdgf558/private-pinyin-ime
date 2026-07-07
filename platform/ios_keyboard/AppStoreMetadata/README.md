# App Store Metadata

This directory records owner-provided App Store Connect metadata for the iOS
container app and keyboard extension.

Stage 12 includes templates and release gates only. Do not treat these files as
final marketing copy or privacy declarations until the owner confirms product
name, license, screenshots, support URL, privacy nutrition labels, and
provisioning setup.

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

## Privacy Notes

- The keyboard extension requests `RequestsOpenAccess=false` by default.
- The source tree does not use Swift network APIs.
- User learning is off by default and should remain disabled if the keyboard
  cannot access shared App Group storage without Full Access.
- App Store privacy labels should report no data collection unless future work
  adds an explicitly opted-in feature that changes that posture.
