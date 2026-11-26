# Former README release highlights

These version-by-version notes were moved out of the README. See the [changelog](../../CHANGELOG.md) for all releases.

## 1.20.0 Fast Captions and capture setup

- Use **Quality First / Fast Captions** at the top of Apple Mode. A change made during capture applies to the next capture. Fast Captions favors earlier drafts and may reduce accuracy.
- **Set Up Permissions** in Settings > Permissions checks the selected input and engine, skips granted permissions, and helps you continue after a visit to macOS System Settings.
- AirTranslate warms up ready Apple translation engines once per language pair for Quality First and Fast Captions. Fast Captions waits less for the first short phrase.
- The **Screen & System Audio Recording** row shows the permission used for Mac audio. The main window distinguishes **Waiting for Mac audio** from **Receiving Mac audio** before the first caption.

## 1.19.0 app updates

The installed version appears at the bottom left of the main window. Select it to check for the latest stable release. When an update is available, you can read its release notes or choose **Download Update**, which verifies the official DMG before you open it and replace the app in Applications.

## 1.18.1 packaging fix

AirTranslate **1.18.1 / build 1181** fixes startup failures in the DMG and ZIP by linking llama.cpp into the app. The release also omits absolute build-machine source paths. The app features and macOS requirements are unchanged from 1.18.0.

[Release notes](../GITHUB-RELEASE-1.18.1.md) · [AirTranslate 1.18.1 release](../GITHUB-RELEASE-1.18.1.md).

AirTranslate **1.18.0/build1180** adds optional local Hy-MT2 1.8B translation, a redesigned Focus Stage single-feed workspace with lower UI latency, adaptive floating-caption glass backdrops with a hover mini-HUD, a categorized Engine & Voice Hub, a Control Center–style Menu Bar panel, searchable Saved Transcripts with Markdown/TXT export, and an interactive Terminology Chip Editor. Apple Mode remains the default local-first workflow.

## New in 1.18.0: local Hy-MT2 translation, Focus Stage UI, and floating-caption HUD

- **Optional local Hy-MT2 1.8B translation:** select **Hy-MT2** in the Engine & Voice Hub, then open **Settings > General** and download the verified Q4_K_M weights (1.13 GB). Apple Speech provides transcription while the bundled llama.cpp runtime translates locally on your Mac with no API key or external translation server. Includes download progress, cancellation, model removal, local preview check, optional terminology hints, recent caption context, and up to 25-second Stop draining without saving incomplete fragments. [Setup and limits](../../docs/hymt-local-translation.md).
- **Focus Stage main window & lower live latency:** language pair selection and swap live in the top stage header, the single-row bottom glass console stays uncollapsed down to 840pt (including the 900pt default window), turns use timestamped cards with a live accent bar, and isolated audio-level metering (`SessionAudioWaveform`) avoids re-evaluating the console bar on audio updates.
- **Categorized Engine & Voice Hub:** filter engines by `All`, `On-Device`, or `Cloud` across separated on-device, cloud realtime translation, and cloud transcribe + local translate sections, with model, translated-speech voice, and API key shortcuts.
- **Adaptive floating captions & hover mini-HUD:** choose `Frosted Glass` (default), `Cinema Dark`, or `Transparent` backdrops for legibility over bright slides and videos, and hover over the floating window for instant pause/resume, copy latest caption, mode cycling, `A-`/`A+` sizing, backdrop toggle, and close actions.
- **Control Center Menu Bar, Library search/export & Terminology Chips:** the Menu Bar popover uses a 2×2 tile grid with direct `PC Audio` / `Microphone` switching; Saved Transcripts adds search, type filters, and Markdown (`.md`) / plain-text (`.txt`) export; Settings adds an interactive Terminology Chip Editor (with direct list editing toggle) and an API key count badge.
- **Reliability fixes:** Azure MAI capture-menu Stop drains finalized translations and excludes provisional drafts; EmbeddingGemma re-checks installed models after live capture ends and clarifies missing/unreadable audio recovery.

[Release notes](../GITHUB-RELEASE-1.18.0.md) · [AirTranslate 1.18.0 release](../GITHUB-RELEASE-1.18.0.md).

## Local English file transcription (from 1.17.0)

- **Optional file transcription:** open Settings > General > EmbeddingGemma 2 file transcription (experimental). Requires Apple Silicon and macOS 27+; the app itself still supports macOS 26+. English audio only, up to 60 minutes / 2 GB. It works separately from live captions and does not restore punctuation or capitalization, translate audio, or identify speakers.
- **How it works:** a frozen audio encoder produces time-based representations. A trained reader maps them to English word embeddings, selects a word or blank at each step, and CTC decoding combines repeated labels and removes blanks. This uses the independent public reader v2 reproduction; the original experiment's code and reader weights are not public.
- **Explicit model download and integrity:** choose Download models to fetch about 935 MB from a pinned Hugging Face revision. File sizes and SHA-256 hashes are verified before installation is accepted. Installation requires at least 2 GiB free; local model compilation also needs space. No API key is needed, and this option never uploads audio or transcript results.
- **Use and export:** stop live capture, download the models, choose an English audio file, and select Transcribe locally. Progress and Cancel are available; copy the result or save UTF-8 text. Cancellation discards the result after any active model call finishes. The current run shows audio length and processing time, including decoding and model loading.
- **Experimental accuracy and speed:** accents, noise, names, and words outside the fixed vocabulary affect results. First model loading may take longer. The original claim of one hour in about 13 seconds is not an AirTranslate performance guarantee.

[Method, setup and limitations](../../docs/embeddinggemma-transcription.md) · [AirTranslate 1.17.0 release](../GITHUB-RELEASE-1.17.0.md).

## Existing caption and translation improvements

