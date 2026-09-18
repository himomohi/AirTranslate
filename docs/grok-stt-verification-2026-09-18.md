# Grok STT 구현·검증 기록

검증일: 2026-09-18 KST. 기존 버전 1.9.2/build192의 소스에 선택형 기능을 추가했으며 공개 릴리즈·태그·업로드는 수행하지 않았다.

## 결과와 범위

- SpaceXAI (xAI) API 키 행과 Grok STT 엔진을 추가했다. 모델 ID는 `grok-voice-transcribe-2.0`으로 고정했다.
- 첫 선택은 원문 전사, 음성 언어 자동 인식이며 기존 Apple 기본값과 다른 제공자의 키를 보존한다.
- PC 소리/마이크 → PCM16 스트림 → 부분/확정 원문 자막 → 선택형 파일 저장을 연결했다. 번역은 선택 시 기존 Apple Translation 경로를 사용한다.
- 중지·일시정지·재개, 늦은 응답 차단, 누락된 키, 전송 대기열 한도, 종료 응답 중복을 검증했다.
- 실제 사용자 키를 입력·읽기·삭제하거나 xAI에 유료 전사 요청을 보내지 않았다. 실제 계정 인증·음성 인식 품질·레이턴시는 미검증이다.

## 검증

| 검사 | 결과 | 근거 |
| --- | --- | --- |
| Grok 전용 | PASS | `swift test --filter Grok`: 최종 25 tests / 2 suites |
| 전체 회귀 | PASS, 실행 방식 구분 | `swift test --no-parallel`: 최종 366 tests / 39 suites, 22.935초 |
| 전체 기본 실행 | 조건부 | 초기 365개 PASS. UI 보완 후 366개 실행에서 기존 `runningSessionCheckpointsTranscriptWithoutStopping`의 1.5초 조건이 1회 실패. 동일 테스트 단독 실행 0.348초 PASS, 전체 직렬 실행 PASS. 대기 시간을 늘리거나 기존 테스트를 수정하지 않음 |
| Release 빌드·앱 실행 | PASS | `BUILD_CONFIGURATION=release ./script/build_and_run.sh --verify` |
| 실제 UI | PASS | 제공자 5→6개, SpaceXAI 보안 입력란, Grok 2.0 모델, 전사만 기본값, 키 누락 차단·API 키 화면 이동. 최종 새 빌드에서 Grok 키 오류 → Apple 전환 → 오류 해제·준비됨을 재확인 |
| 보안 | PASS | 전용 Keychain, 키 존재 확인 시 원문 읽기/인증 UI 없음, 고정 WSS와 Authorization 헤더, ephemeral session·redirect 차단, 서버 오류 원문 폐기. 변경 코드·문서의 비밀 패턴 미검출 |
| 문서 | PASS | 4개 README·사용 안내·개인정보·기능 맵·Unreleased 기록, 로컬 링크 및 `git diff --check` |

## 리뷰와 보완

1. `transcript.done`의 세션 전체 전사문을 다시 추가하지 않도록 확정 발화별로 소비한다. 일본어 무공백 연결과 공백·줄바꿈 연결을 회귀 테스트로 보호했다.
2. 저장 파일에서 임시 자막과 번역 상태 안내를 제외하고 확정 번역만 보존한다.
3. 감지 언어 정보가 없는 자동 인식 결과에 수동 선택 언어를 감지 결과로 기록하지 않는다.
4. 실제 UI에서 Grok 키 누락 안내가 Apple 모드로 전환한 뒤에도 남는 것을 발견했다. Grok을 끌 때 해당 설정 오류만 해제하고 다른 오류는 보존하도록 수정해 회귀 테스트를 추가했다.
5. 종료 번역 대기 시간 초과를 조용한 성공으로 처리하지 않도록 오류로 반환한다.

## 작업 분리

| 대상 작업명 | 실제 모델 | 추론 설정 | 결과 | 검증 |
| --- | --- | --- | --- | --- |
| [하위 작업 \| 메인: Grok Voice Transcribe 2.0 SpaceXAl 도 지원 할수 잇도록 API 옵션에 추가해줘 음성 전사야 스레드를 분리 해서 작업해] Grok STT 구현 | 앱 기본값, 실제 모델 ID 미노출 | 기본값, 실제 값 미노출 | 코드·테스트 12파일 전달, 메인 통합 | 전달 해시 12개 일치, 최종 메인 검증 위 참조 |

- 구현 스레드: `01a0b482-5196-7823-bc53-dbdccda4d905`; 메인: `01a0b480-961a-7f90-89b8-028ee0d53442`.
- 분리 스레드는 결과를 보낸 후 보관되었다. 사용자 승인이 도착하지 않아 15분 자동화는 등록하지 않았다.
- 분리 환경의 초기 테스트는 모듈 캐시 쓰기 제한과 CoreAudio 초기화 예외로 실패했다. 별도 전송 테스트 11개 통과 후 최종 테스트 실행을 메인에 넘겼다.
- 메인이 분리 작업 공간에서 테스트하는 동안 스레드 보관과 함께 해당 빌드 데이터베이스가 사라져 빌드가 실패했다. 이미 검증한 패치를 메인에 통합한 상태였으므로 메인 작업 공간에서 전용·전체 테스트를 완료했다. 이후에는 모든 검증을 통합 공간에서 끝낸 뒤 작업 공간 보관을 허용한다.

## 변경 파일

- 모델·키·전송·문구: `GrokTranscriptionModel.swift`, `GrokAPIKeyStore.swift`, `GrokRealtimeTranscriber.swift`, `GrokCopy.swift`.
- 연결: `StartReadiness.swift`, `TranslationSessionStore.swift`, `APIKeySettingsView.swift`, `CaptionBoardView.swift`, `SettingsView.swift`, `SidebarView.swift`.
- 회귀: `GrokRealtimeTranscriberTests.swift`, `GrokSessionTests.swift`.
- 문서: `README.md`, `README.ko.md`, `README.ja.md`, `README.zh-CN.md`, `CHANGELOG.md`, `Release/PRIVACY-NOTICE.md`, `docs/GETTING-STARTED.md`, `docs/grok-stt.md`, `structure/README.md`, 이 검증 기록, `하네스성숙도기록.md`.
- 기존 미추적 `docs/release/1.8.0-verification-report.md`는 수정하지 않았다. 커밋·push·버전 변경은 수행하지 않았다.

공식 API 계약과 사용법: [Grok STT 안내](grok-stt.md).

최종 실제 앱 상태는 Apple 기본 모드, 영어 → 한국어, PC 소리, 번역, 음성 출력·플로팅 자막 꺼짐, 준비됨으로 복원했다. 새 로컬 앱은 `dist/AirTranslate.app`이며 버전은 변경하지 않았다. 화면의 접근성 라벨과 보안 입력란은 확인했으나 VoiceOver 낭독과 실제 xAI 음성 전사는 수행하지 않았다.
