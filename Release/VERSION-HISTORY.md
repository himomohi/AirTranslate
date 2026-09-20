# AirTranslate Version History

## 1.11.0 - 2026-09-20

### Added

- Qwen LiveTranslate uses `qwen3.8-livetranslate-flash-realtime` for microphone or Mac-audio translation with a Singapore workspace API key and workspace ID. Keys stay in a dedicated macOS Keychain item; selected audio goes directly to Alibaba Cloud Singapore.
- Qwen returns original transcripts and translated captions with automatic source-language detection. Speech output is optional, starts off, and has an independent saved preference.
- Floating-caption Settings adds five text styles, typography and color controls, width, ordering, and sample previews without recording.

### Changed

- A key-aware mode picker shows provider availability, per-row settings shortcuts, and model/pricing information; the API-key screen uses consistent provider rows and concise information icons.
- OpenAI Audio combines translation and source transcription in one provider entry while preserving language and output preferences.
- Floating captions display text only, without background, border, toolbar, status text, or hover resize affordances. Controls remain in Settings, the main window, and the menu bar.

### Fixed

- Qwen stop and system-capture termination drain final captions before closing the active session.
- Empty Qwen final results retract provisional text from the main and floating captions. File saves and periodic checkpoints contain confirmed Qwen results only.

## 1.10.0 - 2026-09-18

### Added

- Optional Grok STT uses SpaceXAI (xAI) Grok Voice Transcribe 2.0 for microphone or Mac-audio transcription.
- API Keys includes a dedicated SpaceXAI (xAI) entry; keys are stored separately in macOS Keychain and audio goes directly to xAI only when Grok capture starts.

### Changed

- Grok starts with original-only captions and automatic spoken-language recognition. Existing Apple defaults and other provider settings remain available; Apple Translation can be enabled separately.

### Fixed

- Grok final-response handling avoids duplicating completed utterances, including Japanese utterances joined without spaces.
- Saved Grok transcripts exclude provisional captions and translation-status messages.
- Switching away from Grok clears its missing-key notice while preserving unrelated errors.

## 1.9.2 - 2026-09-16

### Fixed

- Fixed translation language-pack downloads in Settings > Assets by using Apple's in-app language download approval flow instead of a session restricted to already-installed languages (Issue #14).
- Refresh asset availability after downloads and allow retry after cancellation or failure.
- Keep download completion tied to the requested language pair so an outdated request cannot start capture with a different selection.

## 1.9.1 - 2026-09-16

### Added

- Added precise #RRGGBB color-code input with keyboard Apply for caption text and background colors.

- The floating caption window can now be resized in both width and height.
- Hover states expose clearer drag and resize affordances for the floating caption window.
- Floating captions support a custom font size in addition to the existing preset sizes.
- Floating caption text color, background color, and background opacity can be customized without fading caption text.
- Floating caption window and style preferences persist across launches and can be reset.

## 1.9.0 - 2026-09-16

### Added

- Optional Nari STT sends microphone or Mac audio to Nari Qwen3-ASR for realtime source transcription after the user configures a Nari API key.
- Nari model selection includes the current GA STT IDs `qwen3-asr-fast` and `qwen3-asr`; model availability, limits, and paid-credit requirements follow Nari's current provider documentation and account state.
- Nari can use manual source language selection or Nari-specific automatic spoken-language detection for supported spoken languages, including Korean.

### Changed

- API key settings now use one provider list for OpenAI, Gemini, Meta, Azure, and Nari, with saved/setup state, active engine context, provider icons, key-console links, and a Keychain information popover.
- Nari STT starts as original-only transcription by default, then can use Apple Translation when translation output is enabled and the source language is available.
- New Nari selections use the GA Fast model with a paid-credit notice. Saved Free Public Beta model choices are preserved and blocked from starting, without automatic migration to a paid model; users can explicitly select a GA model in Settings > General to resume.
- Localized README files now describe the current product surface and point release chronology to `CHANGELOG.md` and this version history.
- Public release metadata and README download links are updated for 1.9.0/build190.

### Fixed

- Nari API key presence checks avoid reading secret values or triggering Keychain authentication UI during startup status checks.
- Nari session lifecycle handling preserves completed captions across pause, stop, reconnect, and queue-limit failures while avoiding replay of unfinished audio.
- README provider copy now makes clear that configured keys are not proof of external provider authorization.

