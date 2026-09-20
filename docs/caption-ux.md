# 자막 모드 UI와 설정 개선

## 최종 요구사항

사용자 확인에 따라 플로팅 영역은 **자막 글자만 표시**한다. 배경 상자·테두리·도구막대·상태·안내 문구·리사이즈 표시가 나타나면 안 된다. GUI 검증은 **Codex Computer Use**로 수행하며 외부 cua-driver로 전환하지 않는다. 이 두 원칙은 사용자의 기억 요청에 따라 메모리 갱신 노트에도 저장했다.

메인이 설계·구현·통합·최종 검증을 담당했다. 별도 작업 두 개는 UX·공식 레퍼런스와 코드 경로·회귀 위험을 읽기 전용으로 검토했다. 기존 OpenAI·제공자 관련 변경을 보존하며, 새 릴리즈·버전 변경·GitHub 게시는 이번 범위에 포함하지 않는다.

## 수용 기준과 옵션

- 원문/번역/두 언어 선택에 맞는 실제 자막만 투명하게 표시한다. 자막이 없을 때는 안내 문구도 렌더링하지 않고 마우스 입력을 아래 화면으로 통과시킨다.
- 창 테두리·배경·그림자·도구막대·리사이즈 표시는 hover 중에도 나타나지 않는다. 글자 자체의 그림자/윤곽선은 가독성 옵션으로 유지한다.
- 설정·메인 화면·메뉴바에서 자막을 조절한다. `⌘⇧C`는 표시/숨기기를 전환한다. 가로 폭은 설정 슬라이더에서 바꾸고, 자막 글자를 끌어 위치를 옮길 수 있다.
- 기본·영화·강의·고대비·밝은 화면용의 5개 글자 스타일을 제공한다. 프리셋은 엔진·언어·번역/전사 모드·안정성·항상 위 선호를 바꾸지 않는다.
- 글꼴 4종, 굵기 4단계, 줄 간격 3단계, 글자 효과 3종, 18–72pt 크기, 글자 색상, 정렬, 언어별 최대 줄 수, 번역 우선 배치를 제공한다.
- 기존 외형 설정은 복원한다. 예전 배경 색상·불투명도·모서리 값이 저장되어 있어도 오버레이에는 배경을 그리지 않는다. 프리셋 선택은 해당 과거 값을 덮지 않는다. 명시적 스타일 초기화는 기존 초기화 계약을 유지한다.
- 설정 미리보기는 실제 pt를 사용한다. 밝은/어두운 예시 화면은 설정 안의 배경이며 실제 오버레이 배경이 아니다. 샘플 자막 미리보기는 캡처·번역 요청·기록 저장을 시작하지 않는다.
- 큰 글자와 좁은 폭에서 CoreText로 글꼴 폭을 측정해 최신 내용을 보존한다. 두 언어의 블록 경계와 줄 수에 따른 높이를 유지해 갱신 중 읽는 위치가 흔들리지 않게 한다.

## 개선 전후

| 영역 | 이전 구현 | 최종 변경 | 확인 방법 |
| --- | --- | --- | --- |
| 플로팅 표시 | 배경 상자·도구막대·상태·리사이즈 표시 | 자막 글자만 표시, 빈 자막은 완전 투명 | 5개 프리셋의 빈 화면 픽셀 검사, 샘플 외곽 투명 검사 |
| 조작 위치 | 플로팅 영역 안 버튼 | 설정·메인·메뉴바, 표시 전환 단축키 | 실제 앱에서 단축키 켜기/끄기 확인, 설정 세부 조작은 도구 장애로 미검증 |
| 스타일 | 크기·색상 위주 | 5개 프리셋, 글꼴·굵기·행간·효과·번역 순서 | 설정 복원·프리셋 적용 범위 회귀 |
| 미리보기 | 축소된 샘플 | 실제 pt, 장면 선택, 내용 기반 높이와 스크롤 | SwiftUI 컴포넌트 렌더링, 실제 설정 화면 조작과 구분 |
| 줄바꿈 | 추정 문자 폭 | 실제 글꼴 측정과 최신 줄 보존 | 4개 글꼴×3개 크기×5개 문자 예제 |

## 참고한 스킬과 공식 자료

Build iOS Apps의 SwiftUI UI Patterns와 macOS Settings 가이드, SwiftUI Expert의 layout/accessibility/latest APIs 가이드를 읽었다. 기존 macOS Settings scene과 @Observable 세션을 유지하고 자막 설정을 별도 뷰로 분리했다.

Exa 커넥터에서 아래 자료를 검색하고 원문을 확인했다. 커넥터에 Dynamic Highlights 매개변수가 없어 해당 옵션을 적용했다고 주장하지 않는다.

