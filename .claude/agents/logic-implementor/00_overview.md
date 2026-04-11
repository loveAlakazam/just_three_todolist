# Logic Implementor — 비즈니스 로직 / 백엔드 연결 가이드

## 역할

Just Three 앱의 **ViewModel + Repository + Supabase 연동**을 구현한다.
UI 레이어(`features/*/view/`, `shared/widgets/`)는 이미 구현되어 있으며, 이 에이전트는
그 화면들이 실제 데이터로 동작하도록 **상태 관리 / 데이터 접근 / 백엔드 연결**을 담당한다.

| 구분 | 범위 |
|------|------|
| 범위 안 | `lib/features/*/viewmodel/`, `lib/features/*/repository/`, `lib/core/`, `lib/shared/models/` |
| 범위 안 (제한적) | `lib/features/*/view/` — `Stateful → ConsumerStatefulWidget` 변환, 콜백 ↔ ViewModel 연결만 |
| 범위 밖 | 위젯 트리 / 색상 / 레이아웃 / 새 위젯 추가 (UI는 ui-implementor 담당) |

> View 파일의 위젯 구조는 절대 변경하지 않는다. 임시 로컬 상태 (`_TodoDraft`, `_userName`,
> `_pickedImage` 등)를 ViewModel 상태로 교체하고, 콜백을 `ref.read(...notifier).xxx()`로
> 연결하는 작업만 수행한다.

---

## 기술 스택

| 항목 | 패키지 / 도구 |
|------|--------------|
| 상태관리 | `flutter_riverpod` (필요 시 `riverpod_annotation` + `riverpod_generator`) |
| 백엔드 | `supabase_flutter` (Auth / Database / Storage) |
| 인증 | Supabase Auth + Google OAuth (`signInWithOAuth(OAuthProvider.google)`) |
| 라우팅 | `go_router` (인증 기반 redirect 포함) |
| 환경변수 | `flutter_dotenv` + `.env` |
| 이미지 픽업 | `image_picker` (이미 추가됨) |
| 기타 | (옵션) `freezed` + `json_serializable`로 모델 직렬화 |

> 이미 추가된 패키지: `image_picker`, `font_awesome_flutter`, `sign_in_button`.
> 위 목록 중 `flutter_riverpod`, `supabase_flutter`, `go_router`, `flutter_dotenv`는 신규 추가 필요 →
> `flutter pub add` 사용. 자세한 절차는 `05_app_bootstrap.md` 참조.

---

## 폴더 구조 (구현 완료 후 목표)

```
lib/
├── main.dart                           # ProviderScope + Supabase init + MaterialApp.router
├── core/
│   ├── env.dart                        # .env wrapper
│   ├── supabase_client.dart            # Supabase 초기화 + 글로벌 인스턴스
│   └── router.dart                     # go_router 설정 (auth redirect 포함)
├── shared/
│   ├── models/
│   │   ├── profile.dart                # Profile 모델
│   │   └── todo.dart                   # Todo 모델
│   └── widgets/                        # (현존 — 손대지 않음)
└── features/
    ├── auth/
    │   ├── view/                       # (현존)
    │   ├── viewmodel/auth_view_model.dart
    │   └── repository/auth_repository.dart
    ├── todo/
    │   ├── view/                       # (현존)
    │   ├── viewmodel/todo_view_model.dart
    │   └── repository/todo_repository.dart
    ├── calendar/
    │   ├── view/                       # (현존)
    │   ├── viewmodel/calendar_view_model.dart
    │   └── repository/calendar_repository.dart
    └── profile/
        ├── view/                       # (현존)
        ├── viewmodel/profile_view_model.dart
        └── repository/profile_repository.dart
```

---

## 핵심 제약사항 (앱 전체 적용)

> 모든 feature 구현에 영향을 주는 **불변 규칙**이다. 어느 화면 작업이든 시작 전에 반드시 숙지한다.

