# AirTranslate 1.14.1

AirTranslate 1.14.1 fixes the Gemini model menu so Gemini 3.8 Flash TTS and Gemini 3.8 Flash-Lite TTS can be selected directly from the main workspace's bottom-right Gemini model control.

## Fixed

- The Gemini menu now separates realtime models from translated-speech models and shows an independent selection check for each category.
- Choosing a Gemini TTS model updates the saved translated-speech preference without changing the active realtime model. Gemini TTS is used only for text-translation workflows; realtime providers continue to use native audio.

## Verification Boundary

Local UI verification confirms that both TTS choices appear in the Gemini model menu and update the saved preference. It does not verify Gemini account authorization, billing, generated audio quality, latency, quota, or service availability. Release ZIP and DMG files are ad-hoc signed and not Apple-notarized.

## Download

- [Repository](https://github.com/himomohi/AirTranslate)
- [AirTranslate 1.14.1 release](https://github.com/himomohi/AirTranslate/releases/tag/v1.14.1)
- [Latest stable DMG download](https://github.com/himomohi/AirTranslate/releases/latest/download/AirTranslate.dmg)

Version: **1.14.1 / build 1141**. Requires macOS 26 or later on Apple Silicon.
