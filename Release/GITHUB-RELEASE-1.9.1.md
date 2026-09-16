# AirTranslate 1.9.1

AirTranslate 1.9.1 improves floating captions for users who keep subtitles above videos, meetings, lectures, interviews, and streams.

AirTranslate is an independent open-source project and is not affiliated with Apple, OpenAI, Google, Meta, Microsoft, Azure, or Nari.

## Added

- Added precise #RRGGBB color-code input with keyboard Apply for caption text and background colors.

- The floating caption window can be resized in both width and height.
- Hover affordances make the floating caption window easier to move and resize.
- Floating captions support a custom font size while preserving the existing preset sizes.
- Floating captions support text color, background color, and background opacity controls that do not fade caption text.
- Floating caption window and style preferences persist across launches and can be reset.

## Scope

- Apple Mode remains the default local-first transcription and translation path.
- Nari STT, Azure MAI, Meta Scribe, GPT, and Gemini remain optional provider modes that require user-provided credentials where applicable.
- Existing Caption Stability choices remain the readability timing control while floating-caption size, color, and background opacity are customized separately.
- Real Nari account authorization, live service connectivity, provider quota, real microphone or Mac-audio accuracy, and latency remain unverified unless a separate live provider smoke test is recorded.
- This release does not change the existing ad-hoc signing and non-notarized distribution status.

## Download

- [Repository](https://github.com/himomohi/AirTranslate)
- [AirTranslate 1.9.1 release](https://github.com/himomohi/AirTranslate/releases/tag/v1.9.1)
- [Latest stable DMG download](https://github.com/himomohi/AirTranslate/releases/latest/download/AirTranslate.dmg)

## Distribution Notes

AirTranslate remains fully open-source under the Apache-2.0 License. Release DMG and ZIP artifacts are ad-hoc signed and are not Apple-notarized; macOS may show an unidentified-developer warning on first launch, and TCC permission inheritance across updates is not guaranteed. Compare `AirTranslate.dmg.sha256` with the downloaded DMG checksum. If macOS blocks the app, follow [Apple's first-launch instructions](https://support.apple.com/guide/mac-help/mh40616/mac).
