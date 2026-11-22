# AirTranslate 1.20.0

## Faster first captions in Apple Mode

- Switch between **Quality First** and **Fast Captions** at the top of the main window. A change made during capture applies to the next capture.
- Fast Captions uses faster speech recognition and realtime translation. Drafts can appear earlier, with a possible accuracy trade-off. It also shortens the wait for the first short phrase.
- For a ready language pair, both modes can run a short warm-up translation once as capture starts. The warm-up result never appears in captions or transcript history.

## Clearer capture setup

- **Settings > Permissions > Set Up Permissions** checks the permissions needed for your selected input and engine. It skips allowed permissions and helps you continue after allowing access in macOS System Settings.
- The **Screen & System Audio Recording** row shows the permission check used for Mac audio. Before the first caption, the main window shows when it is waiting for playback or receiving Mac audio. Fixes [issue #19](https://github.com/himomohi/AirTranslate/issues/19).

## 한국어 요약

- Apple 기본 모드에서 **품질 우선 / 빠른 자막**을 메인 창 상단에서 전환할 수 있습니다. 캡처 중 선택은 다음 캡처부터 적용됩니다. 빠른 자막은 초안을 일찍 표시하며 정확도가 낮아질 수 있습니다.
- 선택한 입력과 엔진에 필요한 권한만 **권한 설정 시작**에서 확인할 수 있습니다. 메인 창에서 PC 소리 대기와 실제 수신을 구분합니다.

## Compatibility and distribution

- Requires **macOS 26 or later**. Apple Translation's Quality First strategy is available on macOS 26.4 or later.
- DMG and ZIP packages are ad-hoc signed and unnotarized. See the [installation guide](https://github.com/himomohi/AirTranslate/blob/master/docs/GETTING-STARTED.md).

## Download

- [Repository](https://github.com/himomohi/AirTranslate)
- [AirTranslate 1.20.0 release](https://github.com/himomohi/AirTranslate/releases/tag/v1.20.0)
- [Latest stable DMG download](https://github.com/himomohi/AirTranslate/releases/latest/download/AirTranslate.dmg)
- [AirTranslate-1.20.0.zip](https://github.com/himomohi/AirTranslate/releases/download/v1.20.0/AirTranslate-1.20.0.zip)

Version **1.20.0 / build 1200**.
