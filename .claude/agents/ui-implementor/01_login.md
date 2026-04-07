# 01. 로그인 화면

**파일**: `lib/features/auth/view/login_screen.dart`

## 작업 브랜치

- 로그인 화면 UI 구현 및 개발 작업은 **반드시 `feature/login` 브랜치에서 진행**한다.
- 작업 시작 전 현재 브랜치를 확인하고, 다른 브랜치라면 `feature/login`으로 전환한 후 작업한다.
- `feature/login` 브랜치가 없다면 `main`에서 분기하여 생성한다.

## 레이아웃

```text
Scaffold (bg: #f3f4eb)
└─ SafeArea
   └─ Column
      ├─ Expanded → Image.asset (로고, assets/images/just-three-logo.png)
      ├─ GoogleSignInButton (커스텀)
      └─ SizedBox (하단 여백)
```

## 로고 이미지

- **에셋 경로**: `assets/images/just-three-logo.png`
- **원본 파일**: `.claude/wireframe/v1.0.0/01_로그인화면/just-three-logo.png`
- 원본 파일을 `assets/images/just-three-logo.png`로 복사해 사용한다.
- `pubspec.yaml`의 `flutter.assets`에 `assets/images/` 경로가 등록되어 있어야 한다.
- `Image.asset`에 `fit: BoxFit.contain`을 지정해 비율을 유지한다.

## 위젯 상세

### GoogleSignInButton (`lib/shared/widgets/google_sign_in_button.dart`)

- 흰 배경 + 구글 로고 아이콘 + "Google로 로그인" 텍스트
- `Row(Icon + Text)` 구성, Google 공식 가이드라인 준수
- 탭 시 `onPressed` 콜백 호출 (ViewModel 연결은 화면에서 처리)
- 로그인 실패 시 `SnackBar`로 에러 메시지 표시 (View에서 처리)
