# AirTranslate Getting Started

This guide covers installation, first-launch permissions, provider setup, and the first caption session.

## Install The Public Build

1. Download the latest public DMG from [GitHub Releases](https://github.com/himomohi/AirTranslate/releases/latest).
2. Open the DMG and drag `AirTranslate.app` to Applications.
3. Open `AirTranslate.app` from Applications.
4. If macOS blocks the app, verify the download source and checksum, then follow [Apple’s instructions for opening an app from an unknown developer](https://support.apple.com/guide/mac-help/mh40616/mac): open **System Settings > Privacy & Security** and use **Open Anyway** for AirTranslate if you choose to allow it.

The current public DMG and ZIP are ad-hoc signed and not Apple-notarized. macOS may show an unidentified-developer warning on first launch, and TCC permission inheritance is not guaranteed across updates.

## Verify The Download

Download `AirTranslate.dmg.sha256` next to the DMG, then compare:

```bash
shasum -a 256 AirTranslate.dmg
cat AirTranslate.dmg.sha256
```

## First Launch

AirTranslate asks for the permissions used by the selected capture flow:

- Screen Recording
- System Audio Recording
- Microphone, only when microphone input is selected
- Speech Recognition

Screen Recording is required because ScreenCaptureKit provides the system-audio capture path. AirTranslate does not save screen frames as recordings.

When troubleshooting permissions, check which app copy is running. Older or differently signed builds can share `dev.appcaster.AirTranslate` while macOS keeps separate permission identities for them. Launch the intended copy before checking its permissions.

## Choose A Workflow

- **Apple Mode:** default local-first transcription and translation path. Choose the source language manually; Apple source-language auto-detection is currently disabled while language-switch handling is improved.
- **Transcribe Only:** source captions without translation.
- **OpenAI Audio, Gemini, Meta, Azure, or Nari:** optional provider modes that require user-supplied keys.
- **Grok STT (1.10.0+):** Grok Voice Transcribe 2.0 transcription with your own SpaceXAI (xAI) key. Select Grok STT after adding the key in API Keys. See [Grok STT notes](grok-stt.md).
- **Qwen LiveTranslate (1.11.0+):** Add your Alibaba Cloud Singapore API key, then choose Qwen LiveTranslate in the mode picker. Qwen3.8 also requires a workspace ID; Qwen Audio 3.1 Realtime Plus uses the key without one. Choose the model in Settings > General. Original transcripts and translations arrive directly from Qwen. Speech output is optional and initially off; Apple language packs are not needed for this mode.
- **Qwen Audio Filetrans (1.12.0+):** In Settings > General, submit a public HTTPS audio URL for asynchronous transcription. QwenCloud fetches the URL; the app does not upload a local audio file in this workflow. See [Qwen setup and pricing](qwen-livetranslate.md).
- **MAI-Transcribe-2-Streaming (1.15.0+):** In API Keys > Azure / Microsoft Foundry, choose the streaming model and enter the resource endpoint, resource key, and deployment name. Select Azure MAI for intermediate source captions and Apple translation of finalized text.
- **MAI Voice 2.1 / Flash (1.15.0+):** In Settings > Output, choose a translated-speech model and an automatic or target-language voice. Configure an OpenRouter key in API Keys. These models speak translated text; realtime audio providers keep their native output. See [MAI setup](microsoft-mai-audio.md).

Provider keys are managed in **Settings > API Keys**. A configured key means AirTranslate has local provider settings; it does not prove provider account authorization until a session starts.

## Apple Translation and Jev (1.16.0+)

Settings > General > Apple translation offers Realtime (default), Quality first, and protected terms on macOS 26.4+. Failed quality-first requests return to realtime for that language pair until restart. If a protected term is changed, its segment stays in the original language.

Experimental Jev candidate selection is separate and starts off. Add your own TypeSafe key in API Keys, then enable Jev in General only if you agree to send final recognition candidates and recent transcript context to TypeSafe. API usage and up to 1.2 seconds of response waiting per request are added. Uncertain or failed selections keep the original. See [configuration and data handling](apple-translation-options.md).

## Download Local Language Assets

Choose the source and target languages first, then open **Settings > Assets**. The speech recognition pack and translation language pack are separate. Use **Download** or **Retry** on the translation pack and approve the language download in the macOS prompt. AirTranslate refreshes the status when the download finishes; a cancelled or failed request can be retried.

If a system download cannot finish, check your connection and use **System Settings > General > Language & Region > Translation Languages** to manage the language packs. Download both languages in your selected pair. See [Apple's language download guide](https://support.apple.com/en-euro/guide/mac-help/-mchldd8b3c15/mac).

## Floating Captions

Show or hide floating captions from the main window, menu bar, or ⌘⇧C. The overlay displays caption text only and stays invisible when empty; it has no background, toolbar, status text, or hover resize controls.

Use Settings > Floating Captions for five text styles, font and color, width, line spacing, ordering, persistence, and reset. Preview sample captions without recording. Caption Stability remains a separate readability timing control.

Choose **Floating only** to start or resume capture and minimize the main window after startup succeeds. Startup failures leave the main controls available. Use the menu bar or app menus for start/stop and pause/resume. The combined main-and-floating view does not start a new session by itself. The previous-caption block remains for up to eight seconds and two lines.

## Transcript Files

Transcript file saving is off by default. Enable **Save Transcript Files** in Settings when you want dated `.txt` files under:

```text
~/Library/Application Support/AirTranslate/Transcripts/*.txt
```

When file saving is off, transcript text stays in memory for the current session and Stop or app quit does not create transcript files.
