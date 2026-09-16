# Changelog

All notable changes to AirTranslate are documented in this file.

## [Unreleased]

## 1.9.2 - 2026-09-16

### Fixed

- Fixed translation language-pack downloads in Settings > Assets by using Apple's in-app language download approval flow instead of a session restricted to already-installed languages (Issue #14).
- Refresh asset availability after downloads and allow retry after cancellation or failure.
- Keep download completion tied to the requested language pair so an outdated request cannot start capture with a different selection.

## 1.9.1 - 2026-09-16

### Added

- Added precise #RRGGBB color-code input with keyboard Apply for caption text and background colors.

- Added a resizable floating caption window that can be adjusted in both width and height.
- Added visible hover affordances for moving and resizing floating captions.
- Added custom floating-caption font sizing while keeping the existing preset sizes.
- Added floating-caption text color, background color, and background opacity controls that do not fade caption text.
- Added persistence and reset behavior for floating-caption window and style preferences.

## 1.9.0 - 2026-09-16

### Added

- Added optional Nari STT with Qwen3-ASR realtime transcription. It sends microphone or Mac audio to Nari only after the user selects Nari STT and configures a Nari API key, then uses the existing Apple Translation workflow when translation output is enabled.
- Added Nari model selection for the current GA STT IDs `qwen3-asr-fast` and `qwen3-asr`. Model availability, limits, and paid-credit requirements follow Nari's current provider documentation and account state.
- Added Nari source-language handling with manual source language selection and Nari-specific automatic spoken-language detection for supported languages, including Korean.

### Changed

- Redesigned API key settings around provider rows for OpenAI, Gemini, Meta, Azure, and Nari, with saved/setup status, active-engine context, provider icons, key-console links, and a Keychain information popover.
- Selecting Nari STT starts in original-only transcription by default. Users can switch to translation output when the selected or detected source language is available in AirTranslate's Apple translation workflow.
- New Nari selections use the GA Fast model with a paid-credit notice. Saved Free Public Beta model choices are preserved and blocked from starting, without automatic migration to a paid model; Settings > General provides an explicit GA model selection to resume.
- Refocused localized README files around the current product, download path, engine table, privacy boundary, and documentation links. Release chronology now lives in this changelog and `Release/VERSION-HISTORY.md`.
- Updated public release metadata and README download links for 1.9.0/build190.

### Fixed

- API key presence checks include Nari without reading secret data or allowing Keychain authentication UI during startup status refreshes.
- Nari session lifecycle handling preserves completed source captions across pause, stop, reconnect, and queue-limit failures while avoiding automatic replay of unfinished audio.
- README provider wording now distinguishes a configured key from verified external service authorization.

## 1.8.0 - 2026-09-08

### Added

- Azure MAI is available as a preview transcription engine. It sends 5-second audio segments to Azure Speech MAI-Transcribe-2 only after the user configures an Azure Speech endpoint and API key, then uses Apple Translation for captions.
- Focused Apple caption pipeline tests now cover audio-segment metadata, repeated final utterances, stale recognition rejection, bounded partial translation requests, and Stage rewrite presentation.

### Changed

- Transcript file saving is now opt-in. **Save Transcript Files** is off by default, so Stop and app quit do not create transcript `.txt` files unless the user enables file saving in Settings > Transcript.
- Apple Mode now carries audio range, segment revision, and final-result metadata through recognition, translation, display, and saving so short final utterances and repeated sentences remain distinct.
- Stage captions publish the first text and appended text immediately, while non-prefix rewrites are held briefly and replaced in one piece to make live captions easier to read. Floating-caption stale translation expiry is now calculated from the request deadline instead of a delayed task start.

### Fixed

- Apple final results can now restore prepended words that were missing from an earlier partial result without losing the utterance or merging it with a later repeated sentence.
- Copy controls for transcript panes are reachable by keyboard and accessibility focus, even when the pointer is not hovering over the pane.

## 1.7.1 - 2026-09-02

### Added

- Caption Stability (Responsive / Balanced / Steady) and Caption Alignment (Center / Left) controls in Settings and the menu bar for the floating caption window.

