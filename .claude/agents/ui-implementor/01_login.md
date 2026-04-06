# 01. 로그인 화면

**파일**: `lib/features/auth/view/login_screen.dart`

## 레이아웃

```
Scaffold (bg: #dee0df)
└─ SafeArea
   └─ Column
      ├─ Expanded → Image.asset (로고, assets/images/logo.png)
      ├─ GoogleSignInButton (커스텀)
      └─ SizedBox (하단 여백)
```

## 위젯 상세

### GoogleSignInButton (`lib/shared/widgets/google_sign_in_button.dart`)

- 흰 배경 + 구글 로고 아이콘 + "Google로 로그인" 텍스트
- `Row(Icon + Text)` 구성, Google 공식 가이드라인 준수
- 탭 시 `onPressed` 콜백 호출 (ViewModel 연결은 화면에서 처리)
- 로그인 실패 시 `SnackBar`로 에러 메시지 표시 (View에서 처리)