| 출처 | 적용 |
| --- | --- |
| [Apple Live Captions 설정](https://support.apple.com/guide/mac-help/change-live-captions-settings-accessibility-mchla0b36db8/mac) | 글꼴·크기·색상의 독립 조절 |
| [Apple Live Captions 사용](https://support.apple.com/guide/mac-help/get-captions-of-spoken-and-computer-audio-mchldd11f4fd/26/mac/26) | 자막 위치·크기 조절과 복원. 창 안 버튼은 사용자 요청에 따라 적용하지 않음 |
| [Apple 자막 스타일](https://support.apple.com/guide/mac-help/change-captions-settings-for-accessibility-mh43180/mac) | 프리셋과 사용자 지정 구분 |
| [Apple VoiceOver 평가](https://developer.apple.com/help/app-store-connect/manage-app-accessibility/voiceover-evaluation-criteria) | 설정 컨트롤 라벨·값·탐색 흐름 |
| [Apple 대비 평가](https://developer.apple.com/help/app-store-connect/manage-app-accessibility/sufficient-contrast-accessibility-evaluation-criteria/) | 글자 윤곽선과 밝은/어두운 장면 검토 |

## 분담

| 담당 | 모델·추론 | 결과 |
| --- | --- | --- |
| 메인 | 사용자 선택 유지 | 설계·구현·통합·테스트·앱 검증 |
| 자막 UX와 레퍼런스 검토 | 앱 기본값, 실제 backend 값 미확인 | Apple 원문·탐색·접근성 검토 전달 |
| 자막 설정과 회귀 위험 검토 | 앱 기본값, 실제 backend 값 미확인 | 사용자 크기 override·미리보기 축소·폰트 폭·표시 정책 검토 전달 |

두 별도 작업의 결과를 통합했다. 실제 ID의 제목 재설정 API는 `no rollout found`로 실패해 재설정 성공으로 세지 않았다. 내부 서브에이전트와 예약 자동화는 생성하지 않았다.

## 검증

- 수정 전 구현은 전체 388개 테스트와 릴리즈 빌드가 통과했다. 이는 아래 자막 전용 수정 전 결과다.
- 자막 전용 수정의 집중 검사: `swift test --no-parallel --filter 'FloatingCaption|FloatingPresentationPolicyTests|FloatingTranslationPresentationTests'`, 52개 / 8개 스위트, 12.942초 PASS.
- 신규 `FloatingCaptionOverlayRenderingTests`: 다섯 프리셋에서 빈 자막의 보이는 픽셀 0개, 샘플 글자 렌더링과 네 외곽 투명 PASS. 별도 창을 띄우지 않는 NSHostingView 검사이며 실제 앱 UI 조작과 구분한다.
- 초기 수정에서 기존 배경 초기화 계약 두 조건이 실패했다. 배경을 렌더링하지 않는 요구와 설정 초기화 계약을 분리해 기존 초기화 동작을 보존했고 집중 검사에서 재확인했다.
- 최종 전체 검사: `swift test --no-parallel`, 390개 / 43개 스위트, 25.463초 PASS. 로그: `/tmp/airtranslate-caption-only-all-tests.log`.
- 최종 릴리즈 빌드·앱 실행: `BUILD_CONFIGURATION=release ./script/build_and_run.sh --verify`, 빌드 40.81초, 종료 코드 0. 새 `dist/AirTranslate.app` 실행 경로 확인. 로그: `/tmp/airtranslate-caption-only-launch.log`.
- Codex Computer Use: 최신 앱에서 `⌘⇧C`로 플로팅 표시 끔→켬→끔과 일반 설정 열기를 확인했다. 캡처·녹음을 시작하지 않았다.
- 최신 설정 컴포넌트의 5개 프리셋·실제 크기 미리보기·읽기 옵션·배치 영역을 창 없이 렌더링해 확인했다. 스타일 모음은 초기 표시 Task와 애니메이션의 중간 프레임을 피하도록 프레임 갱신을 반영한 뒤 출력·검토했다. 출력용 fixture에서 읽기 전용 `accessibilityReduceMotion` 값을 주입하려던 컴파일 오류는 제거했으며 제품 코드는 바꾸지 않았다. 최종 출력 검사 PASS, 임시 출력용 테스트 제거, 생성 이미지는 저장소 밖에 보관했다.
- 임시 출력용 테스트 제거 후 영구 투명 렌더링 회귀 2개를 다시 실행해 1.290초 PASS. `git diff --check` PASS, 비밀값 패턴 일치 파일 0개, 무시 파일을 포함한 민감 확장자 파일 0개.

Codex Computer Use는 최신 빌드에서도 자막 설정 선택과 스크린샷 요청에서 `Sky Computer Use native pipe closed before response`로 종료됐다. 앞선 도우미 진단은 `SkyComputerUseService`의 배열 제거 assertion/SIGTRAP이었고, 최신 시도 후에도 AirTranslate 앱 프로세스는 실행 중이다. 외부 도구 사용 승인 대기는 사용자의 Codex Computer Use 지정으로 종료했으며, 외부 도구로 전환하지 않는다. 설정 안 프리셋·옵션의 실제 클릭, 포인터 hover, VoiceOver 낭독은 미검증이다.

투명 자막의 실제 대비는 아래 영상·문서에 따라 달라진다. 이전 불투명 배경의 대비 수치를 최종 구현의 보장값으로 사용하지 않는다. 실제 음성·유료 API·VoiceOver 낭독·공개 배포는 별도 검증 범위다.

## 파일과 기록

핵심 파일은 `FloatingCaptionStyle.swift`, `FloatingCaptionSettingsView.swift`, `CaptionStyleCopy.swift`, `FloatingCaptionWindowView.swift`, `FloatingCaptionWindowController.swift`, `FloatingWindowConfigurator.swift`, `TranslationSessionStore.swift`, `FloatingCaptionTextFormatter.swift`다. 회귀는 `FloatingCaptionStyleTests.swift`와 `FloatingCaptionOverlayRenderingTests.swift`에 있다. README 네 언어·기능 맵도 자막 전용 동작에 맞췄다.

Dev-doc의 자막 하단 앵커 기록을 읽는 위치 유지에 활용했다. 작업·도구 장애 교훈을 최종 자막 전용 요구와 검증 경계에 맞게 갱신했다. 앞선 보관함 전체 검사는 기존 다른 프로젝트 두 기록의 비밀정보 형태·UID 불일치로 실패했다. 무관한 기록은 수정하거나 내용을 출력하지 않았다. Obsidian CLI 응답이 없어 그래프 검증도 미실행이다. 사용자 후속 요청의 변경·검증은 하네스 성숙도 기록 54회차에 남겼다.
