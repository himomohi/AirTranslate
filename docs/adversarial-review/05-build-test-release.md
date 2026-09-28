# 적대적 리뷰 05 — 빌드 / 테스트 / 릴리스 인프라

> 대상: `Package.swift`, `Tests/`, `script/`, `Release/`, 리포 위생, 문서 일관성 (기준 커밋 `dd458cc`, v1.3.6)
> 리뷰일: 2026-07-06
> 참고: 이 리뷰의 빌드/테스트 실패는 실제 `swift build`/`swift test` 실행으로 직접 검증함.

## 최우선 순위 (Top Priorities)

| 순위 | ID | 요약 | 심각도 |
|---|---|---|---|
| 1 | A1 | 릴리스 빌드가 **dev용 Info.plist를 배포** (release 분기는 사문) — 한 단어 수정 | High |
| 2 | A2 | 공증(notarization) 없음, ad-hoc 서명 배포 → macOS 15+에서 Gatekeeper 차단 | High |
| 3 | A3 | CI 전무 — 테스트가 자동으로 실행된 적 없음 | High |
| 4 | B5 | 테스트가 실제 UserDefaults/파일시스템/프레임워크를 오염·의존 | High |
| 5 | B2/C1 | OpenAI 이벤트 파서 100% 미테스트 + 프로토콜 seam 부재로 코어 테스트 불가 | High |

---

## A. 릴리스 파이프라인

### A1. 릴리스 빌드가 "local/dev" Info.plist를 배포 — release plist 분기 전체가 사문 — High
- 위치: `Release/build_open_source_release.sh:72` — `write_info_plist.sh "$INFO_PLIST" local` 호출
- 결함: `script/write_info_plist.sh:52-70`의 release 분기(LSApplicationCategoryType, CFBundleSupportedPlatforms, NSHighResolutionCapable, NSHumanReadableCopyright, `NSAudioCaptureUsageDescription`)가 **한 번도 실행되지 않음**. `dist/AirTranslate.app/Contents/Info.plist`에서 검증됨(카테고리·저작권 없음).
- 실패 시나리오: 모든 공개 DMG/ZIP(1.3.6 포함)이 앱 카테고리/저작권 없이, 오디오 캡처 사용 설명 키가 어긋난 채 배포. macOS가 ScreenCaptureKit 오디오 TCC 프롬프트에 `NSAudioCaptureUsageDescription`을 요구하면 잘못된 키라 설명이 안 뜸.
- 수정: 72행을 `release`로 변경(한 단어), 두 오디오 usage 키를 하나의 올바른 키로 통일, 릴리스 체크리스트에 `plutil -extract LSApplicationCategoryType ...` 검증 추가.

### A2. 공증/스테이플링 단계 전무 — ad-hoc 서명 배포 — High
- 위치: `Release/build_open_source_release.sh:57` (`SIGNING_IDENTITY="${SIGNING_IDENTITY:--}"`)
- 결함: 유일한 배포 경로가 ad-hoc(`-`) 서명 + 비공증 DMG/ZIP. `notarytool submit`/`stapler` 단계가 어느 스크립트에도 없음.
- 실패 시나리오: 이 앱은 macOS 26+를 요구하는데, macOS 15+에선 다운로드한 ad-hoc 앱을 Gatekeeper가 완전 차단하며 **README(133-137행)가 안내하는 우클릭→열기 우회는 더 이상 존재하지 않음** — 사용자 다수가 "고장/멀웨어"로 결론.
- 수정: Developer ID 환경변수 게이트로 `xcrun notarytool submit --wait` + `xcrun stapler staple`을 릴리스 스크립트에 추가, 4개 언어 README의 첫 실행 안내를 macOS 15+ 의미론으로 갱신.

### A3. CI 전무 — High
- 위치: `.github/` (release-notes 라벨 설정 `release.yml`만 존재, `workflows/` 없음)
- 실패 시나리오: `swift test`는 수동 체크리스트 항목(`Release/README.md`)일 뿐 — 테스트/빌드 깨는 커밋이 게이트 없이 릴리스에 포함. A4를 보면 가설이 아님.
- 수정: `swift build` + `swift test`를 macOS 러너에서 도는 `.github/workflows/ci.yml` 추가, 릴리스 스크립트 dry-run 잡 포함.

