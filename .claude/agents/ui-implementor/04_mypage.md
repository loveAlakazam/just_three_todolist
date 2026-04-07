# 04. 마이페이지 화면

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
  - 버튼: "취소" (닫기) / "확인" (onConfirm 콜백)

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
