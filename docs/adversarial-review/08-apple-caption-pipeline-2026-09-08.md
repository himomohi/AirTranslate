# Apple 기본 인식·번역·자막 개선 검증

검증일: 2026-09-08 KST. 기준 소스는 `2e03096` 이후 작업 트리이며,
시작 전에 존재하던 Azure MAI 변경을 보존했다. 이 문서는 현재 소스의
로컬 개선 보고서다. 1.7.1 공개 산출물에 이번 변경이 포함됐다는 뜻은 아니다.

현재 상태: 소스·테스트·보안 검토, 최신 release 빌드·앱 실행,
동일 음성 1회 전후 비교와 약 222초의 7회 반복 캡처를 확인했다.
마이크 실측은 macOS 권한 창에 대한 도구 접근 제한으로 미완료다.
최종 앱은 실행 중이며 PC 소리 입력·캡처 중지 상태다. 공개 배포는 수행하지 않았다.

## 목표와 수용 기준

사용자 요청은 전체 제작물을 점검하고, 특히 Apple 기본 모드의 지연과
자막의 읽기 어려운 중간 교체를 주도적으로 개선하는 것이다.

| 수용 기준 | 검증 근거 | 현재 판정 |
| --- | --- | --- |
| 짧은 최종 발화와 다른 시간에 반복된 같은 문장을 보존한다 | 오디오 구간 메타데이터·저장 회귀 테스트, 동일 음성 실제 캡처 전후 비교 | PASS: 7회 재생에서 `Yes. No.` 7회와 완성된 반복 문장 14회 보존 |
| Apple이 최종 결과에 앞 단어를 보충해도 원문에 반영한다 | `appleFinalCanReplaceVolatilePartialWithPrependedWords`, 구간 시작 시각 이동 테스트 | PASS |
| 늦게 도착한 인식·번역이 확정된 다른 구간을 덮지 않는다 | 확정 오디오 경계·구간·개정 번호 검증 테스트 | PASS |
| 첫 자막과 이어지는 글자는 즉시 표시하고 전체 교체의 빈도를 제한한다 | `CaptionDisplayUpdatePolicyTests`, Stage·플로팅 실제 화면 | 정책 테스트 PASS; 단기·지속 캡처의 플로팅 마지막 완성 문장 확인; 화면 교체 횟수 전후 정량 비교는 없음 |
| 새 메타데이터 builder와 번역 요청 정책의 보조 상태 크기를 제한한다 | 메타데이터 2,000개 최종 구간·정책 32개 구간의 상태 상한 테스트, 50,000자 MainActor 응답성 테스트, 약 222초 실제 캡처 | 테스트 PASS; 후속 6회 RSS 표본 56.1–62.9MiB, 수십 분 이상 연속 실행은 미검증 |
| 저장·일시정지·정지·종료에서 최신 내용을 보존한다 | `AppleSpeechMetadataPipelineTests`, `LongSessionCaptionPresentationTests`, 실제 일시정지·재개·정지 및 저장 결과 | PASS: 원문·번역 각 42개 문단; 앱 종료 flush는 테스트 근거 |
| 키·음성 전송 안내와 접근 가능한 조작을 유지한다 | 보안 검토, 다국어 안내·Keychain 속성, 실제 키보드 복사 포커스와 Azure 빈 설정 화면 | PASS: hover 없이 Shift-Tab 포커스 표시, 빈 endpoint/key 안내·버튼 비활성·폭 확인; VoiceOver 낭독은 미검증 |

## 기준선에서 확인한 문제와 수정

