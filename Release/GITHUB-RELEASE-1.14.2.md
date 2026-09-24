# AirTranslate 1.14.2

AirTranslate 1.14.2 clarifies the main workspace's provider model choices using each provider's documented capabilities and the API workflow AirTranslate actually calls.

## Changed

- The model picker distinguishes realtime speech translation from realtime source transcription. Gemini 3.8 Flash TTS and Flash-Lite TTS remain in the separate translated-speech selector; they synthesize translated text and are used only by text-translation workflows. Realtime providers keep their native audio output.
- Qwen Audio 3.1 Realtime Plus is identified as a full-duplex voice-conversation model that receives translation instructions from AirTranslate. Qwen3.8 LiveTranslate remains the dedicated realtime translation workflow, and Qwen Audio Filetrans remains a separate asynchronous transcription tool.
- Provider-specific model descriptions now reflect the integration path, including Azure's sequential five-second REST transcription chunks.

## Verification Boundary

The model capability classification is based on official provider documentation and the app's current integration code. It does not verify real provider account authorization, billing, quotas, speech quality, translation quality, latency, or service availability. This release does not change provider credentials or how captured audio is sent to a selected provider.

## Download

- [Repository](https://github.com/himomohi/AirTranslate)
- [AirTranslate 1.14.2 release](https://github.com/himomohi/AirTranslate/releases/tag/v1.14.2)
- [Latest stable DMG download](https://github.com/himomohi/AirTranslate/releases/latest/download/AirTranslate.dmg)

Version: **1.14.2 / build 1142**. Requires macOS 26 or later on Apple Silicon.

## Distribution Notes

AirTranslate is an independent Apache-2.0 project and is not affiliated with Apple, Google, Alibaba Cloud, OpenAI, Nari, xAI, Meta, or Azure. DMG and ZIP artifacts are ad-hoc signed and are not Apple-notarized. macOS may show an unidentified-developer warning on first launch; TCC permission inheritance across updates is not guaranteed. Compare the downloaded DMG with its `.sha256` file and follow [Apple's first-launch guidance](https://support.apple.com/guide/mac-help/mh40616/mac) if needed.
