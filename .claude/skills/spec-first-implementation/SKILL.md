---
name: spec-first-implementation
description: Use when the user requests adding, modifying, or removing a feature on the Just Three app. Updates the relevant spec documents first so the change is precisely defined, then implements the code from the updated spec.
---

# spec-first-implementation

Just Three 앱의 기능 추가/수정/삭제 요청을 처리할 때 따르는 워크플로우.

## 핵심 원칙

요구사항이 들어오면 **스펙 문서를 먼저** 갱신해 변경 의도를 명확히 한 뒤, 그 스펙을 기준으로 코드를 작성/수정한다. **코드 먼저 → 문서 나중** 순서는 금지.

이유:

- 스펙 문서를 먼저 손보면 변경 범위와 엣지 케이스를 코드보다 빠른 단계에서 발견할 수 있다.
- 다음 세션의 Claude Code가 동일 화면을 다시 작업할 때, 스펙 문서만 보고 현재 의사결정을 그대로 이어갈 수 있다.
- 코드와 스펙이 어긋난 상태로 커밋되는 사고를 막는다.

## 절차

### 1. 요구사항 분석 & 스펙 위치 파악

먼저 어떤 화면/기능에 대한 요구사항인지 식별하고, 영향을 받는 스펙 문서를 모두 찾는다.

| 화면 | 1차 스펙 (UI 분석) | 2차 스펙 (구현 가이드) |
|------|------------------|---------------------|
| 로그인 | `.claude/ui/v1.0.0/01_로그인화면.md` | `.claude/agents/ui-implementor/01_login.md` |
| Todo | `.claude/ui/v1.0.0/02_todo화면.md` | `.claude/agents/ui-implementor/02_todo.md` |
| 캘린더 | `.claude/ui/v1.0.0/03_캘린더화면.md` | `.claude/agents/ui-implementor/03_calendar.md` |
| 마이페이지 | `.claude/ui/v1.0.0/04_마이페이지화면.md` | `.claude/agents/ui-implementor/04_mypage.md` |

전역 규칙은 다음 문서를 함께 확인한다:

- `.claude/rules/project-overview.md` — 디자인 시스템 / 색상 / 폰트 / 공통 규칙
- `.claude/rules/architecture.md` — MVVM 폴더 구조 / 상태관리 / 라우팅
- `.claude/rules/git-commit.md` — 커밋 메시지 규칙
- `CLAUDE.md` — 프로젝트 전반 가이드

### 2. 스펙 문서 우선 수정

찾은 스펙 문서들을 **요구사항이 반영된 모습으로 먼저 갱신**한다. 다음을 빠뜨리지 않는다:

- **결정사항 표** — 새 동작/제약을 행으로 명시 (예: "목표 삭제 | 오늘 + 미달성에서만 가능")
- **위젯/컴포넌트 표** — 새 위젯, 새 파라미터, 새 콜백
- **구현 단계** — 단계별 설명에 새 동작을 끼워 넣기
- **입력 제한 / 엣지 케이스** — 제약 조건이 추가되었다면 해당 절에 추가
- **와이어프레임과 다른 결정** — 와이어프레임에 없거나 다른 부분은 "와이어프레임에는 없으나 v1.0.0에서 추가/변경됨"을 명시

스펙 문서는 **다음 세션의 Claude Code가 읽고 동일하게 구현 가능한 수준**까지 구체적으로 쓴다. 모호한 표현(예: "적당히", "필요시")은 피하고 조건/상태/콜백 이름까지 명시한다.

### 3. 사용자에게 스펙 변경 확인 (선택)

요구사항이 모호하거나 트레이드오프가 있을 때만 사용자에게 한 번 더 확인한다. 명확한 요구사항이면 바로 4단계로 진행해도 된다.

### 4. 코드 작성 / 수정

이제 비로소 코드를 손댄다. **방금 갱신한 스펙 문서를 단일 진실 공급원**으로 삼는다.

- View / 위젯: `lib/features/<feature>/view/`, `lib/shared/widgets/`
- ViewModel: `lib/features/<feature>/viewmodel/` (도입 후)
- Repository: `lib/features/<feature>/repository/` (도입 후)

스펙에 적힌 콜백 이름, 파라미터 시그니처, 조건식을 그대로 코드에 옮긴다. 코드와 스펙이 어긋나면 **스펙이 우선**이며, 코드를 스펙에 맞추거나 (의도적인 차이라면) 스펙을 다시 갱신한다.

### 5. 검증

- `flutter analyze lib/features/<feature> lib/shared/widgets`로 lint/타입 에러 없는지 확인
- 가능하면 `flutter run`으로 실제 동작 점검
- 변경된 스펙 항목을 코드가 모두 충족하는지 본인이 한 번 더 대조

### 6. 커밋

`/commit` 슬래시 커맨드를 활용해 한글 커밋 메시지로 한 번에 커밋. 보통 한 커밋에 **스펙 + 코드 + 분석 통과**가 함께 들어가는 것이 정상이다 (스펙만 따로, 코드만 따로 커밋하지 않는다 — 두 변화가 의미상 한 단위이기 때문).

## 안티 패턴

- ❌ 코드부터 작성하고 나중에 스펙 문서를 동기화
- ❌ "스펙 문서는 나중에 정리하면 되니까 일단 코드만"
- ❌ 와이어프레임에 없는 추가 기능을 스펙에 명시하지 않고 코드에만 반영
- ❌ 결정사항 표를 건드리지 않고 본문에만 짧게 한 줄 추가하고 끝내기
- ❌ 코드의 콜백 이름과 스펙의 콜백 이름이 다른 상태로 커밋

## 빠른 체크리스트

작업 마무리 직전에 다음 5개를 자가 점검:

- [ ] 영향받는 스펙 문서를 모두 찾았는가? (`ui/v1.0.0/`, `agents/ui-implementor/`)
- [ ] 결정사항 표 / 위젯 표 / 구현 단계 / 입력 제한을 모두 갱신했는가?
- [ ] 스펙 문서만 읽은 다음 세션이 같은 결과를 만들 수 있을 정도로 구체적인가?
- [ ] 코드의 시그니처가 스펙과 일치하는가?
- [ ] `flutter analyze`가 No issues found인가?
