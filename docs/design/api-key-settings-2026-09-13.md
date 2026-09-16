# API 키 설정 리디자인 — 2026-09-13

## 목표와 범위

Apple 기본 모드를 유지하면서 OpenAI, Gemini, Meta, Azure, Nari의 API 키
관리를 같은 화면·상호작용으로 통일한다. Nari STT 별도 작업의 19개 파일
패치를 먼저 통합한 뒤 UI를 적용한다. 키 저장 서비스, 공급자 선택, 실제
인증·오디오 계약은 리디자인에서 바꾸지 않는다. 공개 배포는 범위에 없다.

## Exa 조사와 채택 기준

3개 검색 관점으로 16개 결과를 요청하고, 핵심 3개 원문을 추가 확인했다.
연결된 Exa 도구는 query/numResults와 일반 Highlights를 제공하며
Dynamic Highlights 옵션은 노출하지 않는다. dynamic 적용을 주장하지 않는다.

| 레퍼런스 | 채택한 원칙 | AirTranslate 적용 |
| --- | --- | --- |
| [Raycast BYOK](https://manual.raycast.com/ai/bring-your-own-key) | 공급자별 키를 한 목록에서 관리하고 콘솔로 연결 | 서비스 행과 동일한 키 편집기, 발급 페이지 아이콘 |
| [Apple Disclosure controls](https://developer.apple.com/design/human-interface-guidelines/disclosure-controls) | 자주 필요한 조작을 먼저, 상세 정보는 필요할 때 표시 | 한 번에 한 공급자 편집부를 펼침. Azure 필수 주소는 편집부에 항상 표시 |
| [Apple Text fields](https://developer.apple.com/design/human-interface-guidelines/text-fields) | 민감한 입력은 보안 필드로, 필드 안 아이콘은 목적과 행동을 구분 | SecureField, 저장된 키를 다시 읽거나 미리 채우지 않음 |
| [Apple Buttons](https://developer.apple.com/design/human-interface-guidelines/buttons) | 아이콘 동작의 목적과 조작 영역이 명확해야 함 | 동일한 저장·삭제·정보·외부 페이지 아이콘 |
| [Primer Tooltip](https://primer.style/product/components/tooltip/guidelines/) | 짧은 아이콘 이름을 보조하고 필수 정보를 숨기지 않음 | help와 accessibilityLabel 병행. 긴 설명은 클릭 가능한 팝오버, 오류는 본문 |

Raycast의 Verify 단계나 키 사용 토글을 모방해 인증되지 않은 상태를
검증 완료처럼 표시하지 않는다. 이 작업은 기존 Keychain 저장 동작만 유지한다.

## 구현 계획과 수용 기준

1. 서비스마다 분리된 카드·저장 폼·긴 안내를 공통 목록과 공통 컴포넌트로 교체한다.
2. 이름과 짧은 상태는 계속 보이고, 저장·삭제·발급·정보는 아이콘으로 통일한다.
3. 현재 선택된 공급자가 있으면 해당 편집부로 바로 진입한다. 행을 펼치는 동작은
   처리 엔진을 변경하지 않는다. 기본 모드에는 키 입력 항목을 만들지 않는다.
4. 저장됨은 키의 존재만 의미한다. 키 필요·설정 필요는 짧은 글과 서로 다른 기호로
   구분한다. 색상만으로 상태를 전달하지 않는다.
5. 모든 키 입력은 비어 있는 보안 필드에서 시작한다. 공백 입력은 저장할 수 없고,
   Return으로 저장할 수 있다. 실패 시 입력을 유지하고 오류를 표시한다.
6. 삭제에는 공급자를 명시한 확인 절차를 유지한다. 취소하면 키는 그대로다.
7. 실행 중에는 키·Azure 주소 변경을 막고 이유를 화면에 표시한다.
8. 공급자 설명·모델·서비스 제한은 정보 팝오버에 둔다. 툴팁 없이도 키보드로
   정보 버튼과 편집부에 접근할 수 있다. 필수 Azure 주소와 오류는 툴팁에 숨기지 않는다.
9. 기존 명암 모드 토큰과 창 크기를 재사용하고 한국어·영어·일본어·중국어 간체
   문구를 함께 제공한다.

## 기능 연결

| 표면 | 소유 파일·심볼 | 상태·외부 의존성 | 검증 |
| --- | --- | --- | --- |
| 설정 → API 키 | `SettingsView` → `APIKeySettingsView` | 기존 session의 선택 엔진·키 존재 여부 | 최신 앱의 실제 다섯 행·선택 보존 |
| 키 입력·저장·삭제 | `ProviderCredentialRow` | 로컬 입력 draft, 기존 session save/remove → 공급자별 Keychain | 빈 입력, 키보드, 삭제 취소, 소스 검토 |
| 상태·툴팁·정보 | `CredentialsCopy`, `ProviderCredentialRow` | 저장됨과 인증 상태 구분, 네 언어 | AX 이름, 정보 팝오버, Escape, 명암 모드 |
| Azure 필수 주소 | `APIKeySettingsView.azureConfiguration` | 기존 `azureSpeechEndpoint`, HTTPS 검증 | 필드 표시·읽기·수명주기 잠금 |

## 검증 결과

| 검사 | 결과 |
| --- | --- |
| `swift test --no-parallel` | 314 tests / 36 suites PASS, exit 0, 21.952초 |
| `swift build -c release` | PASS, exit 0, 36.69초 |
| `BUILD_CONFIGURATION=release ./script/build_and_run.sh --verify` | 최종 포커스 보정 후 PASS, exit 0, 빌드 29.20초. 정확한 `dist/AirTranslate.app` 실행 파일 경로 확인 |
| `./script/verify_packaging_permissions.sh` | PASS, exit 0 |
| 비밀 패턴·민감 파일 검사 | 패턴 일치 0, 민감 확장자 후보 0. 값은 출력하지 않음 |
| Nari 패치 통합 | UI·구조 맵 2개를 제외한 17개 파일은 전달 manifest와 SHA-256 일치 |
| 실제 UI / AX | 다섯 공급자·공통 입력·상태, Azure 필수 주소, 정보 팝오버, 키보드·삭제 취소·기본 모드 유지 확인 |

로그는 `/tmp/airtranslate-credentials-tests.log`,
`/tmp/airtranslate-credentials-launch-final.log`,
`/tmp/airtranslate-credentials-packaging.log`에 있다.

실제 화면은 `/Users/appcaster/Dev/AirTranslate/dist/AirTranslate.app`를 지정해
Computer Use로 확인했다. 설치된 `/Applications/AirTranslate.app`의 초기 화면과
최신 코드의 화면을 구분했다. 900px 폭의 다크 모드에서 일반 키 편집과 Azure
주소 편집의 레이아웃을 확인했다. 라이트 모드는 기존 동적 토큰 재사용까지
검토했으며 별도 실제 화면·대비 측정은 하지 않았다. 화면은 도구 안에서 확인했고
별도 PNG 파일로 저장하지 않았다.

UI에서 수행한 동작:

- 공백만 입력하고 Return을 눌러도 저장 동작과 저장 상태가 바뀌지 않았다.
- OpenAI 삭제 확인창의 공급자 이름을 확인하고 취소했다. 키 3개 저장 상태가 유지됐다.
- 정보 팝오버를 키보드 Escape로 닫고 Tab으로 다음 공급자에 접근했다.
- Tab → Space로 Gemini를 펼친 뒤 Gemini 보안 입력란에 포커스가 놓이는 것을 재확인했다.
- Gemini에 무해한 임시 문구를 입력하고 OpenAI로 전환했을 때 OpenAI 입력은 비어 있었다.
  Gemini로 돌아오면 임시 입력이 유지됐다. 테스트 문구는 저장하지 않고 지웠다.
- Azure 편집 시 필수 주소와 누락 안내가 본문에 나타났다. 주소 값은 바꾸지 않았다.
- Nari도 동일한 편집기·정보 팝오버·발급 링크를 사용한다.
- API 키 화면을 나와 일반 설정의 처리 방식이 Apple인 것을 확인했다.

최초 UI에서 키보드로 행을 펼칠 때 포커스가 첫 행으로 돌아갔다. 입력 필드가
마운트된 뒤 `.task`에서 포커스를 받도록 수정해 재확인했다. 전체 테스트 후의
변경은 이 UI 포커스와 `사용 중`을 `선택됨`으로 명확히 한 문구뿐이며 최종
release 빌드와 실제 UI로 검증했다. 수정 후 전체 테스트를 불필요하게 반복하지 않았다.

기존 사용자 키를 읽어 표시·교체·삭제하지 않았다. 실제 키 저장·실서비스 인증과
Nari 실음성 정확도·지연은 이번 UI 검증에 포함하지 않았다. 키 저장 서비스는 기존
구현을 그대로 호출한다. 커밋·push·태그·공개 배포는 수행하지 않았다.
