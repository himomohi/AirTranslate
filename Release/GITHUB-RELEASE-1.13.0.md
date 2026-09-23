# AirTranslate 1.13.0

AirTranslate 1.13.0 adds selectable translated speech output. Apple system speech remains the default, and users can choose Google Gemini 3.8 Flash TTS or Gemini 3.8 Flash-Lite TTS when they want cloud-generated translated speech.

## Added

- **Translated Speech Model** in Settings lets users choose Apple system speech, Google Gemini 3.8 Flash TTS, or Gemini 3.8 Flash-Lite TTS for translated voice output.
- Gemini TTS uses the existing Gemini API key stored in macOS Keychain; no separate Gemini speech key is added.

## Changed

- Gemini speech output speaks only stable translated text instead of provisional caption rewrites.
- AirTranslate does not run its local translated-speech synthesis for realtime audio providers that already synthesize speech, preventing duplicate spoken output.

## Verification Boundary

Local verification can check the Settings choice, model persistence, request construction, and duplicate-speech guard. It does not verify live Gemini account authorization, billing, audio quality, latency, quota, or Google service availability. Qwen Audio 3.1 options from 1.12.0 and the single-instance app behavior from 1.12.1 remain part of the product and are unchanged.

## Download

- [Repository](https://github.com/himomohi/AirTranslate)
- [AirTranslate 1.13.0 release](https://github.com/himomohi/AirTranslate/releases/tag/v1.13.0)
- [Latest stable DMG download](https://github.com/himomohi/AirTranslate/releases/latest/download/AirTranslate.dmg)

Version: **1.13.0 / build 1130**. Requires macOS 26 or later on Apple Silicon.

## Distribution Notes

AirTranslate is an independent Apache-2.0 project and is not affiliated with Apple, Google, or its optional cloud providers. DMG and ZIP artifacts are **ad-hoc signed and not Apple-notarized**. macOS may show an unidentified-developer warning on first launch; TCC permission inheritance across updates is not guaranteed. Compare the downloaded DMG with its `.sha256` file and follow [Apple's first-launch guidance](https://support.apple.com/guide/mac-help/mh40616/mac) if needed.
