# AirTranslate structure

This document maps the repository's runtime areas so contributors can find the
right files before changing the app.

## Swift Package Targets

- `Sources/AirTranslate`
  - The macOS SwiftUI executable target.
  - Owns the menu bar app, settings, live caption board, floating caption
    window, audio capture services, translation services, and transcript
    persistence.
- `Sources/AirTranslateCore`
  - Shared transcript text processing logic used by the app and tests.
- `Tests/AirTranslateCoreTests`
  - Swift Testing coverage for transcript processing and language-candidate
    behavior.

## Main App Surfaces

- `Sources/AirTranslate/App/AirTranslateApp.swift`
  - App entry point and scene setup.
- `Sources/AirTranslate/Views/ContentView.swift`
  - Main app shell.
- `Sources/AirTranslate/Views/SidebarView.swift`
  - Session controls, model/language choices, and inline settings.
- `Sources/AirTranslate/Views/CaptionBoardView.swift`
  - Live transcript workspace and caption rows.
- `Sources/AirTranslate/Views/FloatingCaptionWindowView.swift`
  - Always-on-top floating caption overlay with bounded text blocks, live width/height measurement, and resize-aware appearance.
- `Sources/AirTranslate/Views/FloatingCaptionResizeHandle.swift`
  - Hover affordances and pointer/keyboard/accessibility resizing for the floating caption panel.
- `Sources/AirTranslate/Views/TranscriptLibraryView.swift`
  - Saved transcript browser and editor.
- `Sources/AirTranslate/Views/SettingsView.swift`
  - Settings navigation, provider mode selection, and floating-caption settings.
- `Sources/AirTranslate/Views/APIKeySettingsView.swift`
  - Unified OpenAI, Gemini, Meta, Azure, and Nari credential list. Expanding a
    provider does not select it as the active engine; Apple mode has no key row.
- `Sources/AirTranslate/Views/ProviderCredentialRow.swift`
  - Shared secure input, icon actions, removal confirmation, and details popover.
    Uses existing session Keychain operations without reading stored key values.
- `Sources/AirTranslate/Views/CredentialsCopy.swift`
  - Localized credential status, tooltips, and accessibility labels.

## Session And Services

- `Sources/AirTranslate/Services/TranslationSessionStore.swift`
  - Main observable session state.
  - Coordinates audio capture, transcription, translation, caption lines,
    floating caption presentation, saving, and speech output.
- `Sources/AirTranslate/Services/SystemAudioCapture.swift`
  - ScreenCaptureKit-based system-audio capture.
- `Sources/AirTranslate/Services/MicrophoneAudioCapture.swift`
  - Microphone input capture.
- `Sources/AirTranslate/Services/LiveSpeechTranscriber.swift`
  - Apple Speech transcription.
- `Sources/AirTranslate/Services/OpenAIRealtimeTranscriber.swift`
  - Optional OpenAI realtime transcription.
- `Sources/AirTranslate/Services/AppleTranslationService.swift`
  - Apple Translation integration.
- `Sources/AirTranslate/Services/OpenAITranslationService.swift`
  - Optional OpenAI translation path.
- `Sources/AirTranslate/Services/TranslatedSpeechOutput.swift`
  - Spoken translated output.

## Floating Captions

- `Sources/AirTranslate/Support/FloatingCaptionWindowController.swift`
  - Floating caption panel lifecycle, persisted frame restore/reset, and screen-bounded resize clamps.
- `Sources/AirTranslate/Support/FloatingCaptionTextFormatter.swift`
  - Tail selection and line formatting for floating captions.
- `Sources/AirTranslate/Models/FloatingCaptionDisplayMode.swift`
  - Original, original plus translation, or translation-only display choices.
- `Sources/AirTranslate/Models/FloatingCaptionLineCount.swift`
  - User-selectable floating caption line count.
- `Sources/AirTranslate/Models/FloatingCaptionTextSize.swift`
  - User-selectable floating caption text size and line-height estimates.
- `Sources/AirTranslate/Models/FloatingCaptionAppearance.swift`
  - Custom caption color, background opacity, point-size clamp, and block-height sizing helpers.

## Release And Site

- `Release`
  - Release notes, release assets, and release packaging scripts.
- `docs`
  - Static guide site served by GitHub Pages.
- `script`
  - Local build metadata and helper scripts.

## Local-Only Notes

Contributor-local planning notes can live in `devlog/`. That directory is
ignored so private investigation notes do not appear in pull requests.

## Apple 인식·번역·자막 검증 맵