| 영역 | 이전 | 변경 | 근거 | 담당 |
| --- | --- | --- | --- | --- |
| Apple 결과 구별 | 결과 문자열만으로 보정과 다음 발화를 구별하면 같은 문장이 반복될 때 유실될 수 있음 | `CMTimeRange`, 구간 ID, 개정 번호, 최종 여부를 인식부터 저장·번역까지 전달 | 메타데이터·파이프라인 회귀 테스트 | `airtranslate-macos-implementer`, 코디네이터 |
| 최종 결과 보존 | 기준선 실제 캡처 2회에서 `Yes. No.`와 두 번째 반복 문장의 끝이 누락됨 | 최종 결과의 앞 단어 보충을 반영하고, 다른 오디오 구간의 동일 문장을 별도 발화로 보존 | 동일 음성 기준선, 최종·반복·저장 테스트 | `airtranslate-macos-implementer`, 코디네이터 |
| 번역 요청·반영 | 초기 `I` 같은 조각 번역이 바뀌고 중간 실측에서도 `Please`가 잠시 `제발`로 번역됨 | 의미 있는 부분 결과는 300ms 간격으로 요청; 12자 이하 Latin 단일 단어를 포함한 짧은 부분 결과는 최대 700ms 보류, 의미 있는 후속 결과·최종 결과는 조건 충족 시 즉시 요청 | `AppleRecognitionTranslationPolicyTests`, 최종 동일 음성 실측 | `airtranslate-macos-implementer`, 코디네이터 |
| Stage 가독성 | 원문·번역 전체 교체가 잦고 여러 애니메이션 청크가 갱신됨 | 첫 표시·뒤에 붙는 글자는 즉시, 전체 교체는 최초 예약 시점에서 최대 280ms 내 최신값 반영; 단일 청크 페이드 | `CaptionDisplayUpdatePolicyTests`, `CaptionBoardView` | 자막 구현 에이전트, 코디네이터 |
| 플로팅 상태·복사 | 번역만 모드의 대기 상태와 복사 버튼 발견성이 부족함 | 원문만 있을 때 번역 대기 표시; 포인터·키보드·접근성 포커스에서 복사 버튼 표시 | `FloatingCaptionWindowView`, `CaptionBoardView` | 자막·접근성 에이전트 |
| 긴 세션 회귀 검증 | 100회 병렬 갱신과 실제 타이머가 섞여 기준선에서 revision 기대값이 2/3으로 흔들림 | DEBUG 전용 수동 수신·flush로 두 병합 단계를 직접 검증; 실제 응답성 검사는 별도 유지 | `LongSessionCaptionPresentationTests` | 코디네이터 |
| 테스트 저장소 | 기존 GPT 테스트가 실제 설정·저장 폴더를 사용할 수 있음 | 임시 UserDefaults suite·전사 폴더로 격리하고 실행 후 정리; GPT 테스트 32개 통과 후 실제 폴더 신규 파일 0개 확인 | `GPTLiveTranscriptionModeTests` | 코디네이터 |
| 로컬 계측·실행 | 단계별 숫자 비교가 없고 동일 이름의 설치본과 개발본이 혼동될 수 있음 | 선택적 숫자 계측·요약 스크립트, 빌드 구성 선택, 정확한 앱 번들의 일반 실행·실행 파일 확인 | `PipelineDiagnostics`, `script/build_and_run.sh` | 코디네이터 |
| 개인정보·키 | 진행 중인 Azure 변경의 전송 안내와 갱신 시 Keychain 속성을 보완할 필요가 있음 | 네 README·개인정보 안내에 Azure 직접 전송 명시, Keychain 갱신에도 기기 한정 접근 속성 적용 | 보안 에이전트의 소스·비밀 검토 | `airtranslate-security-auditor` |

짧은 부분 결과에 적용하는 대기 시간은 잘못된 조각 번역의 잦은 교체를 줄이기
위한 정책이다. 모든 번역이 빨라졌다는 근거로 사용하지 않는다. 실제 지연의
전후 차이는 아래처럼 같은 입력을 사용한 계측으로 별도 판단한다.

## 측정 조건과 단계별 지연

- 실제 Apple 기본, PC 소리, 영어 → 한국어, 음성 출력 끔, 플로팅 번역만 표시.
- macOS 27.0 (`26A5425a`), Xcode beta의 Swift 6.4, release 구성.
- `say -v Samantha -r 155`로 생성한 동일 음성 파일 약 19.34초.
- 입력에는 일반 문장, 요일 수정 문장, `Yes. No.`, 같은 항공편 예약 문장 2회를 포함한다.
- 로컬 보관 근거의 논리 이름(저장소에 포함하지 않음): `local-verification/baseline/trace.jsonl`, `metrics.json`, `summary.json`.
- 최종 단일 재생 데이터: `local-verification/after-final/summary.json`.

| 지표 | 기준선 p50 / p95 / 최대 | 최종 p50 / p95 / 최대 | 해석 |
| --- | ---: | ---: | --- |
| 인식 결과 → Store 전달 | 2.677 / 6.273 / 7.809ms | 0.959 / 13.386 / 19.231ms | 중앙값은 감소, p95·최대는 증가 |
| 번역 실행 | 67.181 / 99.160 / 206.862ms | 47.360 / 62.722 / 236.210ms | p95는 36.7% 감소했지만 최대는 증가 |
| 오디오 캡처 콜백 지연 | 40.447 / 68.462 / 75.111ms | 37.975 / 65.690 / 71.203ms | 이번 단일 재생 표본에서 소폭 감소 |
| 첫 원문 → 첫 번역 | 125.271ms | 262.804ms | 불완전한 초기 단어를 보류해 137.533ms 증가 |

