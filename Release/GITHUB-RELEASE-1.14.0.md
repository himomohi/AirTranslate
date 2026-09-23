# AirTranslate 1.14.0

AirTranslate 1.14.0 moves provider-specific model selection into the main workspace. Use the bottom-right control to switch providers, choose the active model, jump to the relevant settings, and choose a translated speech model when the current workflow supports it.

## Added

- **Main workspace provider model picker**: the bottom-right control now opens a provider list and model selector in one popover.
- Apple, OpenAI, Gemini, Qwen, and Nari expose their selectable model choices directly from the console, including Qwen Audio 3.1 realtime, Gemini Live, Gemini TTS, and Nari GA model options where applicable.
- Translated speech model selection appears beside the provider model selection when the active workflow can use Apple system speech or Gemini TTS.

## Changed

- The console badge now shows the selected model name instead of only the provider name.
- Provider switching, unavailable-provider state, Settings shortcuts, and model selection now stay together in the bottom-right picker.

## Verification Boundary

Local verification can check the picker layout, saved model selection, Settings shortcuts, and packaged app metadata. It does not verify live OpenAI, Gemini, Qwen, Nari, xAI, Meta, or Azure account authorization, billing, audio quality, latency, quota, or service availability. Qwen Audio 3.1 options from 1.12.0, single-instance app behavior from 1.12.1, and Gemini TTS from 1.13.0 remain part of the product and are unchanged except for the new main picker access.

## Download

- [Repository](https://github.com/himomohi/AirTranslate)
- [AirTranslate 1.14.0 release](https://github.com/himomohi/AirTranslate/releases/tag/v1.14.0)
- [Latest stable DMG download](https://github.com/himomohi/AirTranslate/releases/latest/download/AirTranslate.dmg)

Version: **1.14.0 / build 1140**. Requires macOS 26 or later on Apple Silicon.

## Distribution Notes

AirTranslate is an independent Apache-2.0 project and is not affiliated with Apple, Google, Alibaba Cloud, OpenAI, Nari, xAI, Meta, Azure, or its optional cloud providers. DMG and ZIP artifacts are **ad-hoc signed and not Apple-notarized**. macOS may show an unidentified-developer warning on first launch; TCC permission inheritance across updates is not guaranteed. Compare the downloaded DMG with its `.sha256` file and follow [Apple's first-launch guidance](https://support.apple.com/guide/mac-help/mh40616/mac) if needed.
