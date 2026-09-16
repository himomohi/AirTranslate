<p align="center">
  <img src="docs/assets/airtranslate-readme-hero.png" alt="AirTranslate" width="720">
</p>

# AirTranslate

Live Mac audio captions and translation for meetings, videos, lectures, interviews, and streams.

<p align="center">
  <a href="https://github.com/himomohi/AirTranslate/releases/latest/download/AirTranslate.dmg"><img alt="Download AirTranslate.dmg" src="https://img.shields.io/badge/Download-AirTranslate.dmg-2EA44F?style=for-the-badge&logo=apple&logoColor=white"></a>
  <a href="https://github.com/himomohi/AirTranslate/releases/latest"><img alt="Latest public release" src="https://img.shields.io/github/v/release/himomohi/AirTranslate?style=for-the-badge&label=Latest"></a>
  <a href="LICENSE"><img alt="License: Apache 2.0" src="https://img.shields.io/badge/License-Apache%202.0-blue?style=for-the-badge"></a>
</p>

<p align="center">
  English ·
  <a href="README.ko.md">한국어</a> ·
  <a href="README.ja.md">日本語</a> ·
  <a href="README.zh-CN.md">中文</a> ·
  <a href="CHANGELOG.md">Changelog</a> ·
  <a href="docs/GETTING-STARTED.md">Getting Started</a>
</p>

AirTranslate captures audio playing on your Mac, transcribes it live, translates it when you choose a translation workflow, and can keep captions floating above other apps. Apple Mode remains the default local-first workflow. Cloud engines are optional and become available after you configure the matching provider key.

AirTranslate **1.9.0/build190** adds optional Nari STT and a redesigned API Keys screen.

## Download

Latest public release: **v1.9.0**.

- [Download AirTranslate.dmg](https://github.com/himomohi/AirTranslate/releases/latest/download/AirTranslate.dmg)
- [Download AirTranslate-1.9.0.zip](https://github.com/himomohi/AirTranslate/releases/download/v1.9.0/AirTranslate-1.9.0.zip)
- [Download AirTranslate.dmg.sha256](https://github.com/himomohi/AirTranslate/releases/latest/download/AirTranslate.dmg.sha256)
- [View release history](Release/VERSION-HISTORY.md)

The open-source DMG and ZIP are ad-hoc signed and not Apple-notarized. If macOS blocks the first launch, follow the [installation guide](docs/GETTING-STARTED.md). Check the DMG hash with:

```bash
shasum -a 256 AirTranslate.dmg
cat AirTranslate.dmg.sha256
```

## Real App

![AirTranslate workspace](docs/assets/airtranslate-workspace.jpg)

Current 1.9.0 local build, shown in Korean before starting capture.

AirTranslate keeps the source transcript and translated text in one workspace, with a floating caption option for watching or listening in another app.

<details>
<summary>API Keys screen</summary>

![AirTranslate API Keys](docs/assets/airtranslate-api-keys.jpg)

</details>

## Start In 3 Steps

1. Install the app, launch the exact copy you want to use, and allow Screen Recording and System Audio Recording when macOS asks.
2. Choose the source and target languages, then select Apple Mode or an optional engine from the console.
3. Press **Start**, play Mac audio or choose a microphone input, and read captions in the main workspace or floating caption window.

API-backed engines become available after you configure their keys in **Settings > API Keys**. A configured key means AirTranslate has local provider settings; provider access is checked when a session starts.

## Core Features

- System-audio capture through ScreenCaptureKit, plus built-in, Bluetooth, and AirPods microphone input.
- Apple Speech transcription and Apple Translation output as the default local-first path.
- Original-only transcription for source captions without translation.
- Floating captions, saved transcript library, optional translated speech, and one-click language swap.
- Transcript file saving is off by default; enable **Save Transcript Files** when you want plain `.txt` files in Application Support.
- Four app languages: English, Korean, Japanese, and Simplified Chinese.

## Engines

| Engine | Role | Requires |
| --- | --- | --- |
| Apple Mode | Default local-first transcription and translation. Apple basic-mode source-language auto-detect remains disabled while language-switch handling is improved. | None |
| GPT Mode | Live translated output through OpenAI Realtime. | OpenAI |
| GPT Transcription | Source-only captions through OpenAI. | OpenAI |
| Gemini Live | Gemini live translation or source-only transcription with automatic spoken-language detection. | Gemini |
| Meta Scribe | Speaker-labeled multilingual transcription before AirTranslate translation. | Meta |
| Azure MAI | Preview cloud transcription with Apple Translation captions. | Azure Speech key and endpoint |
| Nari STT | Prepared in 1.9.0 source for Qwen3-ASR source transcription from microphone or Mac audio. | Nari |

Nari STT is an optional 1.9.0 engine. The first Nari selection starts as original-only transcription; translation uses Apple Translation when the source language is available. Nari's current GA STT model IDs are qwen3-asr-fast and qwen3-asr; availability, rate limits, and paid credits follow Nari's provider documentation and account state, summarized in [docs/nari-stt.md](docs/nari-stt.md).

Nari supports manual source-language selection and automatic spoken-language detection, including Korean.

New Nari selections use the GA Fast model and require Nari credits. Saved Free Public Beta model choices are preserved and blocked from starting; they are never automatically upgraded to a paid model. Review the billing notice in Settings > General and explicitly select a GA model to resume Nari STT.

## API Keys

The 1.9.0 API Keys screen manages **OpenAI**, **Gemini**, **Meta**, **Azure**, and **Nari** in one provider list. Rows show configured/setup state, provider icons, key console links, and an information popover explaining that configured keys do not prove provider authorization.

Keys are stored in macOS Keychain. AirTranslate does not ship with an account system, a developer-operated relay server, or hardcoded provider keys.

## Privacy

- Apple Mode uses macOS frameworks and locally managed Apple language assets.
- GPT, Gemini, Meta, Azure, and Nari modes send only the audio or text needed for the selected feature directly to that provider using your key.
- Saved transcripts are normal text files on your Mac only when file saving is enabled.
- See [Release/PRIVACY-NOTICE.md](Release/PRIVACY-NOTICE.md) for the longer provider and storage guide.

## Requirements

- macOS 26.0 or later
- Swift 6.2 or later for source builds
- A Mac that supports system-audio capture
- Apple Speech and Apple Translation framework availability
- Optional provider keys for OpenAI, Gemini, Meta, Azure Speech, or Nari

## Documentation

- [Getting Started](docs/GETTING-STARTED.md)
- [Development](docs/DEVELOPMENT.md)
- [Nari STT notes](docs/nari-stt.md)
- [Changelog](CHANGELOG.md)
- [Version History](Release/VERSION-HISTORY.md)

<details>
<summary>Build from source</summary>

```bash
./script/build_and_run.sh
./script/build_and_run.sh --verify
swift test
```

More commands are in [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md).

</details>

## Contributing

Keep user-facing release chronology in [CHANGELOG.md](CHANGELOG.md). README files should describe the current product, download path, and provider boundaries instead of repeating every past release note.

## License

AirTranslate is released under the [Apache License 2.0](LICENSE). Copyright attribution is provided in [NOTICE](NOTICE).

AirTranslate is an independent open-source project and is not affiliated with Apple, OpenAI, Google, Meta, Microsoft, or Nari.
