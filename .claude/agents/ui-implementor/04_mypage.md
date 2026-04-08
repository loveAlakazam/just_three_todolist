# 04. 마이페이지 화면

## 작업 브랜치 (git-flow)

- 마이페이지(My 탭, 프로필 편집) UI 구현 및 개발 작업은 **반드시 `feature/my-page` 브랜치에서 진행**한다.
- 작업 시작 전 현재 브랜치를 확인하고, 다른 브랜치라면 `feature/my-page`로 전환한 후 작업한다.
- `feature/my-page` 브랜치가 없다면 **`develop`에서 분기**하여 생성한다 (`main`에서 분기 금지).
  ```bash
  git checkout develop && git pull origin develop
  git checkout -b feature/my-page
  ```
- 작업 완료 후 PR 생성 시 **base 브랜치는 `develop`**으로 지정한다. `/pull-request` 커맨드는 이미 `develop`을 기본 base로 사용한다.
- 전체 브랜치/릴리즈 전략은 `.claude/rules/git-flow.md` 참조.

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
  - `showDialog(barrierDismissible: false)` — 호출 진행 중 사용자가 다이얼로그 바깥을 탭해 임의로 닫는 것을 막는다 (탈퇴 요청과 다이얼로그 lifecycle을 분리).
- 회원탈퇴 확인 흐름:
  1. "확인" 탭 → `ProfileViewModel.deleteAccount()` 호출 (logic-implementor 범위).
     - **로딩 처리**: 호출 시작 시 다이얼로그 내부 로컬 `isDeleting = true`로 전환. UI 효과:
       - "확인" 버튼 → `CircularProgressIndicator` (size 16~20)로 교체.
       - "취소" 버튼은 `onPressed: null`로 비활성.
     - **중복 클릭 방어**: `isDeleting == true`인 동안 "확인" 콜백 재진입을 가드 (early return).
     - 다이얼로그는 `StatefulBuilder` 또는 별도 `StatefulWidget`으로 분리해 `setState` 가능하게 구성.
  2. 성공 → 다이얼로그 닫기 → **로그인 화면으로 자동 이동**. 화면 전환은 `go_router`의 전역 redirect (`auth state == null`) 가 담당하므로, View는 별도로 `Navigator.pushReplacement` 등을 호출하지 않는다. 단순히 `if (mounted) Navigator.of(context).pop()`으로 다이얼로그만 닫으면 redirect가 자동으로 `/login`으로 보낸다.
  3. 실패 → 다이얼로그 닫고(`pop`) `isDeleting`을 false로 복구한 뒤 SnackBar로 안내:
     - 메시지: **"탈퇴에 실패했습니다. 잠시 후 다시 시도해주세요."**
     - SnackBar `duration: 4초`, action 없이 단순 안내.
     - 사용자는 동일한 "회원탈퇴" 버튼을 다시 탭해 **재시도할 수 있다**. 재시도 안전성(idempotent)은 logic-implementor의 `deleteAccount()` 책임이며, 이미 일부 정리된 상태에서 다시 호출해도 깨지지 않도록 설계되어 있다(`04_profile.md` §7 참조).
  4. **부분 실패 회복(주의)**: 탈퇴가 실패했더라도 사용자 데이터(`profiles`/Storage 아바타)는 일부 사라진 상태일 수 있다. 사용자가 SnackBar 안내 후 곧바로 My 화면을 다시 그리거나 다른 탭에 갔다 와도 화면이 깨지지 않아야 한다 — `ProfileViewModel`이 fallback(빈 프로필 또는 재생성)을 보장하므로, View는 `AsyncValue.error` 케이스에서 SnackBar 한 번 외에 추가 분기 처리를 하지 않는다.
- 14일 재가입 제한 정책은 백엔드에서 강제되며, UI에는 다이얼로그 보조 문구 외 추가 표시 없음. 탈퇴 후 14일 이내 같은 Google 계정으로 로그인을 시도하면 로그인 화면에서 SnackBar로 안내가 노출된다 (해당 흐름은 `01_auth.md` / `04_profile.md` 참고).

#### 회원탈퇴 다이얼로그 구현 스켈레톤 (참고)

```dart
Future<void> _showWithdrawDialog() async {
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) {
      bool isDeleting = false;
      return StatefulBuilder(
        builder: (ctx, setStateDialog) {
          Future<void> onConfirm() async {
            if (isDeleting) return; // 중복 클릭 가드
            setStateDialog(() => isDeleting = true);
            try {
              await ref
                  .read(profileViewModelProvider.notifier)
                  .deleteAccount();
              // 성공: 다이얼로그만 닫는다. 라우팅은 redirect가 처리.
              if (mounted) Navigator.of(dialogContext).pop();
            } catch (_) {
              if (mounted) Navigator.of(dialogContext).pop();
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('탈퇴에 실패했습니다. 잠시 후 다시 시도해주세요.'),
                    duration: Duration(seconds: 4),
                  ),
                );
              }
            }
          }

          return AlertDialog(
            title: const Text('탈퇴하시겠습니까?'),
            content: const Text('탈퇴 후 14일 동안은 같은 계정으로 재가입할 수 없습니다.'),
            actions: [
              TextButton(
                onPressed: isDeleting ? null : () => Navigator.of(ctx).pop(),
                child: const Text('취소'),
              ),
              TextButton(
                onPressed: isDeleting ? null : onConfirm,
                child: isDeleting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('확인'),
              ),
            ],
          );
        },
      );
    },
  );
}
```

> 위 스켈레톤은 "확인" 버튼 안에 progress indicator를 두는 형태다. 디자인 시스템 가이드에 다른 로딩 표현이 있다면 그대로 따른다. 핵심 계약은 (1) `barrierDismissible: false`, (2) 로딩 중 버튼 비활성, (3) 성공/실패 모두 다이얼로그 `pop`, (4) 라우팅은 redirect 위임 — 4가지다.

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
