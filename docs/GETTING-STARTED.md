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
- **Qwen LiveTranslate (1.11.0+):** Add your Alibaba Cloud Singapore API key and workspace ID, then choose Qwen LiveTranslate in the mode picker. Choose the default Qwen3.8 model or Qwen Audio 3.1 Realtime Plus in Settings > General. Original transcripts and translations arrive directly from Qwen. Speech output is optional and initially off; Apple language packs are not needed for this mode.
- **Qwen Audio Filetrans (1.12.0+):** In Settings > General, submit a public HTTPS audio URL for asynchronous transcription. QwenCloud fetches the URL; the app does not upload a local audio file in this workflow. See [Qwen setup and pricing](qwen-livetranslate.md).

Provider keys are managed in **Settings > API Keys**. A configured key means AirTranslate has local provider settings; it does not prove provider account authorization until a session starts.

## Download Local Language Assets

Choose the source and target languages first, then open **Settings > Assets**. The speech recognition pack and translation language pack are separate. Use **Download** or **Retry** on the translation pack and approve the language download in the macOS prompt. AirTranslate refreshes the status when the download finishes; a cancelled or failed request can be retried.

If a system download cannot finish, check your connection and use **System Settings > General > Language & Region > Translation Languages** to manage the language packs. Download both languages in your selected pair. See [Apple's language download guide](https://support.apple.com/en-euro/guide/mac-help/-mchldd8b3c15/mac).

## Floating Captions

Show or hide floating captions from the main window, menu bar, or ⌘⇧C. The overlay displays caption text only and stays invisible when empty; it has no background, toolbar, status text, or hover resize controls.

Use Settings > Floating Captions for five text styles, font and color, width, line spacing, ordering, persistence, and reset. Preview sample captions without recording. Caption Stability remains a separate readability timing control.

## Transcript Files

Transcript file saving is off by default. Enable **Save Transcript Files** in Settings when you want dated `.txt` files under:

```text
~/Library/Application Support/AirTranslate/Transcripts/*.txt
```

When file saving is off, transcript text stays in memory for the current session and Stop or app quit does not create transcript files.