### A4. `swift test`가 현 활성 툴체인에서 컴파일 실패 — Medium (직접 재현)
- 위치: `Tests/AirTranslateCoreTests/FloatingCaptionTextFormatterTests.swift:1` 등, 툴체인 `xcode-select -p` → `/Library/Developer/CommandLineTools`
- 결함: 테스트가 Swift Testing(`import Testing`)을 쓰는데 Command Line Tools엔 미포함 — `swift test` 실행 결과 `error: no such module 'Testing'` → `fatalError`로 종료 (이 리뷰에서 직접 재현). "swift test 통과 확인"이라는 릴리스 게이트가 이 환경에선 충족 불가능하며 1.3.6에서 스킵됐을 개연성.
- 수정: README/Release README에 풀 Xcode 요구(`sudo xcode-select -s /Applications/Xcode.app`) 문서화, 권위 게이트는 CI(A3)로.

### A5. 버전 범프에 최소 7개 파일 수동 편집, 일관성 검사 없음 — Medium
- 위치: `script/app_metadata.sh:5-6` vs `CHANGELOG.md:9`, `Release/VERSION-HISTORY.md:3`, `Release/GITHUB-RELEASE-1.3.6.md`, README 4종
- 현재는 일관됨(1.3.6/136, 칭찬할 부분) — 다만 강제 장치 전무.
- 수정: `script/check_release_consistency.sh`(app_metadata 버전을 각 파일에서 grep 단언) 작성, CI와 릴리스 스크립트 서두에서 실행.

### A6. README 다운로드 링크가 `releases/latest` URL 안에 버전 하드코딩 — Medium
- 위치: `README.md:127` (`releases/latest/download/AirTranslate-1.3.6.zip`) + 3개 번역판
- 실패 시나리오: 1.3.7 공개 순간 "latest"에 1.3.6 zip이 없어 **4개 README의 주 다운로드 링크가 일제히 404**.
- 수정: 진짜 무버전 `AirTranslate.zip`을 업로드하고 그걸 링크(스크립트의 `STABLE_ZIP_PATH`도 실제론 버전 포함 — `Release/build_open_source_release.sh:21` 수정).

### A7. 과거 GitHub 릴리스 노트 7개가 워킹트리에서 미커밋 삭제 상태 — Medium
- 위치: `git status`: ` D Release/GITHUB-RELEASE-1.2.1.md` … `1.3.5.md`
- 결함: 프로젝트 자체 정책("이전 릴리스 버전 삭제 금지", `Release/README.md`)과 모순되는 파괴적 삭제가 대기 중.
- 수정: `git restore Release/GITHUB-RELEASE-*.md`, 정리가 의도라면 같은 커밋에서 VERSION-HISTORY로 합병 + 정책 텍스트 갱신.

---

## B. 테스트 커버리지 (소스 14,816줄 vs 테스트 1,021줄)

### B1. TranslationSessionStore(3,813줄) 상태머신 테스트 0 — High
- 위치: `start()`/`stop()`(441-539행), 번역 파이프라인(3176행), 캡션/플로팅 태스크(2085/2475행), `persistSelectedSettings`(1546행~)
- 결함: 유일한 스토어 테스트(637줄)는 언어 후보 순서/퀵 전환/transcribe-only 패널/프리뷰 1건만. 미테스트: start/stop/pause 상태머신과 `captureStartTask`/`captureStopTask` 취소 순서, 에러 경로 해체(504-512행), 세션 시간 컷오프, stop 시 flush/save(524-534행), 토스트 수명, 에셋 자동 다운로드 후 시작, 설정 왕복, 델리게이트 유입 경로 5개 전부.
- 실패 시나리오: CHANGELOG 1.3.5가 손으로 잡았다고 시인한 바로 그 부류("start/stop 캡처 해체 직렬화")가 무음 회귀 — 빠른 stop→start가 캡처 태스크를 살려두거나 저장을 떨궈도 사용자가 전사를 잃기 전까진 아무것도 실패 안 함.
- 수정: 순수 상태 전이를 `AirTranslateCore`로 추출, 나머지 오케스트레이션은 주입된 fake 캡처/전사 프로토콜(C1)로 구동 후 시퀀스 테이블 테스트.

### B2. OpenAI WebSocket 이벤트 파싱이 private + 100% 미테스트 (Gemini 등가물은 internal + 테스트됨) — High
- 위치: `OpenAIRealtimeTranscriber.swift:230`(`private func handleEventText`) vs Gemini의 internal `handleEventText`
- 결함: ~20개 이벤트 타입 매트릭스, 80ms 델타 스로틀(293-320행), completed/delta 버퍼 리셋이 private라 테스트 도달 불가; 231-233행 `try?`가 디코드 불가 이벤트를 무음 폐기.
- 실패 시나리오: OpenAI가 이벤트 타입 개명(이미 이벤트당 4개 별칭을 방어적으로 나열할 만큼 변동 이력) → 전사 전부 무음 드롭, 앱은 영원히 "듣는 중" — 회귀를 특정할 테스트도 로그도 없음.
- 수정: Gemini처럼 internal화 + 미러 테스트 스위트(전 case + 미지 이벤트 + malformed JSON), 디코드 실패는 1회 로그.

