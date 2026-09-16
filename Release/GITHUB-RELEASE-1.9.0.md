# AirTranslate 1.9.0

AirTranslate 1.9.0 adds optional Nari STT for Qwen3-ASR source transcription, redesigns API key management around provider rows, and moves long README release chronology into the changelog and version history.

AirTranslate is an independent open-source project and is not affiliated with Apple, OpenAI, Google, Meta, Microsoft, Azure, or Nari.

## Added

- **Nari STT** is available as an optional transcription engine in the 1.9.0 source release set. It sends microphone or Mac audio to Nari Qwen3-ASR only after the user selects Nari STT and configures a Nari API key.
- Nari model selection supports the current GA STT IDs `qwen3-asr-fast` and `qwen3-asr`. Model availability, limits, and paid-credit requirements follow Nari's current provider documentation and account state.
- Nari source-language handling supports manual source language selection and Nari-specific automatic spoken-language detection for supported spoken languages, including Korean.

## Changed

- **API Keys** now manages OpenAI, Gemini, Meta, Azure, and Nari in one provider list with saved/setup state, active-engine context, provider icons, key-console links, and a Keychain information popover.
- Selecting Nari STT starts as original-only transcription by default. Users can switch output to translation when the selected or detected source language is available in AirTranslate's Apple Translation workflow.
- New Nari selections use the GA Fast model with a paid-credit notice. Saved Free Public Beta model choices are preserved and blocked from starting, without automatic migration to a paid model. Review billing in Settings > General and explicitly select a GA model to resume Nari STT.
- Localized README files now focus on the current product, download path, engines, privacy boundary, and documentation links. Complete release chronology remains in `CHANGELOG.md` and `Release/VERSION-HISTORY.md`.
- Release metadata and public README download links are updated for 1.9.0/build190.

## Fixed

- Nari API key presence checks avoid reading secret values or triggering Keychain authentication UI during startup status checks.
- Nari session lifecycle handling preserves completed source captions across pause, stop, reconnect, and queue-limit failures while avoiding automatic replay of unfinished audio.
- README provider copy now distinguishes a configured key from verified external provider authorization.

## Scope

- Apple Mode remains the default local-first transcription and translation path.
- Nari, Azure MAI, Meta Scribe, GPT, and Gemini remain optional provider modes. Each sends the audio or text needed for the selected feature directly to the corresponding external API using a user-configured key stored in macOS Keychain.
- Configuring a provider key does not verify account access, quota, region support, model entitlement, transcription accuracy, or latency. Provider access is checked when a session starts.
- Nari STT does not add TTS or voice cloning.
- This release does not add an account system or a developer-operated relay/backend server.
- This release does not change the existing ad-hoc signing and non-notarized distribution status.

## Verification

- The final GA and saved-free-model recovery changes passed 315 tests in 36 suites and a release build on 2026-09-16.
- The rebuilt-app UI gate passed for five API-key provider rows, keyboard focus, the Keychain information popover, GA billing notices, blocked free-model starts, General settings recovery, and clearing the old error after an explicit GA selection or return to Apple Mode. Detailed evidence is in [the publication report](https://github.com/himomohi/AirTranslate/blob/master/docs/release/1.9.0-publication-2026-09-16.md).
- Rebuilt ZIPs and DMGs passed bundle-version, license, signature, entitlement, checksum, and secret/sensitive-file checks. The source and final rebuilt-artifact security gates passed. Release signatures remain ad-hoc; Apple notarization has not been performed.
- The public update-set audit passed with 48 localized README content checks and all six release assets. GitHub publication and downloaded-asset verification are tracked by the release harness.
- Real Nari account authorization, live service connectivity, provider quota, real microphone or Mac-audio accuracy, and latency remain unverified until tested with an actual Nari account and audio source.

## Download

- [Repository](https://github.com/himomohi/AirTranslate)
- [AirTranslate 1.9.0 release](https://github.com/himomohi/AirTranslate/releases/tag/v1.9.0)
- [Latest stable DMG download](https://github.com/himomohi/AirTranslate/releases/latest/download/AirTranslate.dmg)

## Distribution Notes

AirTranslate remains fully open-source under the Apache-2.0 License. Release DMG and ZIP artifacts are ad-hoc signed and are not Apple-notarized; macOS may show an unidentified-developer warning on first launch, and TCC permission inheritance across updates is not guaranteed. Compare `AirTranslate.dmg.sha256` with the downloaded DMG checksum. If macOS blocks the app, follow [Apple’s first-launch instructions](https://support.apple.com/guide/mac-help/mh40616/mac).
