# AirTranslate 1.18.1

AirTranslate **1.18.1 / build 1181** is a packaging-only update. The app features and macOS requirements are unchanged from 1.18.0.

## Fixed

- Fixes startup failures when macOS blocks the local translation framework in the signed DMG or ZIP. The release links llama.cpp into the app and omits absolute build-machine source paths.

## 한국어 요약

AirTranslate **1.18.1 / 빌드 1181**은 로컬 번역용 llama.cpp를 앱에 정적으로 링크해 DMG와 ZIP 배포본의 실행 실패를 수정합니다. 빌드 환경의 절대 소스 경로도 제거했습니다. 앱 기능과 macOS 요구 사항은 1.18.0과 같습니다.

## Compatibility and distribution

- Minimum system: **macOS 26+**. Optional EmbeddingGemma file transcription still requires Apple Silicon and macOS 27+.
- DMG and ZIP files are **ad-hoc signed and not Apple-notarized**. Follow the [installation guide](https://github.com/himomohi/AirTranslate/blob/master/docs/GETTING-STARTED.md) and verify the DMG's `.sha256` checksum before installing.

## Download

- [Repository](https://github.com/himomohi/AirTranslate)
- [AirTranslate 1.18.1 release](https://github.com/himomohi/AirTranslate/releases/tag/v1.18.1)
- [Latest stable DMG download](https://github.com/himomohi/AirTranslate/releases/latest/download/AirTranslate.dmg)
- [AirTranslate-1.18.1.zip](https://github.com/himomohi/AirTranslate/releases/download/v1.18.1/AirTranslate-1.18.1.zip)

Version: **1.18.1 / build 1181**.
