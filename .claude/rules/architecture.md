---
description: 기술 스택, MVVM 아키텍처, 폴더 구조, 개발 컨벤션. 코드 작성 및 파일 생성 시 항상 참조.
globs:
  - "lib/**/*.dart"
---

# 앱 개발(Flutter) 아키텍처

## 기술 스택

- 플랫폼: Flutter (iOS, Android 모바일 앱)
- 언어: Dart
- 상태관리: Riverpod
- 백엔드/DB: Supabase
- 인증: Supabase Auth (Google OAuth 직접 사용)
- 파일 저장소: Supabase Storage (프로필 이미지 등)
- 환경변수: `.env` + `flutter_dotenv`
- 라우팅: go_router
- 배포: TestFlight (iOS), 추후 Android 배포 방식 결정

## 아키텍처 (MVVM)

```
View (UI) → ViewModel (State/Riverpod) → Repository (Data) → Supabase (Remote)
```

### View (UI Layer)

- 화면을 그리는 역할만 담당
- 비즈니스 로직 없음
- ViewModel의 상태를 구독하여 화면 렌더링

### ViewModel (State Layer)

- View와 Repository 사이의 중간 다리
- 사용자 액션을 받아 Repository에 요청
- 데이터를 가공하여 View에 전달
- Riverpod Provider로 구현

### Repository (Data Layer)

- 데이터 소스를 추상화
- View/ViewModel은 데이터 출처를 알 필요 없음
- MVP 단계에서는 온라인 전용 (Supabase만 사용)
- 오프라인 지원 및 로컬 캐시는 고도화 단계에서 추가 예정

### Data Source

- Supabase API 호출 (원격)

## 폴더 구조

```
lib/
├── main.dart
├── features/
│   ├── auth/                 # 로그인/회원가입
│   │   ├── view/
│   │   ├── viewmodel/
│   │   └── repository/
│   ├── todo/                 # 투두리스트
│   │   ├── view/
│   │   ├── viewmodel/
│   │   └── repository/
│   ├── calendar/             # 달성 캘린더
│   │   ├── view/
│   │   ├── viewmodel/
│   │   └── repository/
│   └── profile/              # 마이탭 (회원정보, 프로필편집, 탈퇴)
│       ├── view/
│       ├── viewmodel/
│       └── repository/
├── core/
│   ├── supabase_client.dart  # Supabase 초기화
│   └── router.dart           # go_router 라우팅 설정
└── shared/
    ├── models/               # 데이터 모델 (Todo, User 등)
    └── widgets/              # 공통 위젯
```

### 파일 배치 규칙

- 새 기능 추가 시 `features/` 하위에 feature 디렉토리 생성 후 `view/`, `viewmodel/`, `repository/` 구조를 따름
- 여러 feature에서 공유하는 모델은 `shared/models/`에 배치
- 여러 feature에서 공유하는 위젯은 `shared/widgets/`에 배치
- Supabase 초기화, 라우터 등 앱 전역 설정은 `core/`에 배치

## 인증 전략

- MVP: Google 소셜 로그인 (Supabase Auth 기본 제공)
- 고도화: 네이버 (`flutter_naver_login` + Supabase Edge Function), 카카오 (`kakao_flutter_sdk` + `signInWithIdToken()`) 추가 예정

## 고도화 계획 (MVP 이후)

- 오프라인 지원: 로컬 DB (drift 또는 Hive) + 변경 큐 동기화 전략
- 소셜 로그인 확장: 네이버, 카카오
