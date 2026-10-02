# AirTranslate 1.15.0

AirTranslate adds Microsoft's three new MAI audio models as optional transcription and translated-speech choices.

## Added

- **MAI-Transcribe-2-Streaming:** stream microphone or Mac audio to Microsoft Foundry and display intermediate source captions. Finalized text is translated with Apple. In API Keys > Azure / Microsoft Foundry, configure the deployed resource's endpoint, resource key, and deployment name. Audio is committed every three seconds and when paused or stopped. The existing five-second MAI-Transcribe-2 option remains available.
- **MAI-Voice-2.1 and MAI-Voice-2.1-Flash:** choose either model for translated speech and configure an OpenRouter API key. Select an automatic voice or one matching the target language. Korean is supported; Japanese is currently absent from the provider's voice catalog. Only stable translated text is sent for voice generation; realtime audio providers continue using their native speech output.

## Fixed

- Stopping Azure capture waits for the last finalized translations within a bounded timeout before ending the session.
- Empty final Azure results clear provisional text from the main workspace and floating captions.

## Setup and Availability

Microsoft Foundry streaming transcription is a public preview and requires access to a deployed model. OpenRouter speech generation requires your own service key and credits. Provider usage is billed separately. See the [MAI setup guide](https://github.com/himomohi/AirTranslate/blob/master/docs/microsoft-mai-audio.md).

Real-account authentication, deployment availability, billing, quotas, transcription quality, voice quality, and latency have not been verified. Model selection and local key storage do not confirm account access.

## Download

- [Repository](https://github.com/himomohi/AirTranslate)
- [AirTranslate 1.15.0 release](https://github.com/himomohi/AirTranslate/releases/tag/v1.15.0)
- [Latest stable DMG download](https://github.com/himomohi/AirTranslate/releases/latest/download/AirTranslate.dmg)

Version: **1.15.0 / build 1150**. Requires macOS 26 or later on Apple Silicon.

## Distribution Notes

AirTranslate is an independent Apache-2.0 project and is not affiliated with the model providers. DMG and ZIP artifacts are ad-hoc signed and are not Apple-notarized. macOS may show an unidentified-developer warning on first launch; permission inheritance across updates is not guaranteed. Compare the downloaded DMG with its `.sha256` file and follow [Apple's first-launch guidance](https://support.apple.com/guide/mac-help/mh40616/mac) if needed.