| 기능 | 진입점 | 핵심 파일·심볼 | 데이터·외부 의존성 | 검증 |
| --- | --- | --- | --- | --- |
| Apple 음성 구간 식별 | Apple 기본 → PC 소리/마이크 → 시작 | `LiveSpeechTranscriber`, `AppleSpeechRecognitionMetadataBuilder` | `SpeechTranscriber.Result`의 `CMTimeRange`·최종 여부·구간별 개정 번호 | `swift test --filter AppleRecognitionTranslationPolicyTests` |
| 부분 결과 번역과 최종 확정 | `TranslationSessionStore.appendCaption` → `requestTranslationForAppleRecognition` | `AppleRecognitionTranslationPolicy`, `AppleTranslationRequestIdentity` | 부분 결과 300ms 간격, 짧은 부분 결과(12자 이하 Latin 단일 단어 포함) 700ms 무음 대기, 최종 결과 즉시 요청 | `swift test --filter AppleRecognitionTranslationPolicyTests` |
| 짧은 발화·반복 문장·전체 저장 | 인식 콜백 → 자막 라인 → 정지/저장 | `TranslationSessionStore`, `AppleSpeechRecognitionMetadata` | 오디오 구간 기준 동일 발화 수정과 다음 발화 구별; 확정 구간 이전 재전송 차단 | `swift test --filter AppleSpeechMetadataPipelineTests` |
| Stage 원문·번역 안정화 | `CaptionBoardView`의 자막 표시 | `CaptionDisplayUpdatePolicy` | 첫 표시·뒤에 이어지는 글자는 즉시, 전체 교체는 최초 예약 시각 기준 최대 280ms 대기, 확정·정지 시 최신값 반영 | `swift test --filter CaptionDisplayUpdatePolicyTests` |
| 긴 자막 병합·종료 시 보존 | 인식 대기열 → 화면 대기열 → 일시정지/정지/종료 | `TranslationSessionStore.flushPendingRecognizedCaption`, `flushPendingCaptionPresentation` | 최신 텍스트 병합, DEBUG 전용 수동 flush 검증 경로, 사용자 저장소와 분리한 테스트 저장소 | `swift test --filter LongSessionCaptionPresentationTests` |
| 선택형 기록 파일 저장 | 설정 → 기록 → 기록 파일 저장 | `SettingsView`, `TranslationSessionStore.isTranscriptPersistenceEnabled`, `checkpointPendingTranscriptSave`, `flushPendingTranscriptSave` | 기본 꺼짐; 켰을 때만 로컬 `.txt` 저장, 설정은 UserDefaults에 보존 | `swift test --filter TranscriptPersistenceTests` |
| 오래된 플로팅 번역 만료 | 새 원문 표시 → 이전 번역 유지 | `TranslationSessionStore.scheduleFloatingTranslationHoldExpiry` | 요청 시점의 ContinuousClock 만료 시각을 사용; 새 번역 수신 시 취소 | `swift test --filter FloatingTranslationPresentationTests` |
| 단계별 지연 측정 | `AIRTRANSLATE_LATENCY_TRACE=1`로 로컬 앱 실행 | `PipelineDiagnostics`, `script/summarize_latency_trace.py`, `script/build_and_run.sh` | 타임스탬프·문자 수·구간 ID만 출력; 전사·번역 본문·키는 기록하지 않음 | 동일 음성·설정·release 빌드의 trace 비교; [2026-09-08 검증 보고서](../docs/adversarial-review/08-apple-caption-pipeline-2026-09-08.md) |

플로팅 창의 읽기 대기 정책과 사용자 지정 외형 저장은 `TranslationSessionStore`에 유지한다.
번역만 표시하는 모드에서 원문만 도착했을 때는
`FloatingCaptionWindowView`가 번역 대기 상태를 표시한다.
플로팅 창은 사용자가 폭과 높이를 조절할 수 있으며, 사용자 지정 글자 크기·텍스트 색·배경색·배경 불투명도는 UserDefaults에 보존된다.
창 높이가 큰 글자와 6줄 dual 모드를 모두 담기 어려운 경우에는 최소 한 줄짜리 원문·번역 블록을 보존하고, 표시 줄 수를 현재 창 높이에 맞춰 줄인다.
Stage 복사 버튼은 포인터·키보드·접근성 포커스에서 표시되고,
복사할 텍스트가 없을 때 비활성화된다. 2026-09-08 실제 창에서 hover 없이
Shift-Tab 키보드 포커스가 보이는 것을 확인했다. 표시 정책 테스트,
키보드 포커스 확인과 VoiceOver 실제 낭독은 별도 근거로 구분한다.

## Optional Azure MAI Transcription

| 기능 | 진입점 | 핵심 파일·심볼 | 외부 의존성 | 검증 |
| --- | --- | --- | --- | --- |
| Azure MAI 추가 엔진 | 설정 → 일반 → Azure MAI | `TranslationSessionStore.useAzureMAIMode`, `SettingsView`, `ProcessingEngine` | 기존 Apple 번역 언어팩 | `swift test --filter AzureMAITranscriberTests` |
| Azure 리소스 설정 | 설정 → API 키 → Azure MAI | `AzureSpeechAPIKeyStore`, `azureSpeechEndpoint` | macOS Keychain; Azure Speech 리소스 | 엔드포인트 제한·모드 복원 테스트 |
| 5초 구간 전사 | 기존 PC 소리/마이크 캡처 | `AzureMAITranscriber`, `AudioSamplePipelineRegistry`, `receiveAzureMAI` | MAI-Transcribe-2 REST, API 2025-10-15 | WAV·multipart·응답 파싱·중지/일시정지 테스트 |

