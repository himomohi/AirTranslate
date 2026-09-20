# AirTranslate 1.11.0

AirTranslate 1.11.0 adds **Qwen3.8 live translation**, a key-aware mode picker, unified OpenAI output selection, and text-only floating captions.

## Added

- **Qwen LiveTranslate** uses `qwen3.8-livetranslate-flash-realtime` for microphone or Mac audio. Add your Alibaba Cloud **Singapore API key and workspace ID** in Settings > API Keys > Qwen, then select Qwen LiveTranslate.
- Qwen detects the spoken language and returns original transcripts and translated captions directly. **Speech output is optional and initially off**; its preference is saved independently. Keys stay in a dedicated macOS Keychain item, and selected audio goes directly to Alibaba Cloud Singapore only when capture starts. Account access, quotas, and provider charges apply.
- Floating-caption Settings provides five text styles, font and color options, width, line spacing, ordering, and sample previews without recording.

## Changed

- The mode picker shows providers without keys in gray, offers a settings shortcut per row, and describes model/pricing information. API-key settings use consistent provider rows and concise information icons.
- **OpenAI Audio** combines translation and source transcription in one provider entry while preserving language and output preferences.
- Floating captions display **text only**, without a window background, border, toolbar, status text, or hover resize controls. Use Settings, the main window, menu bar, or ⌘⇧C to control them.

## Fixed

- Qwen stop and system-capture termination wait for final captions before closing the session.
- Empty Qwen final results retract provisional captions; saved files and periodic checkpoints contain confirmed Qwen results only.

## Verification Boundary

Local tests, builds, packaged-app checks, and UI inspection cover the implementation. Real Alibaba Cloud account authentication, billing, translation quality, latency, and quota behavior have **not** been verified with a live key. A saved key is not proof of provider authorization. Apple Mode remains the default and transcript file saving remains opt-in.

[Qwen setup, pricing, and privacy](https://github.com/himomohi/AirTranslate/blob/v1.11.0/docs/qwen-livetranslate.md)

## Download

- [Repository](https://github.com/himomohi/AirTranslate)
- [AirTranslate 1.11.0 release](https://github.com/himomohi/AirTranslate/releases/tag/v1.11.0)
- [Latest stable DMG download](https://github.com/himomohi/AirTranslate/releases/latest/download/AirTranslate.dmg)

Version: **1.11.0 / build 1110**. Requires macOS 26 or later on Apple Silicon.

## Distribution Notes

AirTranslate is an independent Apache-2.0 project and is not affiliated with Apple or its optional cloud providers. DMG and ZIP artifacts are **ad-hoc signed and not Apple-notarized**. macOS may show an unidentified-developer warning on first launch; TCC permission inheritance across updates is not guaranteed. Compare the downloaded DMG with its `.sha256` file and follow [Apple's first-launch guidance](https://support.apple.com/guide/mac-help/mh40616/mac) if needed.
