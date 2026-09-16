# AirTranslate Privacy Notice Draft

AirTranslate transcribes and translates audio playing on the user's Mac.

AirTranslate is an independent open-source project and is not affiliated with Apple, OpenAI, Google, Meta, Microsoft, or Nari Labs.

## Data Handling

- AirTranslate does not require an account.
- AirTranslate has no developer-operated relay or backend server. This does not mean optional provider modes are offline: when enabled, they send the audio or text needed for the selected feature directly to the corresponding external API.
- AirTranslate does not include analytics, ads, tracking SDKs, or telemetry SDKs.
- Captured audio is used for live transcription and translation while the user has capture running.
- Transcript file saving is off by default. When the user enables **Save Transcript Files**, saved transcripts are stored locally as plain-text files under the user's `~/Library/Application Support/AirTranslate/Transcripts` directory.
- Settings are stored locally with macOS app preferences.

## Apple System Services

AirTranslate uses Apple system frameworks, including ScreenCaptureKit, Speech, and Translation.

Speech recognition and language assets may be processed or downloaded through Apple-managed system services. AirTranslate does not send audio, transcripts, or translations to a server operated by this app's developer.

## Optional OpenAI GPT Mode

GPT mode is optional and works only after the user provides an OpenAI API key.

When GPT mode or an OpenAI translation model is enabled, AirTranslate sends the necessary audio or text to OpenAI's API to produce realtime transcription, translation, or translated audio output.

OpenAI API keys are user-provided runtime data. AirTranslate stores them in macOS Keychain and does not include API keys in the source tree, release scripts, or generated release bundles.

## Optional Gemini Live and Transcription Modes

Gemini Live Translate and Gemini 3.5 Transcribe Live are optional and work only after the user provides a Gemini API key.

When either Gemini mode is enabled, AirTranslate sends the audio needed for the selected live translation or source-only transcription feature directly to the Google Gemini API. Gemini 3.5 Transcribe Live automatically detects the spoken language and returns source captions rather than translations.

Gemini API keys are user-provided runtime data. AirTranslate stores them in macOS Keychain and does not include API keys in the source tree, release scripts, or generated release bundles.

## Optional Meta Scribe Mode

Meta Scribe is optional and works only after the user provides a Meta API key.

When Meta Scribe is enabled, AirTranslate sends the audio needed for Muse Voice Transcribe realtime transcription, speaker labels, and 25-language code-switching directly to Meta's API, then applies AirTranslate's existing translation layer locally or through the separately selected translation path.

Meta API keys are user-provided runtime data. AirTranslate stores them in macOS Keychain and does not include API keys in the source tree, release scripts, or generated release bundles.

## Optional Azure MAI Transcription

Azure MAI is optional and works only after the user provides an Azure Speech endpoint and API key.

When Azure MAI is enabled, AirTranslate sends audio in the selected source language to Azure Speech MAI-Transcribe-2 in 5-second segments, then uses Apple Translation for captions. Azure charges apply separately, and service availability depends on the user's Azure resource.

Azure Speech API keys are user-provided runtime data. AirTranslate stores them in macOS Keychain and does not include API keys in the source tree, release scripts, or generated release bundles. The Azure Speech endpoint is stored locally with macOS app preferences.

## Optional Nari STT

Nari STT is optional. When selected and started, it sends microphone or system
audio directly to Nari's API for Qwen3-ASR transcription. The user supplies their
own Nari API key, stored in a separate, device-local macOS Keychain item. Only
model and language-detection preferences are stored in app preferences.

Audio is buffered in memory for streaming and is not automatically replayed after
connection failures. Transcript file saving remains off by default. Optional
translation uses the existing Apple Translation path. Nari's account access,
retention, quotas, and service terms apply to the external service; AirTranslate
does not bundle a shared Nari credential or operate a relay.

## Permissions

AirTranslate requests only permissions tied to its core function:

- Screen Recording, because ScreenCaptureKit requires it for system audio capture.
- System Audio Recording, because the app captures audio playing on the Mac.
- Microphone, because the app captures microphone audio only after the user selects Microphone input and starts capture.
- Speech Recognition, because the app converts captured audio into text.

AirTranslate does not request Contacts, Calendar, Photos, Location, browser data, or Full Disk Access.
