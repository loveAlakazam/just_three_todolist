# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**Just Three** — 하루 3개 목표를 실천하는 Flutter 기반 모바일 투두리스트 앱 (iOS/Android, MVP 단계).

- **SDK**: Flutter `^3.11.4` / Dart
- **상태관리**: Riverpod (도입 예정)
- **백엔드**: Supabase (Auth / DB / Storage, 도입 예정)
- **라우팅**: go_router (도입 예정)
- **인증**: Google OAuth — [`sign_in_button`](https://pub.dev/packages/sign_in_button) 패키지 + Supabase Auth
- **플랫폼**: iOS, Android (모바일 전용)

자세한 기능/디자인 명세는 `.claude/rules/project-overview.md` 참조.

## Architecture (MVVM)

```text
View (UI) → ViewModel (State/Riverpod) → Repository (Data) → Supabase
```

```text
lib/
├── main.dart
├── features/
│   ├── auth/        # 로그인
│   ├── todo/        # 투두리스트
│   ├── calendar/    # 달성 캘린더
│   └── profile/     # 마이페이지, 프로필 편집
│       └─ view/ viewmodel/ repository/
├── core/            # supabase_client, router 등 전역 설정
└── shared/
    ├── models/      # 2개 이상 feature가 공유하는 모델
    └── widgets/     # 2개 이상 feature가 공유하는 위젯
```

- 새 기능은 `features/<feature>/{view,viewmodel,repository}/` 구조를 따른다.
- View는 화면 렌더링만 담당. 비즈니스 로직은 ViewModel, 데이터 접근은 Repository로 분리.
- 자세한 아키텍처 규칙: `.claude/rules/architecture.md`.

## Branch Rules (git-flow)

프로젝트는 [git-flow](https://danielkummer.github.io/git-flow-cheatsheet/index.html) 전략을 따른다. 상세 규칙은 `.claude/rules/git-flow.md` 참조.

- **기본 통합 브랜치**: `develop` — 모든 feature PR의 base.
- **릴리즈 브랜치**: `main` — `vX.Y.Z` 태그가 찍히는 브랜치. **직접 push 금지**. `/release`·`/hotfix` 커맨드의 PR 머지 경유만 허용.
- **feature 브랜치**는 **반드시 `develop`에서 분기**한다 (`main` 금지).
- 작업 시작 전 `git branch --show-current`로 확인하고, 다르면 해당 브랜치로 전환한다. 브랜치가 없으면 `develop`에서 분기 생성.
- feature 작업 완료 후 PR 생성 시 **base 브랜치는 `develop`**으로 지정한다.
- 릴리즈는 `/release`, 긴급 패치는 `/hotfix` 슬래시 커맨드로 일괄 처리한다. 수동 `git merge` + `git push origin main` 금지.

### 보호 브랜치 (main / develop)

아래 행위는 **서버(GitHub Branch Protection) + 로컬(husky hooks) 양쪽에서 차단**된다. Claude Code 가 실행할 때도, 사람이 터미널에서 직접 커밋/푸시할 때도 동일하게 적용된다. 우회 금지 (`--no-verify` 포함).

| 행위 | main | develop |
|------|------|---------|
| 브랜치 삭제 | ❌ | ❌ |
| Force push / non-fast-forward push | ❌ | ❌ |
| 직접 push (PR 경유 아님) | ❌ | ✅ (FF 머지만) |
| **`main` 에서 직접 커밋** | ❌ (husky `pre-commit`) | — |
| Admin 우회 | ❌ (`enforce_admins: true`) | ❌ (`enforce_admins: true`) |

**잘못된 릴리즈 복구는 forward-fix(`/hotfix`)만 허용한다.** revert 커밋으로 롤백 / 태그 삭제 / 릴리즈 삭제는 **전면 금지**다 (`.claude/rules/git-flow.md` §"잘못된 릴리즈 복구 전략" 참조).

### 로컬 git hook 활성화 (clone 직후 1회, husky)

```bash
npm install           # package.json 의 prepare 스크립트가 husky 를 호출 → core.hooksPath 자동 설정
```

확인: `git config --get core.hooksPath` → `.husky/_` 가 출력되면 활성. husky 소스:
- `.husky/pre-commit` — main 직접 커밋 차단
- `.husky/commit-msg` — 커밋 메시지 prefix 검증
- `.husky/pre-push` — main/develop 삭제·force·non-FF push 차단 + main 직접 push 차단

`git commit --no-verify` / `git push --no-verify` 로 훅을 우회하는 것은 git-flow 규칙 위반이다.

### 화면별 feature 브랜치

| 화면 | 브랜치 | 작업 범위 |
|------|--------|----------|
| 로그인 | `feature/login` | `lib/features/auth/` |
| Todo | `feature/todo` | `lib/features/todo/` |
| 캘린더 | `feature/calendar` | `lib/features/calendar/` |
| 마이페이지 | `feature/my-page` | `lib/features/profile/` |

## Commands (Flutter)

- **Run app**: `flutter run` (`-d chrome`, `-d macos` 등으로 플랫폼 지정)
- **Get dependencies**: `flutter pub get`
- **Analyze / lint**: `flutter analyze` (`package:flutter_lints` 기반)
- **Test**: `flutter test` (전체) / `flutter test test/<file>_test.dart` (단일)
- **Build**: `flutter build <platform>` (apk, ios, web, macos, linux, windows)

## Slash Commands

### `/commit`

현재 staged/unstaged 변경사항을 분석해 프로젝트 커밋 규칙을 따르는 커밋을 생성한다.

- 형식: `prefix: 한글메시지` (약 60자 이내)
- prefix: `feat` / `fix` / `docs` / `style` / `refactor` / `chore` 등 — `.claude/rules/git-commit.md` 참조
- `.env` 등 민감 파일 자동 제외, `Co-Authored-By` 자동 추가
- 정의: `.claude/commands/commit.md`

### `/pull-request`

현재 브랜치의 **모든 커밋**을 분석해 리뷰어가 이해하기 쉬운 Pull Request를 생성한다. 이미 열린 PR이 있으면 본문을 최신 커밋 기준으로 **재작성**한다.

- 변경사항을 논리 단위로 그룹화, "왜"에 집중한 본문 작성
- base 브랜치는 기본적으로 **`develop`** (git-flow 규칙)
- OPEN 상태 PR 감지 시 단순 append가 아닌 전체 재작성 (설계 결정이 바뀐 부분은 `리뷰 포인트` 블록으로 강조)
- 사전 요구사항: `gh` CLI 설치 및 인증 (`brew install gh && gh auth login`)
- 정의: `.claude/commands/pull-request.md`

### `/release`

`develop`에 누적된 변경사항을 분석해 다음 릴리즈 버전 `vX.Y.Z`를 결정하고, git-flow에 맞춰 release 브랜치 생성 → release PR → `gh pr merge` → 태그 → GitHub Release 공개 → `develop` back-merge를 수행한다.

- 버전 규칙: **X = 신규 기능 / Y = 기존 기능 변경 / Z = 버그 픽스** (일반 SemVer와 정의가 다름)
- develop에 머지된 PR들을 자동 분석해 어느 자리를 올릴지 판정한 뒤 사용자에게 한 번 더 확인
- **릴리즈 노트 필수 게이트**: 초안이 확정되기 전에는 main 머지로 넘어가지 않음. GitHub Release 생성까지 포함
- `main` 직접 push 금지 — `gh pr merge` 만 사용
- 사전 요구사항: `gh` CLI 인증, 로컬 `main`/`develop` 최신 동기화, husky 훅 활성 (`npm install`)
- 정의: `.claude/commands/release.md`

### `/hotfix`

`main`에 이미 배포된 릴리즈(`vX.Y.Z`)에서 버그가 발견되었을 때 **forward-fix**(`vX.Y.(Z+1)`) 로 긴급 패치를 배포한다. 이 프로젝트의 **유일한 공식 릴리즈 복구 방법**이다.

- `main` 에서 `hotfix/vX.Y.(Z+1)` 분기 → 수정 → `main` PR 머지 → 패치 태그 → GitHub Release → `develop` back-merge
- **revert 커밋 / 태그 삭제 / 릴리즈 삭제 / force push 전면 금지**
- 릴리즈 노트 필수 (간단해도 반드시 작성)
- 정의: `.claude/commands/hotfix.md`

## Specialized Agents

- **ui-implementor** — Flutter **View 레이어**(화면 + 공통 위젯) 전담 서브에이전트. 화면별 상세 명세는 `.claude/agents/ui-implementor/0[1-4]_*.md`. ViewModel / Repository / Supabase 연동 / go_router 설정은 범위 밖.

## Reference Documents

| 목적 | 경로 |
|------|------|
| 프로젝트 기능 / 디자인 시스템 | `.claude/rules/project-overview.md` |
| 아키텍처 규칙 | `.claude/rules/architecture.md` |
| 커밋 메시지 규칙 | `.claude/rules/git-commit.md` |
| 브랜치 / 릴리즈 전략 (git-flow) | `.claude/rules/git-flow.md` |
| 화면별 UI 상세 (v1.0.0) | `.claude/ui/v1.0.0/` |
| 와이어프레임 (v1.0.0) | `.claude/wireframe/v1.0.0/` |
