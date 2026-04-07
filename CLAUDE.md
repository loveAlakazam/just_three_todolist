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

## Branch Rules

화면별 작업은 **반드시 전용 feature 브랜치에서 진행**한다. 작업 시작 전 `git branch --show-current`로 확인하고, 다르면 해당 브랜치로 전환한다. 브랜치가 없으면 `main`에서 분기 생성.

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
- OPEN 상태 PR 감지 시 단순 append가 아닌 전체 재작성 (설계 결정이 바뀐 부분은 `리뷰 포인트` 블록으로 강조)
- 사전 요구사항: `gh` CLI 설치 및 인증 (`brew install gh && gh auth login`)
- 정의: `.claude/commands/pull-request.md`

## Specialized Agents

- **ui-implementor** — Flutter **View 레이어**(화면 + 공통 위젯) 전담 서브에이전트. 화면별 상세 명세는 `.claude/agents/ui-implementor/0[1-4]_*.md`. ViewModel / Repository / Supabase 연동 / go_router 설정은 범위 밖.

## Reference Documents

| 목적 | 경로 |
|------|------|
| 프로젝트 기능 / 디자인 시스템 | `.claude/rules/project-overview.md` |
| 아키텍처 규칙 | `.claude/rules/architecture.md` |
| 커밋 메시지 규칙 | `.claude/rules/git-commit.md` |
| 화면별 UI 상세 (v1.0.0) | `.claude/ui/v1.0.0/` |
| 와이어프레임 (v1.0.0) | `.claude/wireframe/v1.0.0/` |