## 1.8.0 - 2026-09-08

### Added

- Azure MAI preview mode sends 5-second audio chunks to Azure Speech MAI-Transcribe-2 with a user-provided Azure Speech endpoint and API key, then translates captions through Apple Translation.
- Apple caption pipeline coverage now includes segment metadata, repeated final utterances, stale recognition rejection, bounded partial translation requests, and Stage rewrite presentation.

### Changed

- Transcript file saving is opt-in. Stop and app quit do not write `.txt` files unless **Save Transcript Files** is enabled in Settings > Transcript.
- Apple Mode now preserves audio segment identity and final-result revisions through recognition, translation, display, and saved transcript staging.
- Stage caption rewrites wait briefly before replacing readable text, while first text and appended text still appear immediately. Floating-caption stale translation expiry is calculated from the request deadline.

### Fixed

- Short final utterances and repeated sentences are preserved instead of being collapsed into nearby partial or final results.
- Transcript pane copy buttons remain discoverable through keyboard and accessibility focus.

## 1.7.1 - 2026-09-02

### Added

- Caption Stability (Responsive / Balanced / Steady) and Caption Alignment (Center / Left) in Settings and the menu bar.

### Changed

- Floating captions reserve a fixed caption height and fade replacements in one piece so the source line does not jump.

### Fixed

- Floating translations hold the previous translation until a replacement is ready, instead of rewriting or flickering on every recognizer revision.

## 1.7.0 - 2026-09-02

### Added

- Optional Meta Scribe mode powered by Muse Voice Transcribe adds realtime transcription, speaker labels, and 25-language code-switching before AirTranslate's existing translation layer. A user-provided Meta API key is required; Apple Mode remains the local-first default.

### Changed

- The main window is now a Stage & Console layout: live captions fill the window as turn-based blocks, and a floating console bar holds Start/Stop, audio source, language route, output mode, voice output, and the active engine. The settings sidebar is gone.
- A shared Air teal design system covers listening/paused/stopped colors, layered surfaces, and caption typography across the main window, Settings, transcript library, floating captions, and menu bar.
- Custom controls use an accent-colored focus ring, Start receives initial focus, and session-locked controls stay dimmed with a single lock indicator.

### Fixed

- Apple Mode no longer accumulates the entire session into one caption line. It rolls the live line into a new turn block after roughly 600 committed characters or a long silence, and late final results that revise a rolled sentence merge instead of duplicating. Saved transcripts still contain the full session.
- The Stage no longer goes blank after a long session or a stop/start cycle. The feed renders the 12 most recent turn blocks with a plain stack so rendering cost stays constant.

## 1.6.2 - 2026-08-27

### Fixed

- AirTranslate requests Screen Recording access only on the first necessary attempt; later failures show the existing macOS Privacy & Security recovery path without reopening the system request.
- Permission guidance now tells users to keep only the intended AirTranslate installation because older or differently signed copies with the same bundle identifier can create conflicting TCC identities.
- Public DMG and ZIP artifacts remain ad-hoc signed, so TCC permission inheritance is not guaranteed between updates and the newly installed build may need to be confirmed in System Settings.
- The hidden Settings Scene no longer participates in capture-start segmented-control state changes, preventing its disabled `Picker` from entering an AppKit focus-navigation/AttributeGraph CPU loop and allowing the top Gemini Live Start flow to proceed.

## 1.6.1 - 2026-08-27

### Fixed

- The top Start control now begins Gemini Live capture with the selected Gemini mode.
- Segmented capture controls no longer use AppKit's dynamic disabled state during startup, avoiding its focus-navigation/AttributeGraph CPU loop while retaining the visible locked state.
- Start failures now remain in the main window with an appropriate API-key Settings, macOS Privacy Settings, or retry action instead of disappearing as a transient overlay.
- Local launch verification checks the exact executable inside the current `dist/AirTranslate.app`, so an older same-bundle-ID copy cannot be reported as the active build.
- Permission guidance identifies the current signed AirTranslate build and asks for one targeted Settings refresh only when macOS does not recognize it; routine TCC resets are not required.

## 1.6.0 - 2026-08-27

### Added

- Optional Gemini 3.5 Transcribe Live for original-only captions with automatic spoken-language detection when the user supplies a Gemini API key.

