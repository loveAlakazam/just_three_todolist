# 04. 마이페이지 화면

## 작업 브랜치

- 마이페이지(My 탭, 프로필 편집) UI 구현 및 개발 작업은 **반드시 `feature/my-page` 브랜치에서 진행**한다.
- 작업 시작 전 현재 브랜치를 확인하고, 다른 브랜치라면 `feature/my-page`로 전환한 후 작업한다.
- `feature/my-page` 브랜치가 없다면 `main`에서 분기하여 생성한다.

## My 탭 초기화면

**파일**: `lib/features/profile/view/my_screen.dart`

### 레이아웃

```
Scaffold (bg: #f3f4eb)
└─ SafeArea
   └─ Column
      ├─ Row
      │  ├─ CircleAvatar (프로필 이미지)
      │  └─ Text ("{이름} 님", #512DA8)
      ├─ ElevatedButton ("프로필 편집", #512DA8)
      ├─ ElevatedButton ("회원탈퇴", gray)
      └─ BottomNavigationBar (My 활성)
```

### 동작

- 프로필 편집 버튼: `go_router.push('/profile/edit')` 연결
- 회원탈퇴 버튼: `showDialog(AlertDialog)` 표시
  - 타이틀: "탈퇴하시겠습니까?"
  - 본문 (보조 안내): "탈퇴 후 14일 동안은 같은 계정으로 재가입할 수 없습니다."
  - 버튼: "취소" (닫기) / "확인" (onConfirm 콜백)
- 회원탈퇴 확인 흐름:
  1. "확인" 탭 → `ProfileViewModel.deleteAccount()` 호출 (logic-implementor 범위).
  2. 성공 → 다이얼로그 닫기 → **로그인 화면으로 자동 이동**. 화면 전환은 `go_router`의 전역 redirect (`auth state == null`) 가 담당하므로, View는 별도로 `Navigator.pushReplacement` 등을 호출하지 않는다. 단순히 `if (mounted) Navigator.of(context).pop()`으로 다이얼로그만 닫으면 redirect가 자동으로 `/login`으로 보낸다.
  3. 실패 → 다이얼로그 닫고 SnackBar로 에러 안내 ("탈퇴에 실패했습니다. 잠시 후 다시 시도해주세요.").
- 14일 재가입 제한 정책은 백엔드에서 강제되며, UI에는 다이얼로그 보조 문구 외 추가 표시 없음. 탈퇴 후 14일 이내 같은 Google 계정으로 로그인을 시도하면 로그인 화면에서 SnackBar로 안내가 노출된다 (해당 흐름은 `01_auth.md` / `04_profile.md` 참고).

### BottomNavigationBar 동작

- `currentIndex = 2` (My 활성).
- 탭별 이동:
  | 인덱스 | 라벨 | 동작 |
  |--------|------|------|
  | 0 | Calendar | `CalendarScreen`으로 화면 전환 (replace) |
  | 1 | To Do | `TodoScreen`으로 화면 전환 (replace) |
  | 2 | My | 현재 화면 — no-op |
- go_router 도입 전: `Navigator.pushReplacement(MaterialPageRoute(builder: (_) => const CalendarScreen()))`.
- 공통 규칙은 `.claude/agents/ui-implementor.md` `공유 위젯: BottomNavigationBar` 절 참고.

---

## 프로필 편집 화면

**파일**: `lib/features/profile/view/edit_profile_screen.dart`

### 레이아웃

```
Scaffold (bg: #f3f4eb)
└─ SafeArea
   └─ Column
      ├─ Stack
      │  ├─ CircleAvatar (프로필 이미지)
      │  └─ Positioned(bottom-right)
      │     └─ GestureDetector → showModalBottomSheet
      │        └─ Container(circle) + Icon(camera_alt)
      ├─ Row
      │  ├─ Text ("이름", #512DA8)
      │  └─ TextField (기존 이름 prefill)
      ├─ ElevatedButton ("수정하기", #512DA8)
      └─ BottomNavigationBar (My 활성 유지)
```

### 이미지 선택 BottomSheet

- "이미지 업로드": `image_picker`로 갤러리 접근 → 임시 상태 저장
- "이미지 제거": 기본 이미지 에셋으로 임시 변경
- **임시 적용**: 수정하기 버튼 탭 전까지 미저장 (화면 이탈 시 변경 취소)
