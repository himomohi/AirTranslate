# AirTranslate 1.16.0

Start capture directly in floating-only mode, keep the previous caption in view, and choose optional Apple translation and Jev text-selection settings.

## Added

- Floating-only mode starts or resumes capture and minimizes the main window only after capture is running. Menu-bar and app-menu controls provide start/stop and pause/resume. Startup failures keep the main controls available.
- Previous-caption history shows one prior block for up to eight seconds and two lines, with Reduce Motion support.
- Experimental, opt-in Jev selection chooses among Apple final recognition candidates before translation. Candidate text and recent transcript context go directly to TypeSafe with the user's Keychain-stored key. Requests add API usage and up to 1.2 seconds of response waiting, with original-text fallback on uncertainty or failure.
- Apple text translation offers Realtime and Quality first choices plus protected terms on macOS 26.4+. Failed quality-first requests fall back to realtime for that language pair until restart. If Apple changes a registered term, the affected segment remains in its original language.

## Changed

- Floating captions reuse bounded layouts, and the minimized main window avoids caption display work while transcription and translation continue.
- On macOS 27, Apple speech input adapts differing PCM formats while preserving the existing 16 kHz mono path.
- Source builds now require Xcode 27, the macOS 27 SDK, and Swift 6.4 or later. The app's minimum runtime remains macOS 26.

## Fixed

- Apple transcription uses surrounding recognition context and preserves final speech when stopping. Superseded translation work no longer overwrites newer captions.

## Setup and Availability

Jev is experimental and off by default. Enable it in Settings > General only after adding a TypeSafe key in API Keys. It sends final recognition candidates and up to six recent transcript segments, limited to 1,000 UTF-8 bytes of context, to TypeSafe. It does not send audio. Accuracy improvement is not guaranteed, and API charges and account limits apply separately. [Apple translation and Jev setup](https://github.com/himomohi/AirTranslate/blob/master/docs/apple-translation-options.md).

Apple's Quality first selection depends on system model availability and may take longer. Model identity and quality gains are not guaranteed. Real provider billing, quotas, retention, broad recognition accuracy, and general end-to-end latency remain unverified.

## Download

- [Repository](https://github.com/himomohi/AirTranslate)
- [AirTranslate 1.16.0 release](https://github.com/himomohi/AirTranslate/releases/tag/v1.16.0)
- [Latest stable DMG download](https://github.com/himomohi/AirTranslate/releases/latest/download/AirTranslate.dmg)

Version: **1.16.0 / build 1160**. Requires macOS 26 or later on Apple Silicon. Apple translation options require macOS 26.4+; the new audio input adapter requires macOS 27+.

## Distribution Notes

AirTranslate is an independent Apache-2.0 project and is not affiliated with the model providers. DMG and ZIP artifacts are ad-hoc signed and are not Apple-notarized. macOS may show an unidentified-developer warning on first launch; permission inheritance across updates is not guaranteed. Compare the downloaded DMG with its `.sha256` file and follow [Apple's first-launch guidance](https://support.apple.com/guide/mac-help/mh40616/mac) if needed.
