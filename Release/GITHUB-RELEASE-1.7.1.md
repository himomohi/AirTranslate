# AirTranslate 1.7.1

AirTranslate 1.7.1 steadies the floating caption overlay so live translations stop jumping, flickering, and rewriting mid-sentence, adds Caption Stability and Caption Alignment controls, and introduces a Presentation Quality mode for audience-facing interpretation.

AirTranslate is an independent open-source project and is not affiliated with Apple, OpenAI, Google, or Meta.

## Added

- **Caption Stability** (Responsive / Balanced / Steady) and **Caption Alignment** (Center / Left) are available in Settings and the menu bar. Steady holds each rewrite longer; Left keeps the start of each line fixed as text grows.
- **Presentation Quality mode** switches to a translation-only, two-line audience overlay with steadier clause timing. Optional talk context improves GPT text translation, while the terminology glossary protects names, brands, acronyms, and preferred translations across caption engines.

## Changed

- Floating captions now reserve a **fixed caption height** and fade replacement text in one piece, so the source line does not jump or re-center on every update.

## Fixed

- Floating translations no longer rewrite or flicker on every recognizer revision. The overlay **holds the previous translation** until a new one is ready, and wraps to the measured window width instead of leaving orphaned words.

## Scope

- Apple Mode remains the default local-first transcription and translation path.
- Meta Scribe, GPT, and Gemini modes remain optional. Each sends the audio or text needed for the selected feature directly to the corresponding external API using a user-provided key stored in macOS Keychain.
- This release does not add an account system or a developer-operated relay/backend server.
- This release does not change the existing ad-hoc signing and non-notarized distribution status.

## Verification

- Focused `FloatingTranslationPresentationTests` and `FloatingCaptionStabilityTests` coverage verifies independent translation dwell, newest-wins queuing, stale-translation hold, hold timeout, persistence, and measured-width wrapping.
- Local tests, a release build, and `./script/build_and_run.sh --verify` passed before packaging.
- Release candidates are built from repository source and checked for version/build metadata, the app bundle, LICENSE, NOTICE, code-signature integrity, ZIP/DMG contents, and checksums.
- Local tests and packaged artifacts do not prove Meta, OpenAI, or Gemini live connectivity; those paths require separately configured user API keys.
- macOS Gatekeeper may still show an unidentified-developer warning because these open-source artifacts are ad-hoc signed and not Apple-notarized.

## Download

- [Repository](https://github.com/himomohi/AirTranslate)
- [AirTranslate 1.7.1 release](https://github.com/himomohi/AirTranslate/releases/tag/v1.7.1)
- [Latest stable DMG download](https://github.com/himomohi/AirTranslate/releases/latest/download/AirTranslate.dmg)

## Distribution Notes

AirTranslate remains fully open-source under the Apache-2.0 License. Release DMG and ZIP artifacts are ad-hoc signed and are not Apple-notarized; macOS may show an unidentified-developer warning on first launch, and TCC permission inheritance across updates is not guaranteed.
