# AirTranslate 1.18.0

AirTranslate **1.18.0 / build 1180** adds **optional local Hy-MT2 1.8B translation**, upgrades the workspace to the **Focus Stage single-feed UI** with lower-latency live updates, and introduces **adaptive floating-caption glass backdrops with a hover mini-HUD**, a **categorized Engine & Voice Hub**, a **Control Center–style Menu Bar panel**, **Saved Transcripts search & Markdown/TXT export**, and an **interactive Terminology Chip Editor**. Apple Mode remains the default local-first workflow.

## Added

- **Optional local Hy-MT2 1.8B translation:** select **Hy-MT2** in the Engine & Voice Hub and download the verified Q4_K_M weights (1.13 GB) in **Settings > General** to translate Apple Speech captions on your Mac with no API key or external server. Supports download progress/cancellation, model removal, a local translation test check, optional terminology hints, and recent caption context.
- **Adaptive floating captions & hover mini-HUD:** choose `Frosted Glass` (default), `Cinema Dark`, or `Transparent` backdrops so captions stay legible over bright slides and videos, and hover over the floating window for instant pause/resume, copy latest caption, mode cycling, `A-`/`A+` sizing, backdrop toggle, and close controls.
- **Categorized Engine & Voice Hub:** the engine popover now filters by `All`, `On-Device`, or `Cloud` across clearly separated on-device, cloud realtime translation, and cloud transcription + local translation groups.
- **Searchable Transcript Library & Terminology Chip Editor:** search and filter saved transcripts and export them as Markdown (`.md`) or plain text (`.txt`), and manage Apple Translation / Hy-MT2 terms with interactive chips or direct list editing.

## Changed

- **Focus Stage single-feed main window & lower UI latency:** moved language selection/swapping into the top stage header, kept the bottom glass console bar uncollapsed at the 900pt default window width, replaced repeated `Original`/`Translation` turn labels with clean timestamped turn cards, and isolated audio-level meter updates (`SessionAudioWaveform`) so live audio metering does not re-evaluate the console bar.
- **Control Center–style Menu Bar panel & streamlined Settings:** reorganized the Menu Bar popover into a 2×2 tile grid with direct `PC Audio` / `Microphone` switching, added an API key count badge in Settings, and tucked inactive Apple options and file-transcription tools into collapsible sections.

## Fixed

- **Hy-MT2 & Azure MAI Stop draining:** Hy-MT2 Stop closes recognition input and drains pending translations for up to 25 seconds without saving incomplete fragments, while clearing stale silence status; stopping Azure MAI from the macOS capture menu now waits for final transcriptions and retains finalized translations without provisional drafts.
- **EmbeddingGemma file transcription polish:** re-checks installed models after live capture ends if Settings was opened during capture, and surfaces audio recovery guidance instead of prompting to re-download models when an audio file is missing or unreadable.

## 한국어 요약

AirTranslate **1.18.0 / build 1180**은 **로컬 Hy-MT2 1.8B 번역(1.13 GB Q4_K_M)** 추가와 함께, **단일 피드 Focus Stage 메인 창**, **다크 글래스 플로팅 자막 및 호버 미니 HUD**, **카테고리형 엔진 허브**, **2×2 메뉴바 컨트롤 센터**, **기록 검색·필터 및 Markdown/TXT 내보내기**, **용어집 칩 에디터**를 포함합니다. 또한 오디오 레벨 웨이브폼 뷰 격리로 UI 재계산 지연을 줄였고, Hy-MT2 및 Azure MAI 중지 드레인·EmbeddingGemma 복구 안내를 개선했습니다.

## Compatibility and distribution

- Minimum system: **macOS 26+** (`Apple Silicon` and `macOS 27+` are required only for optional EmbeddingGemma file transcription).
- DMG and ZIP artifacts are **ad-hoc signed and not Apple-notarized**. macOS may show an unidentified-developer warning on first launch; follow the [installation guide](https://github.com/himomohi/AirTranslate/blob/master/docs/GETTING-STARTED.md) and verify the `.sha256` checksum before installing.

## Download

- [Repository](https://github.com/himomohi/AirTranslate)
- [AirTranslate 1.18.0 release](https://github.com/himomohi/AirTranslate/releases/tag/v1.18.0)
- [Latest stable DMG download](https://github.com/himomohi/AirTranslate/releases/latest/download/AirTranslate.dmg)
- [AirTranslate-1.18.0.zip](https://github.com/himomohi/AirTranslate/releases/download/v1.18.0/AirTranslate-1.18.0.zip)

Version: **1.18.0 / build 1180**. Released **2026-11-22**.