The improvements introduced in **1.16.0** remain available below, including transcription stability, duplicate translation handling, caption reading, Apple translation options, optional Jev selection, and floating-only window controls. They are retained features, not new fixes in 1.17.0.

- **Floating-only start and controls:** starts an idle session or resumes a paused one, then minimizes the main window after capture is running. If startup fails, the main controls remain available. Start/stop and pause/resume are also available from the menu bar and app menus.
- **Previous-caption history:** keeps one previous caption block visible briefly alongside the current text, with up to two lines and an eight-second lifetime. It respects Reduce Motion.
- **Floating-caption rendering:** keeps current text in position without repeated replacement fades, reuses bounded layouts, and avoids repeatedly formatting the entire transcript. The minimized main window skips caption display work while recognition and translation continue.
- **Apple transcription and translation flow:** retains surrounding recognition context and preserves Apple-finalized segments when recognition advances, even without a separate final-text event. Previous segments are not lost or duplicated during that transition.
- **Reduced duplicate translation:** matching interim and final transcripts share the in-flight translation, and identical results are not applied twice.
- **Final captions and restarted sessions:** revised final text supersedes stale interim work. Late results or errors from stopped sessions cannot overwrite a new session, and repeated phrases in separate utterances keep their order.
- **Short transcript handling:** changing short fragments wait for a quiet interval after the last text change; complete phrases can proceed sooner. Punctuation-only results do not trigger translation.
- **Reading history and keeping your place:** scrolling through older captions pauses automatic following. Return to the latest captions to resume it; minimizing or hiding the main window preserves the reading position.
- **Less work for closed captions:** closing floating captions stops their display timers and layout work while transcription and translation continue.
- **Reopening floating captions:** restores the latest available text without retranslating it, prevents duplicated interim text, and clears a corrected source text's outdated translation after its hold period.
- **Main-window restoration:** exiting floating-only mode restores only the windows minimized by that mode, including when captions close during minimization. Windows you had already minimized are kept separate.
- **Consistent capture and menu controls:** main-window, menu-bar, and keyboard actions share preparation, finishing, and reconnecting states and available actions. Menus also share caption display mode and font-size controls.
- **Experimental Jev candidate selection:** off by default. In Apple transcription with translation, Jev can choose among supplied final recognition candidates before translation. Enabling it sends candidate text and up to six recent transcript segments (1,000 UTF-8 bytes) directly to TypeSafe using your Keychain-stored key. It adds API usage and up to 1.2 seconds of response waiting per request. Missing candidates, uncertainty, errors, or timeout keep the original. Accuracy improvement is not guaranteed. [Setup and data handling](../../docs/apple-translation-options.md).
- **Apple translation quality and protected terms:** on macOS 26.4+, choose Realtime (default) or Quality first and register terms to retain their spelling. Quality first may take longer and depends on Apple's available models. If it fails, the language pair uses realtime translation until app restart. If a registered term changes, the affected segment stays in its original language. These options apply to Apple text translation.
- **macOS 27 audio input compatibility:** adapts differing PCM input formats for Apple speech recognition, while retaining the existing 16 kHz mono path.
- **Source build requirements:** Xcode 27 with the macOS 27 SDK and Swift 6.4 or later. The distributed app still requires macOS 26 or later.

Configure an **Alibaba Cloud Singapore API key** in Settings > API Keys > Qwen. Qwen3.8 LiveTranslate also requires a workspace ID; Qwen Audio 3.1 Realtime Plus and Filetrans use the key without one. The key is stored separately in macOS Keychain; selected realtime audio is sent directly to Alibaba Cloud Singapore when capture starts. Choose the existing `qwen3.8-livetranslate-flash-realtime` default or `qwen-audio-3.1-realtime-plus` in Settings > General. Qwen Audio 3.1 Realtime Plus is a full-duplex voice-conversation model that receives translation instructions from AirTranslate; Qwen3.8 LiveTranslate is the dedicated realtime translation model. **Speech output is optional and initially off**. Current Qwen Audio pricing is shown in Model Studio.

Settings > General also includes `qwen-audio-3.1-asr-flash-filetrans` for asynchronous transcription. **Only a public HTTPS audio URL is accepted**; QwenCloud fetches its audio, and AirTranslate does not upload a local file in this workflow. Share only audio you are authorized to send. See [Qwen setup and pricing](../../docs/qwen-livetranslate.md). Real-account authentication, billing, translation and transcription quality, and latency remain unverified.

The **categorized Engine & Voice Hub** filters providers by `All`, `On-Device`, or `Cloud`, dims unavailable cloud providers without keys, and links directly to API key and model settings. Information icons describe the selected model and its pricing basis. **OpenAI Audio unifies translation and source transcription** while preserving the selected language and output preferences. Translated-speech models use a separate selector.

**Adaptive floating captions** support `Frosted Glass` (default), `Cinema Dark`, and `Transparent` backdrops plus a hover mini-HUD for pause/resume, copy, display-mode cycling, `A-`/`A+` sizing, backdrop toggle, and closing. Five text styles, font and color options, width, line spacing, ordering, and sample previews are available in Settings. Use the main window, menu bar, or ⌘⇧C to show or hide captions.

**Qwen final captions are drained before stopping**. Empty final results retract provisional captions, and saved Qwen transcripts contain confirmed results only, including periodic checkpoints. Apple Mode remains the default; transcript file saving remains opt-in.

**Translated speech output is selectable** in Settings and the main workspace's separate translated-speech control. Choose Apple system speech, Gemini 3.8 Flash or Flash-Lite TTS, or MAI Voice 2.1 or Flash. The choice is saved during realtime modes but used only for text translation; realtime providers keep their native audio. Gemini TTS sends only stable translated text to Google with your Gemini key.
