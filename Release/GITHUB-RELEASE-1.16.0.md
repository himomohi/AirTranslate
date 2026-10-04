# AirTranslate 1.16.0

AirTranslate 1.16.0 improves existing transcription, translation scheduling, caption reading, and window controls. It also adds floating-only capture, previous-caption history, and optional Apple translation and Jev text-selection settings.

## Added

- Floating-only mode starts or resumes capture and minimizes the main window only after capture is running. Menu-bar and app-menu controls provide start/stop and pause/resume. Startup failures keep the main controls available.
- Previous-caption history shows one prior block for up to eight seconds and two lines, with Reduce Motion support.
- Experimental, opt-in Jev selection chooses among Apple final recognition candidates before translation. Candidate text and recent transcript context go directly to TypeSafe with the user's Keychain-stored key. Requests add API usage and up to 1.2 seconds of response waiting, with original-text fallback on uncertainty or failure.
- Apple text translation offers Realtime and Quality first choices plus protected terms on macOS 26.4+. Failed quality-first requests fall back to realtime for that language pair until restart. If Apple changes a registered term, the affected segment remains in its original language.

## Changed

- Reading older captions pauses automatic scrolling. Returning to the latest captions resumes following, and the main window retains the reading position when minimized or hidden.
- Current floating captions keep their position without repeated replacement fades. Bounded layout reuse and processing only the visible text reduce repeated formatting of long transcripts.
- The minimized main window skips caption display work. Closing floating captions also stops their display timers and layout work while recognition and translation continue.
- Main-window, menu-bar, and keyboard controls share capture availability and preparation, finishing, and reconnecting states. Caption display mode and font-size controls are shared across menus.
- Apple transcription retains surrounding recognition context. Short, changing fragments wait for a quiet interval after the last text change, while complete phrases can proceed sooner; punctuation-only results do not trigger translation.
- On macOS 27, Apple speech input adapts differing PCM formats while preserving the existing 16 kHz mono path.
- Source builds now require Xcode 27, the macOS 27 SDK, and Swift 6.4 or later. The app's minimum runtime remains macOS 26.

## Fixed

- Matching interim and final transcripts reuse the in-flight translation, and identical results are not applied twice.
- Revised final text supersedes stale interim translation. Late results and errors from stopped sessions cannot overwrite a restarted session, while repeated phrases in distinct utterances keep their order.
- Apple-finalized speech is retained when recognition advances to a new utterance, including when Apple confirms the previous segment without sending a separate final-text event. This avoids losing or duplicating the previous segment.
- Reopening floating captions restores the latest available text without retranslating it. Corrected source text no longer leaves an outdated translation visible past its hold period, and interim text is not duplicated on reopening.
- Closing floating captions automatically restores only the main windows minimized by floating-only mode, including when closed during minimization. Explicitly opening the main window brings it back to the foreground.

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