### B3. 오디오 변환이 2개 파일에 중복 + 양쪽 다 미테스트 — Medium
- 위치: `OpenAIRealtimeTranscriber.swift:360-436` + Gemini의 거의 동일 사본
- 결함: float→Int16 클램프/스케일/리틀엔디언 변환, 파일마다 다른 청크 수학(80ms@24kHz vs 100ms@16kHz), 그리고 비트깊이/부호/엔디언/채널 수 **무확인**으로 raw 바이트를 붙이는 비float 폴백(415-417행)이 테스트 0.
- 실패 시나리오: 요청 포맷을 무시하는 어그리게이트/서드파티 마이크가 Int32/빅엔디언/2채널 전달 → raw 바이트가 "PCM16 모노"로 발송, API가 쓰레기 반환 — 변환에 테스트 하네스가 없어 이등분 불가.
- 수정: 공용 `PCM16Chunker`를 `AirTranslateCore`로(순수 함수), 클램핑/홀수 경계/미지원 포맷 거부를 단위 테스트, 사본 삭제.

### B4. 테스트 커버리지 0인 모듈 전수 목록 — Medium (합산 High)
- Services 14개 전부: SystemAudioCapture, MicrophoneAudioCapture, MicrophoneDeviceCatalog, OpenAIRealtimeAudioOutput, TranslatedSpeechOutput, SpeechCaptioner, LiveSpeechTranscriber, AppleTranslationService, OpenAITranslationService(35행의 HTTP 파싱은 지금도 순수해 즉시 테스트 가능), FoundationTranscriptPolisher, ModelAvailabilityChecker, 키 스토어 2종
- Views 9개 전부 (SettingsView 1,314줄, SidebarView 828줄, CaptionBoardView 749줄 포함)
- Support 5/6 (FloatingCaptionTextFormatter만 테스트됨)
- 테스트된 것(공로 인정): TranscriptTextProcessor(충실), 캡션 랩핑(CJK 포함), Gemini 이벤트 파싱, 언어 후보 우선순위.
- 우선 착수: `OpenAITranslationService` 응답 파싱과 `StartReadinessPolicy` 엣지가 저렴한 승리; `AppText`(900줄 4개 언어)는 **전 항목 4개 언어 보유 단언하는 패리티 테스트** 가치 있음.

### B5. 테스트가 실제 머신 상태를 오염·의존 — High
- 위치: `TranslationSessionStoreLanguageCandidateTests.swift:196, 208, 221, 237, …` (`TranslationSessionStore()` 무오버라이드 생성)
- 결함: 기본 init이 실제 `UserDefaults.standard` 복원(1450행), 실제 전사 디렉터리 로드, 실제 `ModelAvailabilityChecker`/Translation 프레임워크 호출; `session.sourceLanguage` 변조가 러너의 실제 defaults에 **되쓰기**(1541행).
- 실패 시나리오: 테스트 순서나 이전 실행의 영속 값이 이후 테스트 초기 상태를 바꿈 → "내 맥에선 통과"류 플레이키 + 실제 프레임워크 쿼리로 느리고 불안정.
- 수정: 주입 가능한 `UserDefaults(suiteName:)`, 모든 테스트에 `modelAvailabilityProvider: { _,_ in [:] }` + 임시 디렉터리 필수화, 실수로 "실세계 스토어"를 못 만들게 테스트 헬퍼 팩토리.

### B6. "Core" 분리가 이름뿐 + 테스트 타깃 이름 오류 — Medium
- 위치: `Package.swift:14, 26-32`; `Sources/AirTranslateCore/`엔 파일 1개(14,816줄 중 664줄)
- 결함: `AirTranslateCoreTests`가 실행 파일 타깃에 의존, 4개 중 3개가 `@testable import AirTranslate` — 즉 "설계상 테스트 불가" 가설은 거짓이고, 진짜 문제는 거의 모든 로직이 AppKit/SwiftUI와 함께 실행 파일에 있어 문자열 포매터 하나 테스트에 앱 전체+프레임워크 7개 링크가 강제되는 것.
- 실패 시나리오: 테스트 빌드 시간 팽창, 실행 파일의 초기화 부작용이 단위 테스트로 누출, SPM 실행 파일 테스트 특이점(심볼 가시성)이 툴체인 업데이트에 스위트를 깰 수 있음.
- 수정: 순수 로직을 점진적으로 Core로 이동(FloatingCaptionTextFormatter, StartReadinessPolicy, LanguageOption, 이벤트 파싱 페이로드, PCM 청커, AppText), 실행 파일은 얇은 AppKit 셸로.

