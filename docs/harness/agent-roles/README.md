# Agent Role Requirements

이 폴더는 공통 프로젝트 하네스에서 사용하는 에이전트별 역할과 요구사항을
파일 단위로 분리한 문서 모음이다.

각 파일은 다음 기준을 따른다.

- 공통 역할명과 AirTranslate에서의 매핑명을 함께 적는다.
- 책임 범위, 입력, 산출물, 검증 기준, 금지사항을 명확히 적는다.
- 메인 코디네이터가 최종 판단과 통합 책임을 가진다.
- 공개 릴리즈, GitHub 업로드, credential, 데이터 삭제처럼 되돌리기 어려운
  작업은 사용자 승인 게이트를 통과해야 한다.

## Role Files

| Role | File |
| --- | --- |
| Main Coordinator | `main-coordinator.md` |
| Idea Planner | `idea-planner.md` |
| Code Mapper | `code-mapper.md` |
| Adversarial Reviewer | `adversarial-reviewer.md` |
| UI/UX Reviewer | `ui-ux-reviewer.md` |
| Implementer | `implementer.md` |
| Test Verifier | `test-verifier.md` |
| UI Regression Tester | `ui-regression-tester.md` |
| Accessibility Tester | `accessibility-tester.md` |
| Security Auditor | `security-auditor.md` |
| Release Operator | `release-operator.md` |
| Product Launcher | `product-launcher.md` |
| Performance Auditor | `performance-auditor.md` |
| Report Writer | `report-writer.md` |

## Shared Gates

- Define success criteria before implementation.
- Keep edits surgical and tied to the user's request.
- Verify the actual user-visible result, not only build success.
- Run the security gate before public upload or release actions.
- Present a fenced approval report before any GitHub push, tag, release, or
  asset upload.
- 반복 실행·실패 흡수 기록은 Git에서 제외한 로컬 기록에만 남긴다.
  공개 문서·GitHub 릴리즈 본문·첨부·게시용 문구에 포함하지 않는다.