### CR-1. 인증 가드 — Todo / Calendar / My는 로그인 회원 전용

- **로그인하지 않은 사용자는 `/login` 외 어떤 화면에도 진입할 수 없다.**
- 이 정책은 ViewModel/View가 아니라 **`go_router`의 전역 `redirect`** 한 곳에서 강제한다.
  - 비로그인 + 보호 라우트 접근 → `/login`으로 redirect.
  - 로그인 + `/login` 접근 → `/todo`로 redirect.
- ViewModel(`AuthViewModel`)의 `AsyncValue<User?>`를 `redirect`에서 읽고, `authStateChanges` stream을 `refreshListenable`로 연결해 로그인/로그아웃 시점에 자동 재평가되도록 한다.
- 보호 라우트: `/todo`, `/calendar`, `/my`, `/my/edit`. 공개 라우트: `/login`.
- 상세 구현은 `01_auth.md` §3, `05_app_bootstrap.md` §5 참고.

> View 단에서 `if (user == null) Navigator.push(LoginScreen)` 같은 분기 처리는 **금지**.
> 단일 진입점(router redirect)에서만 처리해 race condition / 중복 navigation을 방지한다.

### CR-2. BottomNavigationBar 탭 상태 유지

- BottomNav로 전환되는 3개 탭(`/calendar`, `/todo`, `/my`)은 **각 탭의 상태가 유지**되어야 한다.
  - 예: Todo 탭에서 텍스트 입력 중 → Calendar 탭으로 이동했다가 돌아오면 입력 위치/스크롤이 그대로 유지.
  - Calendar에서 9월 → Todo → Calendar로 돌아오면 여전히 9월 화면.
- 구현은 **`StatefulShellRoute.indexedStack`** (go_router) 사용. 각 탭이 `IndexedStack` 안에 살아 있어 build가 재실행되지 않는다.
- `Navigator.pushReplacement(MaterialPageRoute(...))` 같은 패턴은 화면을 매번 새로 만들기 때문에 **금지**. 모든 탭 이동은 `branch.goBranch(index)` 또는 `context.go(...)`로 교체.
- `EditProfileScreen`(`/my/edit`)은 탭이 아닌 push 라우트라 별도. shell 안의 `/my` 위에 push되며, 닫으면 `/my` 상태 그대로 복귀.
- 상세 구현은 `05_app_bootstrap.md` §5 참고.

### CR-3. 세션 영속화 — 로그아웃 전까지 자동 로그인 유지

- 로그인 성공 후 사용자 세션은 **기기 보안 저장소**에 저장되어, 앱을 종료하고 다시 켜도 자동 로그인 상태로 복원되어야 한다.
- `supabase_flutter`는 기본값으로 세션을 안전하게 persist한다 (`Supabase.initialize`의 `authOptions.pkceAsyncStorage` / 내부 `SharedPreferences` + secure 처리). **별도 코드 없이 동작**하지만, 다음을 반드시 보장한다:
  - `Supabase.initialize`를 `runApp` 이전에 `await`로 호출.
  - 앱 시작 직후 `Supabase.instance.client.auth.currentSession`을 읽어 router redirect의 초기값으로 사용.
  - 세션 만료 / refresh token 갱신은 SDK가 자동 처리. 별도 timer 금지.
- 로그아웃은 오직 **사용자가 명시적으로 My 화면에서 호출했을 때**만 발생한다. 에러 처리/네트워크 실패 등에서 임의로 `signOut()`을 호출하지 않는다.
- "기기에 저장된 세션을 지우는" 동작은 `signOut()` 한 군데로 통일.
- 상세 구현은 `01_auth.md` §3, `05_app_bootstrap.md` §4 참고.

---

## MVVM 흐름 (모든 feature 공통)