기존 기본 엔진은 바뀌지 않는다. Azure 키는 Keychain, 엔드포인트와 엔진
선택은 설정에 저장한다. 오디오는 메모리에서 16 kHz 모노 WAV로 변환하고
선택한 원문 언어를 지정해 Azure에 보낸다. 중지는 마지막 구간의 완료를
기다리며, 일시정지는 새 입력을 제외하고 이미 받은 구간을 처리한다.
최대 6개 구간만 대기시키고, 시간 초과·HTTP 오류·대기열 초과 시 실패를
표시하고 캡처를 중단한다. 오류로 처리하지 못한 오디오는 재전송하지 않는다.
Azure 리소스의 지원 지역·권한·과금 및 실제 음성 정확도는 별도 실서비스
검증 대상이다. 5초 경계에서 단어가 잘릴 수 있으며 실시간 부분 결과나
구간을 넘는 화자 추적은 제공하지 않는다.

공식 계약: https://learn.microsoft.com/en-us/azure/ai-services/speech-service/mai-transcribe

## Optional Nari STT

| 기능 | 진입점 | 핵심 파일·심볼 | 데이터·외부 의존성 | 검증 |
| --- | --- | --- | --- | --- |
| 추가 전사 엔진 | 설정/콘솔 → Nari STT | `ProcessingEngine`, `NariTranscriptionModel`, `TranslationSessionStore.useNariSTTMode` | 모델·자동감지 선택은 UserDefaults, 기존 Apple 기본값 유지 | `NariModelSettingsTests`, `NariSessionTests` |
| 키·시작 준비 | 설정 → API 키 | `NariAPIKeyStore`, `StartReadinessPolicy`, `SettingsView` | 별도 Keychain 항목, 키 누락 시 기존 자막 보존 | `APIKeyStorePresenceTests`, `NariSessionTests` |
| 실시간 오디오·발화 | PC 소리/마이크 → 시작 | `NariRealtimeTranscriber`, `AudioSamplePipelineRegistry`, `NariTranscriptLedger` | 16 kHz PCM16 mono → Nari WebSocket; item/revision별 전체 교체 | `NariRealtimeTranscriberTests` |
| 종료·재개·저장 | 중지/일시정지/재개 | `finishNariCapture`, `pauseNariCapture`, `resumeNariCapture`, `receiveNariTranscript` | 마지막 commit drain, 새 연결 세대, 기존 번역 FIFO와 선택형 파일 저장 | `NariSessionTests`, `NariRealtimeTranscriberTests` |

사용 방법·제한·공식 계약은 [Nari STT 안내](../docs/nari-stt.md)에 있다.

## Apple 번역 언어팩 다운로드

| 기능 | 진입점 | 핵심 파일·심볼 | 데이터·외부 의존성 | 검증 |
| --- | --- | --- | --- | --- |
| 언어팩 다운로드·재시도 | 설정 → Assets → 번역 언어팩, 자산 누락 상태의 시작 | `TranslationSessionStore.beginModelAssetDownload`, `ModelAvailabilityChecker.downloadAssets` | 시작 시점 언어쌍·설정과 요청 ID, 다운로드 뒤 실제 `LanguageAvailability` 재확인 | `swift test --filter TranslationAssetDownloadTests` |
| 시스템 다운로드 승인 | `TranslationAssetDownloader.download` → 요청 전용 창 | `TranslationAssetDownloadWindowController`, `TranslationAssetDownloadView.translationTask` | SwiftUI가 제공한 `TranslationSession.prepareTranslation`; `installedSource` 세션은 다운로드용으로 사용하지 않음 | 실제 미설치 언어쌍 승인·취소·같은 쌍 재시도·완료 상태 확인 필요 |
| 취소·오래된 완료 차단 | 언어·시작 설정 변경, 중지, 앱 종료, 다운로드 창 닫기 | `cancelModelAssetDownload`, `TranslationAssetDownloader.cancel` | 요청당 새 창/세션, 승인 action 안에서만 세션 사용, 이전 요청의 늦은 성공·오류 무시 | `TranslationAssetDownloadTests`, `PipelineLifecycleTests` |

설정/메인 창 또는 메뉴 막대 팝오버가 닫혀도 승인 UI를 호스팅할 수 있도록
요청 동안만 전용 SwiftUI 창을 유지한다. `prepareTranslation`이 이미 진행 중인
다운로드 때문에 일찍 반환해도 `LanguageAvailability`가 설치 완료를 확인할 때까지
500ms 간격의 취소 가능한 상태 확인을 유지한다. 음성인식팩은 기존 Speech
`AssetInventory` 설치 경로를 사용한다. 테스트의 주입된 다운로드/창 경계는
수명과 상태 전이를 검증하며, 실제 macOS 언어팩 설치 성공의 증거는 아니다.