기준선 첫 캡처에는 인식 결과 87개, 최종 결과 6개, 번역 요청 21개,
번역 반영 47개, 플로팅 번역 갱신 15개가 기록됐다. 같은 음성을 재생한
두 번째 기준선에서도 짧은 발화·반복 문장 유실이 재현됐다.
최종 단일 재생은 인식 결과 87개, 최종 결과 6개, 번역 요청 42개,
번역 반영 80개, 플로팅 번역 갱신 16개다. 누락된 구간의 보존과 최종
번역 처리가 추가돼 요청 수가 21개에서 42개로 달라졌다. 따라서 번역
p95 차이를 동일 요청 1건의 순수 가속률이나 전체 체감 속도 개선율로
해석하지 않는다. 입력은 같지만 실시간 OS·UI 부하를 완전히 통제하지 않았다.

이 지표는 발화 시작부터 화면 렌더링 완료까지의 지연이 아니다. 특히
첫 원문 → 첫 번역은 최초의 짧은 임시 원문을 기준으로 하므로 번역의 의미와
안정성을 함께 확인해야 한다. 초기 단어 보류로 첫 번역까지의 간격은
늘어났으며, 최종 결과와 의미 있는 후속 원문은 700ms를 일괄 기다리지 않는다.
기준선에 Stage 교체 계측이 없고 최종 측정은 플로팅 단독이므로,
Stage 교체 빈도의 전후 감소율은 산출하지 않는다. 기준선의
`board_rewrites: 0`은 교체가 없었다는 증거가 아니며, 최종 요약의
해당 값은 측정 없음(`null`)이다.

기준선 유휴 상태 5초 표본은 MainActor 4,250/4,250개가 대기 상태였고,
footprint 53.8MB(peak 60MB)였다. 이 결과로 실행 중 부하나 장기 누수를
판정하지 않는다.

## 반복 캡처·저장·화면 확인

`local-verification/sustained/`의 `summary.json`,
`resource-samples.json`, `original.txt`, `translation.txt`를 대조했다.
로그 구간은 221.951초이며 일시정지·재개를 포함해 같은 음성을 총 7회
재생했다. 최종 결과 42개, 저장 원문·번역 각 42개 문단을 확인했다.
`Yes. No.`는 7회, `I want to book a flight from Seoul to Tokyo`는
14회 모두 보존됐다. 단일·반복 캡처의 마지막 플로팅 자막에서도
서울에서 도쿄까지의 완성 문장을 Computer Use로 확인했다.

후속 6회 재생 직후 표본은 RSS 56.1–62.9MiB, CPU 4.7–12.6%였다.
지속 로그의 인식 결과 전달 p95는 31.340ms, 최대 47.985ms였다.
같은 음성을 반복해 번역 캐시가 작동하므로 번역 실행 중앙값 2.016ms를
일반 음성의 장시간 번역 속도로 제시하지 않는다. 약 222초의 반복 검증은
수십 분·수 시간 실행이나 다양한 화자·언어의 안정성을 증명하지 않는다.

키보드 검증은 마우스를 올리지 않은 복사 버튼에 Shift-Tab으로 이동했을 때
파란 포커스 표시가 보이는 것을 확인했다. Azure 설정은 endpoint/key가
비어 있을 때의 안내, 버튼 비활성 상태, 창 폭 안의 배치를 확인했다.
구성된 Azure 계정 연결 및 일본어·중국어 UI는 실행하지 않았다.
자동 감지는 기존의 `개선 중` 비활성 상태를 유지한다.

## 검증 명령과 게이트