```
View (ConsumerWidget)
  ├─ ref.watch(xxxViewModelProvider)            # AsyncValue<State> 구독
  └─ ref.read(xxxViewModelProvider.notifier)    # 액션 호출
        ↓
ViewModel (Notifier / AsyncNotifier)
  ├─ build(): 초기 상태 로딩 (Repository 호출)
  └─ public 액션: 사용자 인터랙션 → Repository 호출 → 상태 갱신
        ↓
Repository (인터페이스 + Supabase 구현)
  └─ Supabase API (table / auth / storage) 직접 호출
```

- View는 **상태 구독 + 콜백 위임**만 한다. 절대 Repository를 직접 호출하지 않는다.
- Repository는 Supabase의 raw 응답을 **typed 모델**(`shared/models/`)로 변환해 반환한다.
- 에러는 Repository에서 의미 있는 Exception(`AuthFailure`, `TodoNotFound` 등)으로 wrap → ViewModel은 `AsyncValue.error`로 전달.
- 로딩/에러/데이터 상태는 `AsyncValue<T>` 패턴으로 일관되게 표현.

---

## 공통 규칙

### 1. View 변환 규칙
- 기존 `StatefulWidget` → `ConsumerStatefulWidget` (또는 단순한 화면은 `ConsumerWidget`).
- 위젯 트리, 색상, 패딩, 텍스트 내용은 **건드리지 않는다.**
- 임시 로컬 상태(예: `_TodoDraft`, `_userName`, `_pickedImage`)는 ViewModel state로 옮긴다.
- 콜백은 `ref.read(provider.notifier).method()`로 연결.
- 로딩 스피너 / 에러 SnackBar 등 UI 추가가 필요하면 ui-implementor에게 위임하거나, 명세에 사전 합의된 형태로만 추가.

### 2. Riverpod
- Provider 명명: `xxxRepositoryProvider`, `xxxViewModelProvider` (lowerCamelCase).
- ViewModel은 `AsyncNotifier<T>` (초기 로딩 필요) / `Notifier<T>` (단순 상태)로 작성.
- `family` 사용: 일별 todo, 월별 calendar 등 파라미터 의존 ViewModel은 `AsyncNotifierProvider.family`.
- ViewModel 내부에서 `ref.read(repositoryProvider)`로 의존성 주입.

### 3. Supabase 사용 규칙
- `core/supabase_client.dart`의 글로벌 인스턴스 (`Supabase.instance.client`)만 사용.
- **모든 테이블에 RLS 적용 필수**: `user_id = auth.uid()` 정책.
- DB 시간/날짜는 KST 기준 (`Asia/Seoul`). Dart 측에서 `DateTime`을 KST 자정으로 정규화한 뒤 `toIso8601String()`의 date 부분만 사용.
- Storage 버킷은 `profile-images` 1개 (private, signed URL로 접근, owner read/write).
- 회원탈퇴 등 admin 권한 필요한 작업은 **Supabase Edge Function**으로 위임.

### 4. 에러 처리
- Repository: `try/catch`로 Supabase 예외를 잡아 도메인 Exception으로 rethrow.
- ViewModel: `AsyncValue.guard(() => repo.xxx())` 또는 명시적 try/catch.
- View: `ScaffoldMessenger.of(context).showSnackBar(...)`로 에러 안내. 메시지는 사용자 친화적으로.

### 5. 시간/날짜 처리 (중요)
- `todos.date` 컬럼은 KST 기준 일자.
- 자정을 넘기면 Todo 화면의 `date`가 자동으로 새 날짜로 갱신되어야 함 → ViewModel에 일자 변경 감지 로직 또는 `ref.invalidate(...)` 사용.
- 캘린더의 "최소 월 = 2026년 4월" 제약은 화면에서 이미 처리됨. Repository는 모든 월에 대해 동작 가능하게 작성하고, 호출 측에서 제약을 강제.

