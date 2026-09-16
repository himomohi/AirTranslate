# AirTranslate Development

AirTranslate is a macOS SwiftPM app. Use the repository scripts first so local app metadata, bundle generation, and verification stay aligned with release packaging.

## Common Commands

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

Reset development permissions for the local build:

```bash
./script/build_and_run.sh --reset-permissions
```

SwiftPM checks:

```bash
swift build
swift test
```

Release build:

```bash
swift build -c release
```

## Version Metadata

The app version and build number live in:

```text
script/app_metadata.sh
```

Release update sets should keep this file aligned with `CHANGELOG.md`, `Release/VERSION-HISTORY.md`, localized READMEs, `Release/GITHUB-RELEASE-<version>.md`, generated artifacts, checksums, and GitHub release state.

## Key Implementation Areas

- `SystemAudioCapture`: captures Mac system audio through ScreenCaptureKit.
- `LiveSpeechTranscriber`: streams speech recognition through Apple Speech.
- `AppleTranslationService`: isolates Apple Translation work.
- `OpenAIRealtimeTranscriber`: handles optional OpenAI realtime translation and transcription events.
- `GeminiLiveTranslationService`: handles optional Gemini Live Translate and Transcribe Live sessions.
- `MetaVoiceTranscribeService`: handles optional Meta Scribe sessions.
- `AzureMAITranscriber`: handles optional Azure MAI-Transcribe-2 REST segments.
- `NariRealtimeTranscriber`: handles optional Nari Qwen3-ASR realtime transcription.
- `TranslationSessionStore`: coordinates capture, transcript state, translation, saving, and playback.
- `APIKeySettingsView`: manages OpenAI, Gemini, Meta, Azure, and Nari keys.
- `CaptionBoardView`: displays live transcript, translation, controls, and audio meter.
- `TranscriptLibraryView`: manages saved transcript files.
- `FloatingCaptionWindowController`: owns floating caption window lifecycle.

## Release Checks

For public release preparation, run the project checks selected by the release harness. The usual local bundle is:

```bash
swift test
swift build -c release
./script/build_and_run.sh --verify
```

The public update-set audit should include localized README semantic checks. Keep generated artifacts under `Release/product/` out of commits unless the release process intentionally tracks that exact path.
