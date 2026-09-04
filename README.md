![AirTranslate hero](docs/assets/airtranslate-readme-hero.png)

# AirTranslate

Live system-audio transcription and translation for macOS.

<p align="center">
  <a href="https://github.com/himomohi/AirTranslate/releases/latest/download/AirTranslate.dmg"><img alt="Download AirTranslate.dmg" src="https://img.shields.io/badge/Download-AirTranslate.dmg-2EA44F?style=for-the-badge&logo=apple&logoColor=white"></a>
  <a href="https://github.com/himomohi/AirTranslate/releases/latest"><img alt="Latest release" src="https://img.shields.io/github/v/release/himomohi/AirTranslate?style=for-the-badge&label=Latest"></a>
  <a href="https://himomohi.github.io/AirTranslate/"><img alt="Official guide site" src="https://img.shields.io/badge/Guide-Site-0A84FF?style=for-the-badge"></a>
</p>

<p align="center">
  <a href="https://himomohi.github.io/AirTranslate/">Guide Site</a> ·
  <a href="#download">Download</a> ·
  <a href="#requirements">Requirements</a> ·
  <a href="#privacy-and-api-keys">Privacy</a> ·
  English ·
  <a href="README.ko.md">한국어</a> ·
  <a href="README.ja.md">日本語</a> ·
  <a href="README.zh-CN.md">中文</a>
</p>

<p align="center">
  <img alt="macOS 26+" src="https://img.shields.io/badge/macOS-26%2B-0A84FF?style=flat-square&logo=apple">
  <img alt="Swift 6.2+" src="https://img.shields.io/badge/Swift-6.2%2B-F05138?style=flat-square&logo=swift&logoColor=white">
  <a href="LICENSE"><img alt="License: Apache 2.0" src="https://img.shields.io/badge/License-Apache%202.0-blue?style=flat-square"></a>
</p>

AirTranslate captures audio playing on your Mac, turns it into a live transcript, translates it in real time, and can show the result as a floating caption overlay. It is designed for meetings, lectures, videos, interviews, and streams where routing audio through a microphone is awkward or lossy.