| 검사 | 명령·근거 | 결과 |
| --- | --- | --- |
| 전체 테스트 | `swift test`; `local-verification/full-tests.log` | 278개, 32개 suite, 8.433초 PASS |
| focused 회귀 | `swift test --filter AppleRecognitionTranslationPolicyTests`, `AppleSpeechMetadataPipelineTests`, `CaptionDisplayUpdatePolicyTests`, `LongSessionCaptionPresentationTests` | 전체 테스트에 포함되어 PASS |
| 후속 GPT fixture 격리 | `swift test --filter GPTLiveTranscriptionModeTests` | 32개 PASS; 실제 사용자 전사 폴더 신규 파일 0개 |
| release 빌드·정확한 앱 실행 | `BUILD_CONFIGURATION=release AIRTRANSLATE_LATENCY_TRACE=1 ./script/build_and_run.sh --verify`; `local-verification/release-build.log` | 빌드 34.06초 exit 0, bundle verify PASS; 실행 PID 79425 확인 |
| 실제 Apple 자막·저장·일시정지·재개 | Computer Use와 동일 음성 1회·7회 재생 | PASS: 짧은 발화·반복 문장과 원문/번역 저장 보존 |
| 마이크 입력 | Computer Use로 마이크 선택·시작 후 상태 확인 | `마이크 캡처 시작 중...`까지 확인; 시스템 권한 창 접근 제한으로 실음성 미완료; 캡처 중지·PC 소리 복원 확인 |
| 보안·정적 검사 | 소스·문서 비밀 패턴, 비밀 파일, 숫자 계측, 키 저장·음성 전송 안내, `bash -n`, `git diff --check` | PASS; 비밀 패턴 일치 파일 0개, 비밀 파일 0개 |
| 공개 일관성 | 현재 작업 트리와 기존 1.7.1 릴리즈 자산 | 이번 작업은 미출시; 공개 준비 완료로 판정하지 않음 |

전체 테스트 기준선은 255개/29개 suite였고, 긴 전사 병합 테스트 1개가
타이머 순서에 따라 실패했으며 단독 재실행에서는 통과했다. 이를 기대값만
완화하는 대신 두 병합 단계의 결정적 검증으로 바꿨다.
최종 전체 테스트와 앱 빌드 뒤에는 GPT 테스트 파일의 저장소 격리만
추가했으며 앱 소스는 변경하지 않았다. 변경 범위에 맞춰 GPT 테스트
32개를 다시 검증했다. 실제 저장 폴더에서 본문이 테스트 fixture와
정확히 일치하는 20개 파일만 대조한 뒤
`local-verification/test-transcript-backup`으로 백업 이동했다.

## 변경 파일과 검증 경계

핵심 변경은 `LiveSpeechTranscriber.swift`, `TranslationSessionStore.swift`,
새 `AppleSpeechRecognitionMetadata.swift`, `AppleRecognitionTranslationPolicy.swift`,
`CaptionDisplayUpdatePolicy.swift`, `PipelineDiagnostics.swift`와 대응 테스트다.
화면은 `CaptionBoardView.swift`, `FloatingCaptionWindowView.swift`,
설정의 Azure 상태 안내·조작 부분을 보완했다. 빌드·계측 스크립트와
네 README·`Release/PRIVACY-NOTICE.md`도 작업에 포함된다.
시작 전에 있던 Azure 구현·설정 변경 전체를 이번 개선의 신규 산출물로
계산하지 않는다.

마이크 선택 후 시작하면 `마이크 캡처 시작 중...`이 표시됐다.
`UserNotificationCenter` 프로세스가 실행 중임을 확인했지만 Computer Use의
`com.apple.UserNotificationCenter` 접근이 안전 제한으로 차단됐다.
따라서 실제 권한 창의 내용이나 승인·거절 상태를 확인하지 못했으며,
마이크 실음성 정확도·지연은 미검증이다. 이후 캡처 메뉴에서 중지하고
PC 소리 입력으로 복원해 캡처가 꺼진 상태를 확인했다.

API 키를 이용한 외부 제공자 실서비스 호출, VoiceOver 실제 낭독,
일본어·중국어 UI, 수십 분 이상 연속 실행과 OS 음성 서비스의 메모리 추이,
공개 산출물의 서명·공증·배포는 미검증이다. 기존 1.7.1 DMG/ZIP은 현재 수정 소스의
검증 산출물이 아니다. 이번 요청에는 버전 변경·커밋·푸시·게시가 포함되지 않았다.

## 검증 기록 관리

공개 보고서에는 수치와 재현 절차를 기록하며, 원문 로그와 음성 파일은
로컬 검증 자료로 별도 보관한다. 아래 `local-verification` 이름은 공개 다운로드
경로가 아니라 해당 검증 자료를 구분하는 논리 이름이다.

실제 음성 재생 검증이 만든 알려진 샘플 기록 10개도 본문과 경로를 확인한 뒤
`local-verification/runtime-transcript-backup`으로 별도 보관했다.
검증 보고서의 원문·번역·계측 근거는 임시 검증 폴더에 유지한다.

역할별 위임은 Apple 구현·접근성에 커스텀 `gpt-5.5/high`, 보안 검토에
`gpt-5.5/xhigh`를 사용했다. Spark의 실행 설정 오류가 발생한 검증·보고
작업은 메인 모델·추론 설정을 상속한 대체 에이전트와 코디네이터가 수행했다.
최종 통합·실제 화면·음성 재생·바이너리 일치 확인은 코디네이터가 담당했다.