### Changed

- Gemini Live now handles finished session state, scheduled session resumption, GoAway reconnection recommendations, bounded context compression, and 40 ms audio transmission for more resilient long-running capture.
- The workspace and Settings reflow at the minimum window size without hiding controls, and Apple, GPT, and Gemini transcription modes share the same original-only output behavior.

### Fixed

- Original-only transcription no longer leaves translated-voice controls or target-language routing visible.

## 1.5.1 - 2026-08-09

### Added

- Per-permission rows with available status or System Settings verification guidance, refreshable permission state, translation-asset download progress/error/retry feedback, and visible app version/build details.

### Changed

- The workspace, sidebar, menu bar, floating captions, transcript library, and Settings now share a minimal design system with consistent spacing, icon sizing, surfaces, selection, and hover feedback.
- Settings communicate API-key replacement, active control dependencies, caption-preview behavior, keyboard navigation, accessibility values, and Reduce Motion behavior more clearly.

### Fixed

- Voice volume is no longer interactive while translated voice output is unavailable or off.
- API-key persistence uses one session-store path instead of duplicate Settings-level Keychain writes.
- Startup API-key presence checks no longer read secret data or allow authentication UI before the first window appears.
- The About pane resolves version/build metadata from the packaged executable that is actually running.
- Failed translation-language assets can be retried, and each Settings section retains a stable scroll identity.

## 1.5.0 - 2026-08-02

### Added

- Added optional GPT Transcription with `gpt-live-transcribe` for source-only live captions when the user provides an OpenAI API key. Apple Mode remains the default local-first path.
- Added lifecycle regression tests for permission cancellation, stale callbacks, external system-audio stops, restart behavior, configuration locking, and explicit speech-input backpressure handling.

### Changed

- Apple Mode start attempts now use generation-scoped ownership so an old permission, warm-up, or callback cannot mutate a newer capture session.

### Fixed

- An external system-audio user stop now saves the active transcript, unlocks the session, and allows the next start to proceed normally.
- Speech-input backpressure is surfaced as a controlled stop instead of silently losing audio.
- Stale OpenAI and Gemini connection errors can no longer replace the current session state or expose raw provider connection details in the UI.

## 1.4.2 - 2026-07-31

### Fixed

- Release and local app signatures now embed the required microphone audio-input entitlement while retaining Hardened Runtime.
- The privacy-reset helper now resets Microphone permission, and packaging checks verify the release/debug entitlement separation before distribution.

## 1.4.1 - 2026-07-24

### Changed

- Apple-mode translated speech now waits for stable sentence boundaries during streaming and speaks final unpunctuated translations immediately when the request completes.
- Dubbing speech progress is isolated in AirTranslateCore with focused regression coverage for streaming rewrites, finalization revisions, suffix replays, priming, and repeat expiry.

### Fixed

- Prevented translated speech from repeating the tail of a restored sentence after a shorter streaming rewrite.
- Suppressed near-duplicate finalization variants and text that was already visible before dubbing was enabled.
- Prevented short suffix replays while keeping legitimate later repeated phrases speakable.

## 1.4.0 - 2026-07-10

### Added

- Periodic transcript checkpoints during active capture and native macOS capture shortcuts.
- Regression tests for long-session responsiveness, realtime provider tails, retry policies, floating-window visibility, and speech backlog limits.

### Changed

- Apple basic mode now bounds long-session MainActor work with automatic update coalescing, background translation preparation, and a bounded LRU cache.
- Gemini Live uses explicit activity detection and bounded pre-setup audio buffering.
- OpenAI translation streams partial results and applies bounded retry and timeout behavior.
- Workspace, sidebar, menu bar, floating-caption, and settings interactions have clearer state, keyboard, accessibility, and reduced-motion behavior.

### Fixed

- Preserved the final buffered words across realtime completion, pause, stop, and termination paths.
- Prevented translated speech and realtime audio queues from accumulating unbounded stale output.
- Restored off-screen floating caption windows to a visible display.
- Redacted authenticated Gemini WebSocket details from network errors shown to users.

## 1.3.6 - 2026-06-13

### Added

- Gemini 3.5 Live Translate mode for direct audio-to-live-translation sessions.
- Gemini API key storage in macOS Keychain.
- Compact LIVE Translation control for API-backed GPT and Gemini modes.
- Sidebar voice-output toggle and translated-voice volume slider.