### Changed

- Floating captions reserve a fixed caption height and fade replacement text in one piece so the source line does not jump or re-center on every update.

### Fixed

- Floating translations no longer rewrite or flicker on every recognizer revision. The overlay holds the previous translation until a new one is ready, and wraps to the measured window width.

## 1.7.0 - 2026-09-02

### Added

- Meta Scribe mode powered by Muse Voice Transcribe adds realtime transcription, speaker labels, and 25-language code-switching before AirTranslate's existing translation layer.

### Changed

- Redesigned the whole app around a "Stage & Console" layout. The main window no longer uses a settings sidebar: live captions fill the window as turn-based blocks (source line above a larger translated line, speaker chip when available, newest turn anchored just above the console), and a floating console bar at the bottom holds Start/Stop with a live audio meter, Pause, audio source, language route, output mode, voice output and volume, and the active engine badge. On narrow windows the secondary controls collapse into a More menu.
- Introduced a shared design system (adaptive "Air teal" accent, listening/paused/stopped state colors, layered surfaces, a typography scale for captions and UI, spacing/radius/elevation/motion tokens) applied consistently across the main window, Settings, transcript library, floating captions, and menu bar, in both light and dark appearance.
- Keyboard focus now uses an accent-colored focus ring across custom controls, the Start button receives initial focus, and session-locked controls are shown dimmed with a single lock indicator while remaining fully described to assistive technologies.

### Fixed

- Apple default mode no longer slows down over long sessions. Previously the entire transcript accumulated into one caption line, so every recognition update re-normalized, re-segmented, and re-laid-out the whole session's text on the main thread. Apple mode now rolls the live line over into a new turn block after roughly 600 committed characters (or a shorter block after a long silence), with a replay guard so late final results that revise an already-rolled sentence are merged instead of duplicated. Saved transcripts and the library still contain the full session text across all blocks.
- The Stage could go blank after a long session or a stop/start cycle. The transcript feed now renders the most recent turn blocks (12) with a plain stack instead of a lazy stack, which fixes the disappearing captions and keeps rendering cost constant regardless of session length.

## 1.6.2 - 2026-08-27

### Fixed

- Screen Recording access is now requested only on the first necessary attempt. Later capture failures direct the user to macOS Privacy & Security settings instead of repeatedly opening the system permission prompt.
- Clarified recovery for TCC identity conflicts: remove or archive older AirTranslate copies and differently signed builds that share `dev.appcaster.AirTranslate`, then keep and launch only the intended installation before checking its permission state.
- Documented that the public ad-hoc signed DMG and ZIP do not provide stable TCC permission inheritance across updates; users may need to confirm the newly installed build in System Settings.
- Removed the hidden Settings Scene's segmented `Picker` from the capture-start state transition. Changing that hidden control to disabled could enter an AppKit focus-navigation/AttributeGraph loop and make the top Gemini Live Start control appear stuck; capture startup can now continue without that hidden settings control participating.

## 1.6.1 - 2026-08-27

### Fixed

- Fixed the top Start control so it begins a Gemini Live capture using the selected Gemini mode instead of being blocked by the workspace state.
- Avoided the macOS SwiftUI/AppKit `NSSegmentedCell` disabled-state focus cycle that could drive AttributeGraph CPU use near 100% while a capture starts; locked segmented controls now keep their visible state while ignoring interaction.
- Replaced transient start-error overlays with an in-window recovery message that offers the relevant API-key Settings, macOS Privacy Settings, or retry action.
- Made local verification confirm that the current `dist/AirTranslate.app` executable is the process that launched, preventing a stale 1.5.1 copy with the same bundle identifier from being mistaken for the current build.
- Clarified privacy guidance for the current signed app build: keep the active copy, refresh the affected macOS permission once when necessary, then quit and relaunch instead of routinely resetting all TCC grants.

## 1.6.0 - 2026-08-27

### Added

- Added optional Gemini 3.5 Transcribe Live for source-only captions with automatic spoken-language detection. It remains opt-in and requires a user-provided Gemini API key.

### Changed

