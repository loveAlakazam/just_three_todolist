# 01. 로그인 화면

**파일**: `lib/features/auth/view/login_screen.dart`

## 작업 브랜치 (git-flow)

- 로그인 화면 UI 구현 및 개발 작업은 **반드시 `feature/login` 브랜치에서 진행**한다.
- 작업 시작 전 현재 브랜치를 확인하고, 다른 브랜치라면 `feature/login`으로 전환한 후 작업한다.
- `feature/login` 브랜치가 없다면 **`develop`에서 분기**하여 생성한다 (`main`에서 분기 금지).
  ```bash
  git checkout develop && git pull origin develop
  git checkout -b feature/login
  ```
- 작업 완료 후 PR 생성 시 **base 브랜치는 `develop`**으로 지정한다. `/pull-request` 커맨드는 이미 `develop`을 기본 base로 사용한다.
- 전체 브랜치/릴리즈 전략은 `.claude/rules/git-flow.md` 참조.

## 레이아웃

```text
Scaffold (bg: #f3f4eb)
└─ SafeArea
   └─ Column
      ├─ Expanded → Image.asset (로고, assets/images/just-three-logo.png)
      ├─ SignInButton (Buttons.google, sign_in_button 패키지)
      └─ SizedBox (하단 여백)
```

## 로고 이미지

- **에셋 경로**: `assets/images/just-three-logo.png`
- **원본 파일**: `.claude/wireframe/v1.0.0/01_로그인화면/just-three-logo.png`
- 원본 파일을 `assets/images/just-three-logo.png`로 복사해 사용한다.
- `pubspec.yaml`의 `flutter.assets`에 `assets/images/` 경로가 등록되어 있어야 한다.
- `Image.asset`에 `fit: BoxFit.contain`을 지정해 비율을 유지한다.

## 로그인 플로우

### 인증 방식

- **네이티브 Google Sign-In** (`google_sign_in` 패키지) → `idToken` 획득 → Supabase `signInWithIdToken`
- 웹 기반 OAuth (PKCE/implicit) 는 사용하지 않음. 콜백 URL 불필요.

### 신규 회원 (앱 최초 이용)

1. 구글 로그인 버튼 클릭
2. (Google) 구글 계정 선택 화면
3. (Google) 로그인 성공 시 접근 권한 허용 화면
4. 로그인 완료 → Todo 화면(`/todo`)으로 이동

### 기존 회원 (토큰 만료 / 로그아웃 후 재로그인)

1. 구글 로그인 버튼 클릭
2. (Google) 구글 계정 선택 화면
3. 로그인 완료 → Todo 화면(`/todo`)으로 이동

### 로그인 실패

1. 에러 발생 시 `SnackBar`로 "로그인에 실패했습니다. 다시 시도해주세요." 표시
2. 로그인 화면 유지 (다른 화면으로 이동하지 않음)

### 로그인 취소

1. 구글 계정 선택에서 취소 시 에러 메시지 없이 로그인 화면 유지

---

## 위젯 상세

### Google 로그인 버튼 (`sign_in_button` 패키지)

- **패키지**: [`sign_in_button`](https://pub.dev/packages/sign_in_button) `^4.1.0`
- **사용 위젯**: `SignInButton(Buttons.google, ...)` — 패키지가 Google 공식 가이드라인을 이미 준수
- **커스터마이징**: `text: 'Google로 로그인'`로 한글 텍스트 적용
- **사용 위치**: `lib/features/auth/view/login_screen.dart`에서 직접 사용 (별도 래퍼 위젯 없음)
- 탭 시 `onPressed` 콜백 호출 (ViewModel 연결은 화면에서 처리)
- 로그인 실패 시 `SnackBar`로 에러 메시지 표시 (View에서 처리)

```dart
SignInButton(
  Buttons.google,
  text: 'Google로 로그인',
  onPressed: () => _handleGoogleSignIn(context),
)
```