For a user-facing overview, setup guide, and download path, visit the [AirTranslate Guide Site](https://himomohi.github.io/AirTranslate/).

The default workflow uses Apple frameworks. GPT Realtime, Gemini Live Translate, and Meta Scribe are optional API-backed modes and can be enabled from the app only after you provide the matching API key.

## Why AirTranslate

- **System-audio first:** capture Mac playback audio directly with ScreenCaptureKit.
- **Readable live workspace:** source and translated text stay side by side.
- **Floating captions:** keep subtitles above other apps while you watch or listen.
- **Apple by default:** Apple Speech and Apple Translation remain the baseline path.
- **Optional API modes:** OpenAI Realtime Translation, Gemini Live Translate, and Meta Scribe can be enabled only when needed.
- **Keychain storage:** OpenAI, Gemini, and Meta API keys are entered by the user and stored in macOS Keychain.
- **Optional plain text history:** transcript files are off by default and can be enabled from Settings; saved transcripts remain normal `.txt` files in Application Support.

![AirTranslate demo](docs/assets/airtranslate-readme-demo.gif)

> "Turn any Mac audio into live captions and translation, right where you are watching."

## What's New in 1.7.1

- **Steadier floating translations:** The overlay holds the previous translation until a new one is ready, so live captions no longer rewrite or flicker on every recognizer revision.
- **Reserved caption height:** Floating captions keep a fixed block height and fade replacements in one piece, so the source line does not jump or re-center as text grows.
- **Caption Stability and alignment:** Settings and the menu bar now offer Caption Stability (Responsive / Balanced / Steady) and Caption Alignment (Center / Left). Left-aligned captions stay anchored as the line grows.
- **Presentation Quality mode:** One switch configures a translation-only, two-line audience overlay with steadier clause timing. Add talk context and a terminology glossary to protect names, brands, acronyms, and preferred Japanese wording.

See the complete [AirTranslate 1.7.1 release notes](https://github.com/himomohi/AirTranslate/releases/tag/v1.7.1).

## What's New in 1.7.0

- **Meta Scribe:** Optional Muse Voice Transcribe adds realtime transcription, speaker labels, and 25-language code-switching before AirTranslate's existing translation layer. Provide a Meta API key from Settings; Apple Mode stays the local-first default.
- **Stage & Console:** The settings sidebar is gone. Live captions fill the window as turn-based blocks, with the newest turn just above a floating console bar for Start/Stop, audio source, language route, output mode, voice, and the active engine.
- **Shared Air teal design system:** Listening, paused, and stopped colors, layered surfaces, and a caption typography scale now apply across the main window, Settings, transcript library, floating captions, and menu bar in light and dark appearance.
- **Keyboard focus ring:** Custom controls use an accent-colored focus ring, Start receives initial focus, and session-locked controls stay dimmed with a single lock indicator while remaining fully described to assistive technologies.
- **Apple Mode stays fast on long sessions:** Apple Mode now rolls the live line into a new turn block after roughly 600 committed characters or a long silence, so recognition updates no longer reprocess the entire transcript on the main thread. Saved transcripts still contain the full session.
- **Stage no longer goes blank:** The feed renders the 12 most recent turn blocks with a plain stack, which fixes disappearing captions after a long session or stop/start and keeps rendering cost constant.

See the complete [AirTranslate 1.7.0 release notes](https://github.com/himomohi/AirTranslate/releases/tag/v1.7.0).

## What's New in 1.6.2

- **One Screen Recording request:** AirTranslate opens the macOS Screen Recording request only on the first attempt that needs it. Later failures point to Privacy & Security settings instead of repeatedly reopening the system prompt.
- **One intended app installation:** Older or differently signed AirTranslate copies can share `dev.appcaster.AirTranslate` while macOS treats them as different TCC permission identities. Remove or archive the other copies and keep only the installation you intend to run.
- **Accurate ad-hoc update boundary:** Public DMG and ZIP builds are ad-hoc signed, so Screen Recording permission is not guaranteed to carry over between updates. A newly installed build may need to be confirmed again in System Settings.
- **Hidden Settings focus loop removed:** A segmented `Picker` in the hidden Settings Scene no longer switches to disabled while capture starts. That invisible AppKit focus-navigation/AttributeGraph loop could consume CPU and make the top Gemini Live Start control appear stuck; startup now proceeds normally.

See the complete [AirTranslate 1.6.2 release notes](https://github.com/himomohi/AirTranslate/releases/tag/v1.6.2).

## What's New in 1.6.1

- **Gemini Live Start is reliable:** The top Start control now begins capture in the selected Gemini Live mode.
- **Responsive capture controls:** Locked segmented controls keep their visible state without using the macOS disabled-state focus path that could cause an AttributeGraph CPU loop during startup.
- **Actionable start recovery:** A start failure stays in the main window with a direct API-key Settings, macOS Privacy Settings, or retry action instead of disappearing in a transient overlay.
- **Current-build permission guidance:** Permission help identifies the current signed AirTranslate build. When macOS does not recognize it, keep the active copy, refresh only the affected permission once, then quit and relaunch; routine TCC resets are not needed.

See the complete [AirTranslate 1.6.1 release notes](https://github.com/himomohi/AirTranslate/releases/tag/v1.6.1).

## What's New in 1.6.0

- **Gemini source-only transcription with automatic language detection:** Choose optional **Gemini 3.5 Transcribe Live** for original-only captions. Gemini detects the spoken language during capture after you add your own Gemini API key.
- **More resilient long-running Gemini sessions:** Finished-state handling, session resumption, GoAway reconnect recommendations, bounded context compression, and 40 ms audio chunks keep the Gemini Live path prepared for extended capture.
- **Responsive original-only workflow:** The smallest supported workspace and Settings windows reflow instead of hiding controls. Apple, GPT, and Gemini transcription modes consistently remove target-language, translated-text, and translated-voice controls.

See the complete [AirTranslate 1.6.0 release notes](https://github.com/himomohi/AirTranslate/releases/tag/v1.6.0).

## What's New in 1.5.1

- **Minimal, consistent interface:** The workspace, sidebar, menu bar, floating captions, transcript library, and Settings now share one restrained system for spacing, icons, surfaces, selection, and hover feedback.
- **Clearer settings status:** Separate permission rows show the available state or direct you to verify it in System Settings, language assets expose download progress and retry states, and the About pane shows the app version and build.
- **More reliable settings controls:** Voice volume follows the voice-output state, API-key persistence uses one session-store path, startup checks Keychain presence without reading secret data or showing authentication UI, and floating-caption previews follow the selected display mode.
- **Keyboard and accessibility:** Settings preserve section identity while navigating, provide clearer accessibility labels and values, and respect Reduce Motion.

See the complete [AirTranslate 1.5.1 release notes](https://github.com/himomohi/AirTranslate/releases/tag/v1.5.1).

## What's New in 1.5.0

- **Apple Mode lifecycle hardening:** Apple Mode remains the default local-first path and now ignores late permission, warm-up, and capture callbacks from an older start attempt.
- **Clean external stops:** stopping macOS system-audio capture outside the app now saves the transcript, unlocks the session, and permits a clean restart.
- **No silent speech-input loss:** audio backpressure becomes a visible controlled stop instead of silently dropping input.
- **Optional GPT Transcription:** choose `gpt-live-transcribe` for source-only captions only when you provide an OpenAI API key; it is separate from GPT live translation.

See the complete [AirTranslate 1.5.0 release notes](https://github.com/himomohi/AirTranslate/releases/tag/v1.5.0).

## What's New in 1.4.2

- **Reliable microphone permission prompt:** signed local and release builds now embed the macOS microphone audio-input entitlement required for permission requests.
- **Release-signing guard:** packaging checks verify Hardened Runtime, the release/debug entitlement split, and the microphone permission description before distribution.

See the complete [AirTranslate 1.4.2 release notes](https://github.com/himomohi/AirTranslate/releases/tag/v1.4.2).

## What's New in 1.4.1

- **Steadier translated speech:** Apple Mode now waits for stable sentence boundaries before speaking streaming translated text.
- **Final text still speaks:** final translations that arrive without punctuation are spoken when the translation request completes.
- **Fewer repeated tails:** restored sentence tails, near-duplicate finalization variants, and short repeated suffixes are suppressed instead of being spoken again.
- **Cleaner dubbing handoff:** enabling translated speech no longer rereads translation text that was already visible.
- **Legitimate repeats preserved:** repeated phrases can still be spoken later in a session after the short replay window expires.
- **Focused regression coverage:** the translated-speech progress logic is covered by dedicated AirTranslateCore tests.

See the complete [AirTranslate 1.4.1 release notes](https://github.com/himomohi/AirTranslate/releases/tag/v1.4.1).

## Core Features

- Live Mac system-audio capture
- Apple Speech transcription
- Apple Translation output
- Transcribe Only mode with an original-only live workspace
- Built-in, Bluetooth, and AirPods mic input support
- Apple basic-mode source-language auto-detect is temporarily disabled while language-switch handling is improved.
- GPT mode with OpenAI Realtime Translation
- Optional GPT Transcription with `gpt-live-transcribe` for source-only captions
- Gemini 3.5 Live Translate mode and optional Gemini 3.5 Transcribe Live source-only mode with automatic spoken-language detection
- Optional Meta Scribe mode with Muse Voice Transcribe for speaker-labeled, 25-language captions before AirTranslate translation
- Microphone input stability fixes for duplicate segments and noisy transitions
- LIVE Translation mode for API-backed translated streams
- One-click source/target language swap
- Floating caption window
- Transcript polish based on macOS spelling suggestions
- Optional translated speech output
- Saved transcript library with edit, delete, and folder access
- English, Korean, Japanese, and Simplified Chinese interface selection based on the Mac language

## Processing Modes

AirTranslate separates the quick choice from the detailed setup.

| Mode | Best For | Details |
| --- | --- | --- |
| Apple Mode | Local-first transcription and translation | Uses Apple Speech for transcription and Apple Translation for the selected language pair. Source-language auto-detect is temporarily disabled while language-switch handling is improved. |
| GPT Mode | OpenAI Realtime live translation | Streams audio directly to OpenAI Realtime Translation. If no API key is saved, AirTranslate opens the settings modal and focuses the API key field. |
| GPT Transcription | OpenAI source-only captions | Uses `gpt-live-transcribe` for source-language captions without translation after you choose this optional mode and provide an OpenAI API key. |
| Gemini Live | Gemini 3.5 Live Translate or source-only transcription | Choose Gemini 3.5 Live Translate for returned input and translated transcripts, or Gemini 3.5 Transcribe Live for original-only captions with automatic spoken-language detection. Both require your Gemini API key. |
| Meta Scribe | Speaker-labeled multilingual captions | Uses Muse Voice Transcribe for realtime transcription with speaker labels and 25-language code-switching, then AirTranslate's existing translation layer. Requires your Meta API key. |
| Transcribe Only | Source captions without translation | Records source-language captions without running translation. |
| LIVE Translation | Direct translated stream | Uses the selected API provider's live translation model path when you want the model to produce the translated stream directly. |

GPT, Gemini, and Meta model details, API key entry, transcript polish, and voice output are managed from the gear-shaped Settings window. Everyday capture controls live in the floating console bar under the Stage.

## Privacy And API Keys

AirTranslate does not ship with an account system or a developer-operated relay/backend server. This does not mean every mode is offline: optional provider modes send the audio or text needed for the selected feature directly to the corresponding external API.

- Apple Mode uses macOS frameworks and locally managed Apple language assets.
- OpenAI sends happen only when GPT Mode or the optional GPT Transcription mode is enabled; the required audio or text goes directly to OpenAI's API using your OpenAI API key.
- Gemini sends happen only when Gemini Live Translate or Gemini 3.5 Transcribe Live is enabled; the required audio goes directly to the Google Gemini API using your Gemini API key.
- Meta Scribe sends happen only when Meta Scribe is enabled; the required audio goes directly to Meta's Muse Voice Transcribe API using your Meta API key.
- OpenAI, Gemini, and Meta API keys are user-provided, saved in Keychain, and never hardcoded, committed, or included in release packages.
- Keys are saved in macOS Keychain with `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`.
- Saved transcripts are plain text files on your Mac.

Need an API key? Open the [OpenAI API key page](https://platform.openai.com/api-keys), [Google AI Studio API key page](https://aistudio.google.com/app/apikey), or [Meta developer portal](https://dev.meta.ai), create a key, then paste it into AirTranslate's Settings window.

## Apple Translation Language Packs

Apple Mode uses macOS-managed translation languages. Before using Apple Mode with a new language pair, download the needed Apple translation language packs:

1. Open **System Settings**.
2. Go to **General > Language & Region**.
3. Click **Translation Languages**.
4. Click **Download** for each source and target language you want to use.
5. Optional: turn on **On-Device Mode** if you want macOS to process supported translations on your Mac whenever possible.

If a selected language pair is unavailable or not downloaded, Apple Mode translation may not start or may show an unavailable state until macOS has the required language assets.

## Permissions

AirTranslate asks for the permissions required by its capture and transcription flow.

- Screen Recording
- System Audio Recording
- Microphone (only when microphone input is selected)
- Speech Recognition

Screen Recording is required because ScreenCaptureKit provides the system-audio capture path. AirTranslate does not save screen frames as recordings. AirTranslate opens the system request only on the first attempt that needs it; after that, unavailable access is handled with a link to Privacy & Security settings rather than another request prompt.

Before troubleshooting, remove or archive older AirTranslate copies from Applications, Downloads, development `dist` folders, and other launch locations. Keep one intended installation, launch that exact copy, and verify its version in **Settings > About**. Older or differently signed copies can use the same `dev.appcaster.AirTranslate` bundle identifier while macOS stores separate TCC permission identities for them.

If the current app is still unavailable after the first request, open **System Settings > Privacy & Security > Screen & System Audio Recording**, confirm the current installation, then quit and relaunch. Routine `tccutil` resets are not needed. Public ad-hoc signed builds do not guarantee TCC permission inheritance between updates, so a newly installed build may need to be confirmed again.

If Gemini Live Start previously appeared stuck despite correct permissions, verify that **Settings > About** shows 1.7.1 or later. Releases from 1.6.2 onward prevent the hidden Settings segmented control from entering the AppKit focus-navigation/AttributeGraph loop during startup.

## Download

Download the latest open-source build from [GitHub Releases](https://github.com/himomohi/AirTranslate/releases/latest). The DMG is the easiest install path, and the ZIP remains available as the original lightweight option.

AirTranslate remains fully open-source under the Apache-2.0 License. The DMG is provided only as a convenient macOS installer, while all source code, build scripts, release materials, LICENSE, and NOTICE files remain available in this repository.

- [Download AirTranslate.dmg](https://github.com/himomohi/AirTranslate/releases/latest/download/AirTranslate.dmg)
- [Download AirTranslate-1.7.1.zip](https://github.com/himomohi/AirTranslate/releases/download/v1.7.1/AirTranslate-1.7.1.zip)
- [Download AirTranslate.dmg.sha256](https://github.com/himomohi/AirTranslate/releases/latest/download/AirTranslate.dmg.sha256)
- [View version history](Release/VERSION-HISTORY.md)

![AirTranslate install guide](docs/assets/airtranslate-install-guide.svg)

The open-source DMG and ZIP are ad-hoc signed builds for pre-notarization distribution. On the first launch, macOS may show an "unidentified developer" warning. Ad-hoc signing also means TCC permission inheritance is not guaranteed across updates. To open the app:

1. Open the DMG and drag `AirTranslate.app` to Applications.
2. In Applications, Control-click or right-click `AirTranslate.app`.
3. Choose **Open**, then choose **Open** again in the macOS warning dialog.

You can verify the DMG checksum after downloading:

```bash
shasum -a 256 AirTranslate.dmg
cat AirTranslate.dmg.sha256
```

Developer ID signing and notarization are planned for a later distribution step.

## Requirements

- macOS 26.0 or later
- Swift 6.2 or later
- A Mac that supports system-audio capture
- Apple Speech and Apple Translation framework availability
- Optional: an OpenAI API key for GPT mode
- Optional: a Gemini API key for Gemini Live mode
- Optional: a Meta API key for Meta Scribe mode

## Build From Source

### Install the privacy-fixed custom build on another Mac

On an Apple Silicon Mac running macOS 26 or later, paste this block into Terminal. It downloads an immutable installer revision and verifies its SHA-256 digest before execution:

```bash
INSTALLER_COMMIT="2cffcdde08e7d9d4cb7408aa1c34e08df8a753a2"
INSTALLER_SHA256="49ea3e8b1b6fcd2df4adf8e649af12ef634baf471facf611d746c2866e4469f7"
INSTALLER_PATH="$(mktemp "${TMPDIR:-/tmp}/airtranslate-installer.XXXXXX")"
curl -fL "https://raw.githubusercontent.com/gary8020/AirTranslate/$INSTALLER_COMMIT/script/install_on_this_mac.sh" -o "$INSTALLER_PATH"
printf '%s  %s\n' "$INSTALLER_SHA256" "$INSTALLER_PATH" | shasum -a 256 -c -
AIRTRANSLATE_SOURCE_REVISION="$INSTALLER_COMMIT" /bin/bash "$INSTALLER_PATH" install
rm -f "$INSTALLER_PATH"
```

The installer downloads the pinned source commit, creates a release build locally, checks
the app bundle's code-signature integrity, installs it to
`~/Applications/AirTranslate.app`, and opens it. It does not copy API keys,
transcripts, or settings from another Mac. Each Mac must grant its own
Microphone and Speech Recognition permissions and download any required Apple
language assets. macOS may ask for those permissions again after an update if
the Mac does not have a persistent code-signing identity.

Running a newer verified installer block updates the source and preserves one previous app at
`~/Library/Application Support/AirTranslate Custom Build/backups/AirTranslate-previous.app`
before installing the new build.

Run the app bundle:

```bash
./script/build_and_run.sh
```

Build and verify launch:

```bash
./script/build_and_run.sh --verify
```

View logs:

```bash
./script/build_and_run.sh --logs
```

Reset development permissions:

```bash
./script/build_and_run.sh --reset-permissions
```

SwiftPM checks:

```bash
swift build
swift test
```

## Basic Usage

1. Choose the source and target languages.
2. Use the center swap button if you want to reverse the direction.
3. Choose Apple Mode, GPT Mode, Gemini Live, or Meta Scribe from the console bar.
4. For API-backed modes, add the matching OpenAI, Gemini, or Meta API key in Settings if prompted.
5. Press Start.
6. Play meeting, lecture, video, interview, or stream audio on your Mac.
7. Read the transcript and translation in the main workspace or floating caption window.
8. If you enabled **Save Transcript Files** in Settings > Transcript, press Stop to save the current transcript.

## Saved Transcripts

Saved transcripts are stored as plain text files:

```text
~/Library/Application Support/AirTranslate/Transcripts/*.txt
```

Transcript file saving is off by default. Enable **Save Transcript Files** in Settings > Transcript to opt in. When it is off, transcript text stays in memory for the session and Stop or app quit does not create a `.txt` file.

When source and translation are saved together, AirTranslate writes separate `_original.txt` and `_translation.txt` files while presenting them as one grouped item in the library UI.

## Project Map

```text
Package.swift
Resources/
  AppIcon.png
  AppIcon.icns
Sources/AirTranslate/
  App/
  Models/
  Services/
  Support/
  Views/
Sources/AirTranslateCore/
Tests/
script/
  build_and_run.sh
docs/assets/
  airtranslate-readme-hero.png
```

## Key Implementation Areas

- `SystemAudioCapture`: captures Mac system audio through ScreenCaptureKit.
- `LiveSpeechTranscriber`: streams speech recognition through Apple Speech.
- `AppleTranslationService`: isolates Apple Translation work.
- `OpenAIRealtimeTranscriber`: handles optional OpenAI realtime translation and transcript events.
- `GeminiLiveTranslationService`: handles optional Gemini Live Translate websocket sessions.
- `OpenAIAPIKeyStore` / `GeminiAPIKeyStore`: save API keys in macOS Keychain.
- `TranslationSessionStore`: coordinates capture, transcript state, translation, saving, and playback.
- `SidebarView`: language, mode, session, and settings entry points.
- `CaptionBoardView`: live transcript, translation, controls, and audio meter.
- `TranscriptLibraryView`: saved transcript management.
- `FloatingCaptionWindowController`: floating subtitle window lifecycle.

## License

AirTranslate is released under the [Apache License 2.0](LICENSE). Copyright attribution is provided in [NOTICE](NOTICE).

AirTranslate is an independent open-source project and is not affiliated with Apple, OpenAI, or Google.
