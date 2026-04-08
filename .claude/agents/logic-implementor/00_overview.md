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
- Storage 버킷은 `avatars` 1개 (public read, owner write).
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
- 키: `SUPABASE_URL`, `SUPABASE_ANON_KEY`, (필요 시) `GOOGLE_WEB_CLIENT_ID`, `GOOGLE_IOS_CLIENT_ID`.
- `core/env.dart`에서 단일 진입점으로 노출.

### 7. 작업 브랜치
- 각 feature 작업은 해당 브랜치에서:
  - `feature/login` — auth
  - `feature/todo` — todo
  - `feature/calendar` — calendar
  - `feature/my-page` — profile
- 새 feature 추가 시 main에서 분기.

---

## 작업 시작 전 체크리스트

1. `git branch --show-current`로 작업 브랜치 확인.
2. 이 파일 + 작업 대상 명세 (`01~05`) Read.
3. 대응하는 View 파일 Read하여 콜백 시그니처 / 임시 상태 구조 파악.
4. `.claude/rules/architecture.md` + `.claude/rules/project-overview.md` 재확인.
5. 필요한 패키지 추가 (`flutter pub add ...`).
6. `core/`, `shared/models/`가 없으면 먼저 생성 (`05_app_bootstrap.md`).

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
