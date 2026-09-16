# AirTranslate 1.9.2

AirTranslate 1.9.2 fixes in-app translation language-pack downloads reported in [Issue #14](https://github.com/himomohi/AirTranslate/issues/14).

## Fixed

- **Settings > Assets > Translation Language Pack** now uses Apple's download approval flow to request missing source and target languages.
- Asset availability refreshes after a download. Cancelled or failed requests can be retried.
- Downloads remain tied to the selected language pair, preventing outdated completion from starting capture with different settings.

## Using the Fix

Select the source and target languages, open **Settings > Assets**, and choose **Download** or **Retry** for the translation language pack. Approve the language download when macOS asks. The system's network availability and supported languages still determine whether a download can finish.

Speech recognition assets remain a separate download. Apple Mode remains the default; optional cloud engines and provider credentials are unchanged.

## Download

- [Repository](https://github.com/himomohi/AirTranslate)
- [AirTranslate 1.9.2 release](https://github.com/himomohi/AirTranslate/releases/tag/v1.9.2)
- [Latest stable DMG download](https://github.com/himomohi/AirTranslate/releases/latest/download/AirTranslate.dmg)

## Distribution Notes

AirTranslate is an independent open-source project under the Apache-2.0 License and is not affiliated with Apple or its optional cloud providers. DMG and ZIP artifacts are ad-hoc signed and are not Apple-notarized. macOS may show an unidentified-developer warning on first launch; TCC permission inheritance across updates is not guaranteed. Compare the downloaded DMG with its `.sha256` file and follow [Apple's first-launch guidance](https://support.apple.com/guide/mac-help/mh40616/mac) if needed.