- Gemini Live sessions now interpret finished state, reuse session-resumption handles during scheduled refreshes, respond to GoAway reconnection recommendations, compress retained context, and send audio in 40 ms chunks to keep long-running capture responsive.
- The smallest supported workspace and Settings layouts now reflow controls without clipping, and every transcription mode uses the same original-only output contract.

### Fixed

- Source-only transcription no longer exposes translated-voice controls or a target-language route that does not apply to the active mode.

## 1.5.1 - 2026-08-09

### Added

- Added per-permission rows with available status or System Settings verification guidance, focused settings actions and refresh, translation-asset progress/error/retry states, and app version/build details.

### Changed

- Redesigned the main workspace, sidebar, menu bar, floating captions, transcript library, and all Settings panes around one minimal visual system for spacing, icons, surfaces, selection, and hover feedback.
- Settings now explain saved-versus-replacement API keys, show a floating-caption preview that follows the selected display mode, and make control dependencies easier to understand.
- Improved keyboard navigation, selection identity, accessibility labels and values, and Reduce Motion behavior across the redesigned surfaces.

### Fixed

- Disabled the translated-voice volume control whenever voice output is unavailable or off, with an explicit explanation of the dependency.
- Consolidated API-key persistence behind the session store so Settings no longer performs duplicate Keychain writes.
- Made startup API-key presence checks noninteractive so an updated ad-hoc build cannot block the first app window while macOS protects an existing Keychain item.
- Made the About pane read version and build metadata from the running packaged app, even when another local AirTranslate copy shares the same bundle identifier.
- Made failed translation-language assets downloadable again and preserved each Settings pane's scroll identity while switching sections.

## 1.5.0 - 2026-08-02

### Added

- Added the optional `gpt-live-transcribe` GPT Transcription mode for source-language captions. It requires a user-provided OpenAI API key; Apple Mode remains the default local-first path.
- Added focused regression coverage for GPT transcription selection and restore behavior, session configuration locking, permission cancellation, external capture stops, and speech-input backpressure.

### Changed

- Apple Mode now treats a start attempt as one generation-scoped session: permission waits, warm-up work, and callbacks from an old attempt cannot alter a newer session.
- Settings remain locked while a capture start is in flight and are restored after a blocked, cancelled, or failed start.

### Fixed

- Fixed Apple system-audio sessions so an external user stop saves the transcript, releases the session state, and allows a clean restart.
- Fixed live speech input backpressure so audio is never silently discarded; the app stops with a visible controlled error instead.
- Fixed stale OpenAI and Gemini connection callbacks and provider errors from overriding the active session, and keep user-visible provider failures free of raw connection details.

## 1.4.2 - 2026-07-31

### Fixed

- Fixed local and release app signing so the signed bundle embeds the required microphone audio-input entitlement under Hardened Runtime.
- Fixed the privacy-reset helper to reset Microphone permission alongside the other AirTranslate capture permissions.
- Added a packaging permission check that verifies the release/debug entitlement split, embedded entitlement values, Hardened Runtime, and microphone usage descriptions.

## 1.4.1 - 2026-07-24

### Changed

- Translated speech output in Apple mode now waits for stable sentence boundaries during streaming and still speaks final translation text that arrives without punctuation.
- Dubbing progress is now tracked by a focused core helper so speech-output replay behavior can be tested independently from the main session store.

### Fixed

- Fixed Apple-mode translated speech repeating restored sentence tails after shorter streaming rewrites.
- Fixed translated speech replaying near-duplicate finalization variants or rereading text that was already visible when dubbing was enabled.
- Fixed short repeated suffixes such as repeated closing words being spoken again while still allowing legitimate repeated phrases later in the session.

## 1.4.0 - 2026-07-10

### Added

- Added 30-second in-session transcript checkpoints that update the same files without stopping capture.
- Added native macOS capture shortcuts for start/stop and pause/resume.
- Added focused regression coverage for long sessions, realtime transcript tails, provider retries, floating-window placement, and translated-speech backlog behavior.

### Changed

