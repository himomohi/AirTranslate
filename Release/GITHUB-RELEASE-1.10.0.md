# AirTranslate 1.10.0

AirTranslate 1.10.0 adds optional **Grok STT** using SpaceXAI (xAI) **Grok Voice Transcribe 2.0** for microphone and Mac-audio transcription.

## Added

- Select **Grok STT** after saving your own key in **Settings > API Keys > SpaceXAI (xAI)**.
- The key is stored in a separate macOS Keychain item. Starting Grok capture sends the selected audio directly to xAI; provider pricing, access requirements, and account limits apply.

## Changed

- Grok starts with original-only captions and automatic spoken-language recognition. Apple Mode remains the default, other providers remain available, and Apple Translation can be enabled separately.

## Fixed

- Final Grok responses do not duplicate completed utterances, including Japanese utterances joined without spaces.
- Saved Grok transcripts exclude provisional captions and translation-status messages.
- Switching to another engine clears the Grok missing-key notice while preserving unrelated errors.

## Verification Boundary

Local transport/session tests, builds, and app UI checks cover this integration. Real xAI account authentication, speech-recognition accuracy, latency, and quota behavior have **not** been verified with a live API key. A saved key is not proof of provider authorization. See [Grok setup and privacy notes](https://github.com/himomohi/AirTranslate/blob/v1.10.0/docs/grok-stt.md).

## Download

- [Repository](https://github.com/himomohi/AirTranslate)
- [AirTranslate 1.10.0 release](https://github.com/himomohi/AirTranslate/releases/tag/v1.10.0)
- [Latest stable DMG download](https://github.com/himomohi/AirTranslate/releases/latest/download/AirTranslate.dmg)

Version: **1.10.0 / build 1100**. Requires macOS 26 or later on Apple Silicon.

## Distribution Notes

AirTranslate is an independent Apache-2.0 open-source project and is not affiliated with Apple or its optional cloud providers, including SpaceXAI (xAI). DMG and ZIP artifacts are **ad-hoc signed and not Apple-notarized**. macOS may show an unidentified-developer warning on first launch; TCC permission inheritance across updates is not guaranteed. Compare the downloaded DMG with its `.sha256` file and follow [Apple's first-launch guidance](https://support.apple.com/guide/mac-help/mh40616/mac) if needed.