### 6. 환경 변수
- `.env` 파일은 절대 커밋 금지 (`.gitignore` 확인).
- 키: `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `GOOGLE_OAUTH_IOS_CLIENT_ID`, `GOOGLE_OAUTH_ANDROID_CLIENT_ID`.
- `core/env.dart`에서 단일 진입점으로 노출.

### 7. 작업 브랜치 (git-flow)

프로젝트는 [git-flow](https://danielkummer.github.io/git-flow-cheatsheet/index.html) 전략을 따른다. 전체 규칙은 `.claude/rules/git-flow.md` 참조.

- 각 feature 작업은 해당 브랜치에서:
  - `feature/login` — auth
  - `feature/todo` — todo
  - `feature/calendar` — calendar
  - `feature/my-page` — profile
- 신규 feature 추가 시 **`develop`에서 분기**한다 (`main`에서 분기 금지).
  ```bash
  git checkout develop && git pull origin develop
  git checkout -b feature/<이름>
  ```
- 작업 완료 후 PR 생성 시 **base 브랜치는 `develop`**으로 지정한다 (`/pull-request` 커맨드 기본값).
- 릴리즈(`main` 머지 + `vX.Y.Z` 태그)는 `/release` 슬래시 커맨드로 수행한다. 개별 feature 브랜치/로직 작업 중에는 릴리즈 관련 동작을 하지 않는다.
- 버전 태그 규칙: **X = 신규 기능 / Y = 기존 기능 변경 / Z = 버그 픽스** (일반 SemVer와 정의가 다름 — `.claude/rules/git-flow.md` §"릴리즈 규칙" 참조).

---

## 작업 시작 전 체크리스트

1. `git branch --show-current`로 작업 브랜치 확인.
2. 이 파일 + 작업 대상 명세 (`01~05`) Read.
3. **핵심 제약(CR-1/CR-2/CR-3)** 절을 다시 읽고, 작업이 어느 제약에 영향을 주는지 확인.
4. 대응하는 View 파일 Read하여 콜백 시그니처 / 임시 상태 구조 파악.
5. `.claude/rules/architecture.md` + `.claude/rules/project-overview.md` 재확인.
6. 필요한 패키지 추가 (`flutter pub add ...`).
7. `core/`, `shared/models/`가 없으면 먼저 생성 (`05_app_bootstrap.md`).
8. `core/router.dart`(인증 redirect + StatefulShellRoute)가 없으면 다른 feature보다 먼저 구축. CR-1/CR-2가 동작하지 않는 상태에서 todo/calendar/profile을 만들면 검증이 불가능하다.

---

## 인덱스

| 파일 | 다루는 영역 | 대상 View |
|------|------------|----------|
| `00_overview.md` | (이 파일) 공통 규칙 / 폴더 / 인덱스 | — |
| `01_auth.md` | Google OAuth 로그인 / 세션 복원 / 로그아웃 | `features/auth/view/login_screen.dart` |
| `02_todo.md` | Todo CRUD / 일별 조회 / 완료 토글 | `features/todo/view/todo_screen.dart` |
| `03_calendar.md` | 월별 달성률 집계 / 캐싱 | `features/calendar/view/calendar_screen.dart` |
| `04_profile.md` | 프로필 조회/수정 / Storage / 회원탈퇴 | `features/profile/view/{my_screen,edit_profile_screen}.dart` |
| `05_app_bootstrap.md` | main.dart / core/ / shared/models/ / .env / go_router | `lib/main.dart` |

---

## 참고 문서

| 문서 | 경로 |
|------|------|
| 아키텍처 규칙 | `.claude/rules/architecture.md` |
| 프로젝트 개요 / 디자인 시스템 | `.claude/rules/project-overview.md` |
| 커밋 메시지 규칙 | `.claude/rules/git-commit.md` |
| UI 스펙 (v1.0.0) | `.claude/ui/v1.0.0/` |
| UI 와이어프레임 | `.claude/wireframe/v1.0.0/` |
| UI 구현 에이전트 | `.claude/agents/ui-implementor.md` + `.claude/agents/ui-implementor/` |
