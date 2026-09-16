# Nari STT 구현 검증 — 2026-09-13

## 범위와 결과

Nari Qwen3-ASR을 선택형 실시간 전사 엔진으로 추가했다. 기존 Apple 기본값과
다른 제공자의 선택·자막·파일 저장 계약을 유지한다. Nari 최초 선택은 원문
전사이며, 사용자가 번역을 선택하면 기존 Apple Translation 흐름을 사용한다.
TTS, 계정 생성, 공용 키, 중계 서버, API 키 화면 리디자인은 이번 범위에 없다.

- 작업 브랜치: `codex/nari-stt`
- 기준 HEAD: `6f40bd9a4ee7fe504c556809e0f7d9d1330aa7dc`
- 코드·문서 변경은 미커밋 상태다. 커밋·push·태그·배포를 실행하지 않았다.
- 기존 `docs/release/1.8.0-verification-report.md`는 수정하지 않았다.
- 기존 `하네스성숙도기록.md` 내용은 보존하고 이번 실행 기록만 끝에 추가한다.

## 구현

| 경로 | 구현·검증 대상 |
| --- | --- |
| `NariRealtimeTranscriber` | 고정 WSS 주소, Bearer 인증, 설정 완료 후 16 kHz PCM16 mono 전송, 100 ms 청크, 유한 대기열, 정제된 오류 |
| `NariTranscriptLedger` | item/revision별 가설 전체 교체, `previous_item_id` 순서, 빈 최종 결과, 중복·늦은 결과 억제 |
| `TranslationSessionStore` | 시작 준비, 수명주기 세대, PC/마이크 입력, pause drain·resume 새 연결, 앱/시스템 중지 drain, 선택형 번역·파일 저장 |
| `NariAPIKeyStore` | 별도 Keychain 항목, ThisDeviceOnly, attributes-only 존재 확인, 키 값 진단 출력 금지 |
| 설정·콘솔·자막 화면 | Free/Partner 네 모델, Nari 자동 감지, 원문/번역 선택, 키 누락 복구, 입력에 맞는 권한 안내 |

공식 계약과 사용법은 [Nari STT 안내](../nari-stt.md)에 정리했다.

## 독립 검토에서 수정한 항목

1. 뒤 발화의 partial이 앞 발화의 final보다 먼저 도착하면 표시 순서가 뒤집힐 수
   있었다. ledger가 뒤 partial의 최신 revision을 보류하고 앞 발화 완료 후 전달한다.
2. 중지 시 마지막 원문은 받았어도 번역 task가 취소되어 저장에서 빠질 수 있었다.
   서비스 drain 후 대기 중인 번역을 최대 15초 기다리고 저장한다.
3. macOS 오디오 공유 메뉴에서 중지하면 마지막 Nari drain을 우회할 수 있었다.
   활성 Nari 세대의 외부 중지도 동일한 종료 경로로 연결했다.

통신·설정·독립 검토를 `nari_transport`, `nari_settings`, `nari_review`로 분담했다.
세 작업은 메인 모델·추론 설정을 상속했고 별도 override를 지정하지 않았다.
실제 serving model·effort 메타데이터는 도구에 노출되지 않았다. 검토 후 열린
P1/P2는 없었으며, 코디네이터가 통합·전체 테스트·release 실행·UI를 확인했다.

## 실행 근거

| 검사 | 결과와 경계 |
| --- | --- |
| `swift test --no-parallel` | 314 tests / 36 suites PASS, exit 0, 실행 21.870초 |
| Nari 서비스 테스트 | 가짜 연결을 주입한 17개 프로토콜·순서·종료·오디오 형식 회귀 포함 |
| Nari 세션 테스트 | 10개 기본값·설정 복원·키 누락·저장·번역 drain·외부 중지 회귀 포함 |
| `./script/verify_packaging_permissions.sh` | PASS, exit 0 |
| `BUILD_CONFIGURATION=release ./script/build_and_run.sh --verify` | 최종 안내 문구 보정 후 PASS, exit 0, release build 30.44초; 스크립트가 실행 파일 경로를 검사 |
| 소스 보안 검토 | redirect 거부, ephemeral URLSession, cookie/credential cache 비사용, 오류 allowlist, Keychain 확인 |
| `git diff --check`·비밀 패턴 검사 | 최종 적용용 파일 목록을 대상으로 수행; 사용자 기존 변경 제외 |

전체 테스트 이후 변경은 두 뷰의 안내 문구·표시 조건뿐이다. 해당 변경은 최종
release 빌드와 화면 read-back으로 확인했으며 전체 테스트를 다시 실행하지 않았다.

로컬 실행 로그:

- `/tmp/airtranslate-nari-all-tests-final.log`
- `/tmp/airtranslate-nari-packaging.log`
- `/tmp/airtranslate-nari-release-final.log`

## UI 확인과 남은 실서비스 검증

실제 앱에서 Nari 선택, 최초 원문 모드, 네 모델 메뉴, 자동 감지, 키 설정 이동,
키 누락 시 시작 차단과 API 키 설정 열기, PC/마이크별 안내, 번역 출력 전환 시
Nari 선택 유지, 재실행 후 선택 복원을 확인했다. 일반 설정 화면 한 장은 도구
안에서 시각 확인했고 나머지는 AX 상태로 확인했다. 별도 PNG 파일은 저장하지 않았다.

초기에는 키 누락 UI를 확인했다. 후속 재실행에서는 키 저장 표시가 관찰되었으나,
이 작업은 키를 입력·읽어 출력·교체·삭제하지 않았다. 키 존재 표시는 인증 성공의
근거가 아니다. 실제 Nari WebSocket 인증·오디오 전사·정확도·발화부터 화면까지의
지연·실서비스 pause/resume은 미검증이다. 공급자 서비스의 광고 지연을 앱 실측으로
보고하지 않는다.

UI 검증에서 바꾼 설정은 사전 허용 목록 19개와 비교하여 복원했다. API 키는
변경하지 않았다. 동일 Bundle ID의 설치 앱을 사용하는 원본 작업이 병행되므로,
원본에서 diff를 통합하고 API 키 UI를 리디자인한 뒤에는 그 산출물의 경로와 화면을
다시 확인해야 한다. 이 보고서는 원본의 후속 UI 변경이나 공개 배포를 검증하지 않는다.