---

## C. 테스트 가능성 차단 요인 (설계)

### C1. 모든 서비스 의존성이 스토어 안에 하드와이어된 구상 타입 — High
- 위치: `TranslationSessionStore.swift:260-269` (`= SystemAudioCapture()` 등), init(378-401행)은 클로저 3개만 주입
- 결함: 코드베이스의 protocol 선언은 델리게이트 5개가 전부 — 캡처/전사/번역/웹소켓/음성출력 seam 부재.
- 실패 시나리오: "시스템 오디오 시작 실패 → 상태 메시지 → 해체"를 실제 ScreenCaptureKit과 TCC 프롬프트 없이 단위 테스트하는 것이 불가능 — B1의 상태머신에 테스트가 없는 정확한 이유.
- 수정: `AudioCapturing`/`Transcribing`/`Translating`/`SpeechOutputting` 프로토콜 정의(콜백 절반은 델리게이트가 이미 정의), init에서 프로덕션 기본값과 함께 수용, 테스트엔 스크립트 fake.

### C2. 네트워크 싱글턴 + static Keychain 접근이 서비스에 박제 — Medium
- 위치: `URLSession.shared.webSocketTask`(OpenAI:83, Gemini:66), `URLSession.shared.data`(OpenAITranslationService:35), `OpenAIAPIKeyStore.readAPIKey()` static 호출(OpenAI:66)
- 실패 시나리오: 연결/재시도/에러 경로 테스트 불가; `start()`에 닿는 테스트는 실제 Keychain(CI에서 키체인 프롬프트!)과 실제 OpenAI 엔드포인트를 침.
- 수정: `URLSession`(또는 `WebSocketConnecting` 팩토리)과 `APIKeyProviding` 클로저 주입, static 스토어는 프로덕션 구현으로 유지.

### C3. 가변 공유 상태 주변의 동시성 안전 옵트아웃 — Medium
- 위치: 스토어 263-264행(`nonisolated(unsafe)` 캡셔너, 옛 인스턴스의 수신 루프가 델리게이트 배달 중일 수 있는 채 1265-1267행에서 재할당); `OpenAIRealtimeTranscriber:5`는 `@unchecked Sendable`인데 `realtimeTranscriptionText` 등이 수신 태스크와 `start()` 호출 맥락 양쪽에서 **무락** 변조
- 실패 시나리오: 델타 버스트 중 stop→start → 리셋과 append 교차 → 캡션 중복/왜곡, 최악은 String 데이터 레이스 크래시(TSan) — C1/C2 탓에 현재 테스트 불가.
- 수정: 전사 버퍼 변조를 `stateLock` 경유(또는 actor화), 재할당 전 옛 서비스의 `delegate` nil 처리.

### C4. 델리게이트 콜백마다 새 `LiveSpeechTranscriber` "프록시" 할당 — Low
- 위치: `OpenAIRealtimeTranscriber.swift:356-358` — 델타 스트리밍 중 초당 수십 개 일회용 객체 + `===` 비교 미래 로직은 영원히 불일치. 소스 무관 델리게이트 프로토콜이 정도(正道), 최소한 프록시 1개 캐시.

### C5. 마케팅 데모 픽스처가 프로덕션 바이너리에 컴파일 — Low
- 위치: 스토어 403-440행 (`AIRTRANSLATE_PRODUCT_HUNT_SCREENSHOTS=1` env 게이트)
- 실패 시나리오: 해당 env를 가진 사용자/런처가 실제 앱 상태에 가짜 캡션·전사 주입. `#if DEBUG` 또는 별도 데모 타깃으로.

---

## D. 스크립트 위생

### D1. 잘 된 것 (검증됨)
- 전 스크립트 `set -euo pipefail` + 일관된 변수 인용 + `BASH_SOURCE` 기반 `ROOT_DIR`(→ `rm -rf`가 `/`로 해석될 수 없음), plist 린트, 서명 검증.
- 하드코딩 서명 identity 없음(env 오버라이드), **시크릿 없음**(`sk-…`/`AIza…`/인라인 api_key grep 전체 무검출), 키는 Keychain(`AfterFirstUnlockThisDeviceOnly`) + `SecureField` 입력.