- Long Apple sessions now coalesce recognition and presentation updates automatically after 4,000 characters, move expensive translation preparation off the MainActor, and use a bounded LRU segment cache.
- Gemini Live now configures low-latency activity detection and buffers a bounded amount of audio while setup completes.
- OpenAI text translation now streams partial results, applies bounded request timeouts, and retries rate-limit or server failures once.
- Realtime translated audio and Apple speech output now bound stale backlog instead of drifting farther behind live captions.
- The main workspace, sidebar, menu bar, floating captions, and settings surfaces now use clearer state hierarchy, keyboard access, and reduced-motion behavior.

### Fixed

- Fixed suppressed realtime transcript tails and empty completion events losing the last recognized words.
- Fixed pause, stop, and app termination paths so pending caption text is flushed before saving.
- Fixed floating caption windows reopening outside the visible area after display changes.
- Fixed Gemini connection failures potentially exposing an authenticated WebSocket URL in user-visible error text.

## 1.3.6 - 2026-06-13

### Added

- Added Gemini 3.5 Live Translate mode for direct live audio translation with input and output transcripts.
- Added Gemini API key storage and missing-key guidance alongside the existing OpenAI key workflow.
- Added a compact LIVE Translation entry point for API-backed GPT and Gemini modes.
- Added sidebar voice-output controls with a single volume slider for translated speech.

### Changed

- GPT mode now uses the realtime translation path only and shows source transcript updates returned by the realtime session.
- API-backed modes now use a shared translated-audio output path and default voice output on.
- Apple basic mode keeps voice output off by default while still allowing users to enable it manually.
- Settings and sidebar mode controls were redesigned so Apple, GPT Realtime, and Gemini Live are clearly separated.

### Fixed

- Fixed the quick source-language button path so changing the source language no longer silently switches to Transcribe Only mode.
- Fixed GPT realtime translation sessions not showing the original transcript.
- Fixed translated audio playback so GPT and Gemini live modes output the translated voice through one speaker path.
- Fixed Apple basic-mode translated speech output lowering the Mac system volume.

## 1.3.5 - 2026-06-13

### Changed

- Saved transcript history now loads lightweight previews first and opens full text only when a transcript is selected.
- Realtime GPT transcript updates are coalesced to reduce MainActor and UI churn during long sessions.
- Realtime audio send backlog is bounded so stalled websocket sends cannot accumulate without limit.
- Capture start now waits for previous stop teardown before opening a new capture session.

### Fixed

- Very large transcript panes now render a bounded display tail even in standard session mode while preserving the full saved text.
- GPT translated audio output now decodes base64 audio on the audio queue instead of the MainActor path.

## 1.3.4 - 2026-05-26

### Changed

- Floating caption wrapping now scales with the selected text size so larger caption fonts keep more usable text on screen.

### Applied Pull Requests

- Applied `lidge-jun` / YEEE's PR #6, "fix: scale floating caption wrapping by text size", as the 1.3.4 user-facing floating-caption improvement.

## 1.3.3 - 2026-05-26

### Added

- Added a clearer Transcribe Only output mode that hides the translation pane and keeps the live workspace focused on the original transcript.

### Changed

- Floating captions now preserve readable line wrapping while streaming and stay original-only while Transcribe Only mode is active.
- Transcribe Only mode now keeps its hidden target language synchronized with the visible source language so changing the source language does not silently switch back to Translation mode.

### Fixed

- Prevented translation-only floating caption display choices from creating blank captions while Transcribe Only mode is active.

### Applied Pull Requests

- Applied `lidge-jun` / YEEE's PR #4, "fix: wrap floating captions while streaming", as part of the 1.3.3 floating-caption behavior.
- Applied `lidge-jun` / YEEE's PR #5, "fix: improve transcribe-only mode behavior", with follow-up fixes for hidden target-language sync and Transcribe Only floating-display limits.
- Included PR #7, "Release AirTranslate 1.3.3", by `himomohi` / Appcaster to ship the aligned version, release notes, artifacts, and harness record.
- Release preparation also includes `lidge-jun` / YEEE's PR #3, "docs: add repository structure guide".

## 1.3.2 - 2026-05-17

### Fixed

- Centered the empty transcript placeholder so the no-captions state no longer sits too high in the main workspace.

