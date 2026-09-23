# AirTranslate 1.12.1

AirTranslate 1.12.1 is a focused singleton release. It keeps the packaged macOS app to one running instance so launching it again does not create another process.

## Fixed

- **Single-instance app launch**: the packaged app now declares macOS single-instance behavior, preventing duplicate AirTranslate processes from normal Finder or `open` launches.

## Changed

- **Safer local release verification**: the local build-and-run harness no longer kills a running AirTranslate process or force-opens another copy. It asks the operator to quit AirTranslate before rebuilding, so verification uses one active app bundle.

## Verification Boundary

This release verifies the packaged app metadata and local launcher behavior. It does not change Qwen model selection, live provider authentication, billing, translation or transcription quality, latency, macOS Screen Recording approval, or Gatekeeper notarization status.

## Download

- [Repository](https://github.com/himomohi/AirTranslate)
- [AirTranslate 1.12.1 release](https://github.com/himomohi/AirTranslate/releases/tag/v1.12.1)
- [Latest stable DMG download](https://github.com/himomohi/AirTranslate/releases/latest/download/AirTranslate.dmg)

Version: **1.12.1 / build 1121**. Requires macOS 26 or later on Apple Silicon.

## Distribution Notes

AirTranslate is an independent Apache-2.0 project and is not affiliated with Apple or its optional cloud providers. DMG and ZIP artifacts are **ad-hoc signed and not Apple-notarized**. macOS may show an unidentified-developer warning on first launch; TCC permission inheritance across updates is not guaranteed. Compare the downloaded DMG with its `.sha256` file and follow [Apple's first-launch guidance](https://support.apple.com/guide/mac-help/mh40616/mac) if needed.
