# AirTranslate 1.12.0

AirTranslate 1.12.0 adds two Qwen Audio 3.1 options while keeping Apple Mode and the existing Qwen3.8 realtime model available.

## Added

- **Qwen Audio 3.1 Realtime Plus** (`qwen-audio-3.1-realtime-plus`) is an alternate model for Qwen LiveTranslate. Select the model in Settings > General; capture requires the user's Alibaba Cloud Singapore API key. The workspace ID is required only for the existing Qwen3.8 model.
- **Qwen Audio 3.1 ASR Flash Filetrans** (`qwen-audio-3.1-asr-flash-filetrans`) is available in Settings > General for asynchronous transcription from a public HTTPS audio URL. QwenCloud fetches the audio; AirTranslate does not upload a local file in this workflow.

## Changed

- Qwen model descriptions distinguish the realtime model from asynchronous file transcription and direct users to the current Model Studio pricing for Qwen Audio 3.1.
- Setup, privacy, and localized README documentation describe both data paths and the Filetrans public-URL requirement.

## Verification Boundary

Automated tests use fake network clients. They verify local request construction, parsing, state transitions, and model selection. They do not contact QwenCloud or verify live account authorization, billing, transcription or translation quality, or latency. Share only audio you are authorized to send to the provider.

[Qwen setup and pricing guidance](https://github.com/himomohi/AirTranslate/blob/v1.12.0/docs/qwen-livetranslate.md)

## Download

- [Repository](https://github.com/himomohi/AirTranslate)
- [AirTranslate 1.12.0 release](https://github.com/himomohi/AirTranslate/releases/tag/v1.12.0)
- [Latest stable DMG download](https://github.com/himomohi/AirTranslate/releases/latest/download/AirTranslate.dmg)

Version: **1.12.0 / build 1120**. Requires macOS 26 or later on Apple Silicon.

## Distribution Notes

AirTranslate is an independent Apache-2.0 project and is not affiliated with Apple or its optional cloud providers. DMG and ZIP artifacts are **ad-hoc signed and not Apple-notarized**. macOS may show an unidentified-developer warning on first launch; TCC permission inheritance across updates is not guaranteed. Compare the downloaded DMG with its `.sha256` file and follow [Apple's first-launch guidance](https://support.apple.com/guide/mac-help/mh40616/mac) if needed.