### D2. deprecated `codesign --deep` 사용 — Low
- 위치: `script/build_and_run.sh:49, 52`, `Release/build_open_source_release.sh:76-90` — macOS 13부터 deprecated, 중첩 서명 실수 은폐. 단일 번들 직접 서명으로.

### D3. 첫 매칭 서명 identity 비결정적 자동 선택 — Low
- 위치: `script/build_and_run.sh:38-46` — 인증서 갱신 후 identity가 바뀌면 TCC 재프롬프트(스크립트 자신의 경고가 피하려는 바로 그 것). 명시적 `CODE_SIGN_IDENTITY` + 선택된 identity 출력.

### D4. 빌드마다 무조건 `pkill -x "$APP_NAME"` — Low
- 위치: `script/build_and_run.sh:22` — 세션 중인 릴리스판 AirTranslate도 확인 없이 살해(미저장 라이브 전사 소실). `dist/` 경로 매칭(pgrep -f) 또는 프롬프트.

### D5. 미문서화 `BUILD_NUMBER_DEFAULT` 간접층 — Low
- 위치: `script/app_metadata.sh:6`. 삭제 또는 Release/README 오버라이드 목록에 문서화.

---

## E. 리포 위생

### E1. 잘 된 것: `dist/`(40MB급 1.3.6 산출물 포함)/`tmp/`/`.build/`/`Release/product/` 모두 gitignore + 미추적 확인(`git ls-files` 144개, 마케팅 미디어 외 바이너리 없음).

### E2. 미추적 작업 디렉터리가 status를 영구 오염 — Low
- 위치: `.agent-harness/`, `.product-design-audits/` (`??`)
- 실패 시나리오: 항상 더러운 status는 개발자가 status를 무시하게 훈련 — A7의 삭제나 유출 시크릿 파일이 그렇게 눈감고 커밋됨.
- 수정: 둘 다 `.gitignore`에 추가.

### E3. 로컬 전용 ignore + 내부 문서 공개 배포 — Low
- 위치: `.git/info/exclude:9-10`이 `AGENTS.md`/`프로젝트하네스.md`를 로컬만 숨김; 루트 `intro.html`/`design-qa.md`는 추적 중.
- 수정: exclude 규칙을 `.gitignore`로 이동; 내부 노트의 공개 리포 포함 여부를 의도적으로 결정(`git rm --cached`).

### E4. Gemini API 키 URL 쿼리 전송 — Medium
- 위치: `GeminiLiveTranslationService.swift:61` — OpenAI 키는 올바르게 `Authorization` 헤더(OpenAI:81). 상세는 리뷰 02의 A1 참조. `x-goog-api-key` 헤더로.

---

## F. 문서 일관성

### F1. 버전/주장 일관성 양호: CHANGELOG·VERSION-HISTORY·GITHUB-RELEASE-1.3.6·app_metadata·빌드된 plist 모두 1.3.6/136 일치; README 4종은 상호 충실 번역이며 기능 주장(Keychain 등급, SecureField, Gemini 모델 id `gemini-3.5-live-translate-preview` = `IntelligenceModel.swift:136`)이 코드와 부합.

### F2. 낡은 Gatekeeper 안내 — A2에서 다룸: README 133-137행의 "우클릭→열기"는 이 앱이 지원하는 macOS 버전에서 동작하지 않음 (4개 언어 전부 수정 필요).

### F3. `Package.swift:8` `.macOS(.v26)` + tools 6.2 — 정보성
- SpeechAnalyzer/Translation API상 불가피해 보이고 README 배지도 정직하나, 정확한 Xcode 요구 버전을 "Build From Source"에 명시할 것 (A4와 연결).

---

## 레버리지 기준 Top 5 액션

1. **A1** 릴리스 plist 모드 수정(한 단어) + **A2** 공증 추가.
2. **A3** CI 추가(`swift build`+`swift test`) — 즉시 A4와 B5의 플레이키를 표면화.
3. **B5** 테스트를 실제 UserDefaults/FS/프레임워크에서 격리.
4. **B2** `handleEventText` internal화 + Gemini 테스트 스위트 복제.
5. **C1** 스토어에 캡처/전사/번역 프로토콜 seam 도입 → 3,813줄 상태머신(B1)을 테스트 가능하게.