## 1.3.1 - 2026-05-16

### Changed

- Temporarily disabled Apple basic-mode source-language auto-detection while the mid-session language-switch behavior is improved.
- Added an in-app notice when the disabled auto-detect toggle is clicked.
- Updated release packaging metadata for the 1.3.1 hotfix build.

### Fixed

- Prevented previously saved auto-detect settings from enabling the feature in the current build.

## 1.3.0 - 2026-05-16

### Added

- Added input support for built-in, Bluetooth, and AirPods microphones.
- Added source-language auto-detection for Apple basic mode when the input stream makes source language inference possible.

### Changed

- Improved microphone pipeline handling for long-running sessions to reduce duplicate input spikes.

### Fixed

- Fixed unstable microphone source behavior that could duplicate incoming segments.
- Improved input handling when switching between system audio and microphone capture.

## 1.2.1 - 2026-05-14

### Changed

- Apple mode now resets GPT transcription and translation model state when selected.
- Apple and GPT mode switching now uses shared session helpers to keep visible mode and internal processing state aligned.

### Fixed

- Fixed Apple default mode translation staying inactive while live transcription continued.
- Translation unavailable states now appear in the translation output instead of leaving the pane stuck on `Translating...`.

## 1.2.0 - 2026-05-13

### Added

- Added optional OpenAI Realtime transcription and translation modes for GPT-powered captions.
- Added a realtime translation-only model path with optional translated audio playback.
- Added macOS Keychain storage for user-provided OpenAI API keys.
- Added English, Korean, Japanese, and Simplified Chinese README files.
- Added separate Apple Intelligence Writing Tools buttons for the original and translation panes in the saved transcript editor.
- Added grouped saved transcript display for original-plus-translation saves.

### Changed

- GPT realtime floating captions now show only the current live caption unit instead of the accumulated transcript, so the overlay behaves more like movie subtitles.
- GPT realtime delta handling now builds the current utterance before publishing it to the caption flow.
- GPT modes disable transcript lint cleanup so realtime model output is not rewritten by Apple spell-check cleanup.
- Saved `Original + Translation` transcripts are now stored as separate `*_original.txt` and `*_translation.txt` files that share the same base name.
- The library presents those paired files as one saved transcript and shows original and translation editors in the same detail section.
- The saved transcript editor now uses plain `NSTextView` editors for Writing Tools so macOS treats each pane as editable plain text.
- The library row hit area now spans the full row, making saved transcript selection easier.

### Fixed

- Reduced duplicate source and translation text after paragraph cleanup or settings changes.
- Fixed GPT realtime floating captions so the overlay shows only the current live caption unit instead of the accumulated transcript.

## 1.1.0 - 2026-05-10

### Added

- Added a centered live audio waveform meter that reacts to captured system-audio decibel levels while capture is running.
- Added visible hover, pressed, active, and short click-confirmation feedback to the header transport controls.

### Changed

- Moved the live audio waveform out of the right-side button cluster into a wider center header area.
- Increased audio-level reporting frequency so the waveform responds more smoothly to current input.
- Kept stop, pause/resume, and floating-caption controls grouped on the right while preserving accessibility labels and values.

## 2026-05-09 - Library Modal UI

### Added

- Added a saved transcript content selector for original, original plus translation, or translation-only output.
- Added a confirmation-protected delete-all action for saved transcript files.

### Changed

- Moved saved transcript management out of the sidebar into a focused modal library view.
- Kept the sidebar storage area as a compact entry point for opening saved transcript management.

## 2026-05-09 - Transcript Control and Stability

### Added

- Added a settings control for the silence interval that starts a new transcript paragraph.
- The paragraph break interval keeps the previous default of 5 seconds and can now be adjusted from 1 to 15 seconds in 0.5 second steps.

### Fixed

- Limited live speech analyzer input buffering to the latest 32 audio chunks so delayed analysis cannot grow an unbounded queue.
- Limited the live translation segment cache to 240 recent entries and reset it when the session, language, or model changes.
- Disabled streaming text animation for long transcript updates to reduce SwiftUI layout and attributed-text work during long sessions.