### Changed

- GPT mode now uses OpenAI Realtime Translation for the live translation path and shows source transcript updates.
- API-backed modes now use one translated-audio output path and default voice output on.
- Apple basic mode defaults voice output off while allowing manual translated speech output.
- Settings and sidebar controls now separate Apple, GPT Realtime, and Gemini Live modes more clearly.

### Fixed

- Source-language quick changes no longer switch translation sessions to Transcribe Only mode.
- GPT realtime translation now shows the original transcript.
- GPT and Gemini live translated audio playback now uses the translated voice path consistently.
- Apple basic-mode translated speech no longer lowers the Mac system volume.

## 1.3.5 - 2026-06-13

### Changed

- Saved transcript history now loads lightweight previews first and opens full text only when a transcript is selected.
- Realtime GPT transcript updates are coalesced to reduce MainActor and UI churn during long sessions.
- Realtime audio send backlog is bounded so stalled network sends cannot accumulate without limit.
- Start/stop capture teardown is serialized before a new capture start.

### Fixed

- Very large transcript panes now render a bounded display tail even in standard session mode while preserving the full saved text.

## 1.3.4 - 2026-05-26

### Changed

- Floating caption wrapping now scales with the selected text size so larger captions keep readable text within the floating window.

## 1.3.3 - 2026-05-26

### Added

- Added a dedicated Transcribe Only output mode that shows only the original transcript pane.

### Changed

- Floating captions keep the wrapping improvements from 1.3.2-era development and stay original-only during Transcribe Only sessions.
- Transcribe Only language changes now keep the hidden target language aligned with the visible source language.

### Fixed

- Prevented blank translation-only floating captions while Transcribe Only mode is active.

## 1.3.2 - 2026-05-17

### Fixed

- Centered the empty transcript placeholder in the main workspace.

## 1.3.1 - 2026-05-16

### Changed

- Temporarily disabled Apple basic-mode source language auto-detection while language-switch handling is improved.
- Added a clear in-app notice when the disabled auto-detect toggle is clicked.

### Fixed

- Prevented saved auto-detect preferences from re-enabling the feature in this build.

## 1.3.0 - 2026-05-16

### Added

- Added input support for built-in, Bluetooth, and AirPods microphones.
- Added source language auto-detection for Apple basic mode when language inference is available.

### Changed

- Improved microphone pipeline stability for long sessions.

### Fixed

- Fixed duplicate transcript input from unstable microphone transitions.
- Reduced duplicate segments when switching capture source setup.

## 1.2.1 - 2026-05-14

### Changed

- Apple mode now keeps the visible mode and internal translation state aligned.
- GPT mode setup now uses the same session-level mode switching path as Apple mode.

### Fixed

- Fixed Apple default mode translation staying inactive while transcription continued.
- Translation unavailable states now show a clear message in the translation output.

## 1.2.0 - 2026-05-13

### Added

- Optional GPT realtime transcription and translation modes.
- Realtime translation-only path with optional translated audio playback.
- macOS Keychain storage for user-provided OpenAI API keys.
- English, Korean, Japanese, and Simplified Chinese README files.

### Changed

- GPT realtime floating captions show only the current live caption unit instead of the accumulated transcript.
- GPT realtime output is preserved without transcript lint cleanup rewriting model text.
- Saved original-plus-translation transcripts are grouped as one library item.

### Fixed

- Reduced duplicate live transcript text after paragraph cleanup or settings changes.
- Improved per-pane editing behavior for saved original and translated transcripts.

## 1.1.0 - 2026-05-10

### Added

- Centered live audio waveform meter.

### Changed

- Improved hover, pressed, active, and click-confirmation feedback for transport controls.
- Moved the live audio waveform into the center header area.

## 2026-05-09 - Library Modal UI

### Added

- Original-plus-translation saved transcripts grouped into a single library row.
- Confirmation-protected delete-all action.

### Changed

- Saved transcript management moved from the sidebar into a focused modal.

## 2026-05-09 - Transcript Control and Stability

### Added

- Configurable silence interval for paragraph breaks.

### Fixed

- Bounded speech analyzer input buffering.
- Bounded translation segment cache.
- Reduced text animation work for long transcript updates.
