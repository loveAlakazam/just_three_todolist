# 04. 마이페이지 / 프로필 편집 비즈니스 로직

## 작업 브랜치
`feature/my-page`

## 대상 View
- `lib/features/profile/view/my_screen.dart`
- `lib/features/profile/view/edit_profile_screen.dart`

### 현재 상태 (UI 구현 완료, 로직 미연결)

#### `my_screen.dart`
```dart
static const String _userName = '사용자';                  // 하드코딩
String? get _profileImageUrl => null;                       // 항상 null
// TODO(profile): ProfileViewModel.deleteAccount() 호출 후 로그인 화면으로 이동.
```
- 회원탈퇴 다이얼로그 "확인" 콜백이 비어 있음.
- 프로필 편집 진입은 `Navigator.push(...EditProfileScreen)`로 동작 (go_router 도입 시 교체).

#### `edit_profile_screen.dart`
```dart
static const String _initialName = '사용자';                // 하드코딩 (My에서 전달받아야 함)
XFile? _pickedImage;                                        // 임시 상태
final ImagePicker _imagePicker = ImagePicker();             // 갤러리 픽업은 동작
// TODO(profile): ProfileViewModel.updateProfile()에 이름 / 이미지 변경 사항을 전달
void _onSubmit() { Navigator.of(context).pop(); }           // 단순 pop, 저장 없음
```
- 갤러리에서 이미지 선택은 동작 (`image_picker` 연결 완료).
- "이미지 제거"는 `_pickedImage = null`만 호출. 기존 원격 이미지 삭제 처리 없음.
- 수정하기 버튼이 단순 pop만 수행 → DB 반영 안 됨.

---

## 구현해야 할 비즈니스 로직

### 1. 현재 사용자 프로필 조회 (My 진입 시)
- `profiles` 테이블에서 `auth.uid()` 기준 row 1건 select.
- 결과를 `Profile` 모델로 변환.
- 첫 진입 시점에 row가 없으면 `01_auth.md`의 `ensureProfileExists`가 이미 만들어 두었어야 함. 그래도 방어적으로 fallback.

### 2. 이름 수정
- Edit 화면에서 입력한 새 이름을 `profiles.name` UPDATE.
- 빈 문자열 / 공백만 입력 시 reject (SnackBar로 안내).
- 길이 제한: 한글 기준 20자 정도 (정책 미정 — 일단 30자 cap).

### 3. 이미지 변경 (3가지 케이스)
사용자가 Edit 화면에서 수행할 수 있는 동작은 다음 3가지 중 하나:

| 케이스 | 동작 | View 상태 | DB / Storage 처리 |
|--------|------|----------|------------------|
| `keep` | 아무것도 안 함 | `_pickedImage == null && !_imageRemoved` | 변경 없음 |
| `replace` | 갤러리에서 새 이미지 선택 | `_pickedImage != null` | Storage 업로드 → 새 URL → profiles UPDATE → (기존 파일이 있으면) 삭제 |
| `remove` | "이미지 제거" 탭 | `_pickedImage == null && _imageRemoved == true` | 기존 Storage 파일 삭제 → profiles.avatar_url = null |

> **주의**: 현재 `edit_profile_screen.dart`는 `_pickedImage` 1개로만 상태를 표현하므로 `keep`/`remove`를 구분하지 못한다. ViewModel 도입 시 다음 중 하나로 확장:
> - **A. 별도 플래그**: `bool _imageRemoved` 추가.
> - **B. enum 상태**: `enum ImageDraft { keep, replace(XFile), remove }` (sealed class 또는 freezed union 권장).
>
> ViewModel로 옮기는 김에 sealed class로 깔끔하게 표현하는 것을 권장.

### 4. 이미지 업로드
- 파일명 규칙: `<userId>/<uuid>.jpg` (Supabase Storage `avatars` 버킷).
- `client.storage.from('avatars').upload(path, file)` → public URL `getPublicUrl(path)`.
- 업로드 성공 시 `profiles.avatar_url`에 해당 URL 저장.
- 실패 시 ViewModel에서 에러 → SnackBar.

### 5. 기존 이미지 삭제
- replace / remove 케이스에서, 기존 `avatar_url`이 있으면 Storage에서도 삭제 (orphan 방지).
- URL → path 변환은 정규식 또는 prefix strip으로 처리.
- 삭제 실패는 silent fail 허용 (사용자 경험 우선).

### 6. 수정하기 버튼 처리 (atomic)
1. 로딩 상태 진입 → 버튼 비활성 + 스피너 (UI 변경 필요 시 ui-implementor와 합의).
2. 이미지 변경 케이스에 따라 Storage 업로드 / 삭제.
3. profiles UPDATE (name + avatar_url).
4. 성공 → My 화면으로 pop + `ref.invalidate(profileViewModelProvider)`.
5. 실패 → SnackBar + 로딩 해제 (변경 사항은 그대로 유지).

### 7. 회원탈퇴
탈퇴는 보안상 클라이언트만으로는 완결할 수 없다 (auth.users 삭제는 service_role 필요).

#### 권장 흐름
1. 클라이언트: `profiles` row 삭제 (RLS로 본인 row만 삭제 가능).
   - `todos`는 `profiles` (또는 `auth.users`) cascade로 자동 삭제.
2. 클라이언트: Storage `avatars` 버킷에서 본인 폴더 (`<userId>/`) 삭제.
3. 클라이언트: **Supabase Edge Function**(`delete-account`)을 호출 → service_role 키로 `auth.admin.deleteUser(userId)` 수행.
4. 클라이언트: `signOut()` → router redirect로 `/login`.

> Edge Function 없이 진행해야 한다면 MVP에서는 **soft delete**(profiles에 `deleted_at` 컬럼 추가) + 로그아웃만 해도 된다. 단, 사용자가 같은 Google 계정으로 다시 로그인하면 데이터가 복구되므로 정책 결정 필요.

---

## 구현해야 할 파일

### `lib/shared/models/profile.dart`
```dart
class Profile {
  final String id;
  final String name;
  final String? avatarUrl;
  final DateTime createdAt;
  final DateTime updatedAt;

  const Profile({...});

  factory Profile.fromMap(Map<String, dynamic> map) { ... }
  Map<String, dynamic> toMap() { ... }
  Profile copyWith({...}) { ... }
}
```

### `lib/features/profile/repository/profile_repository.dart`
```dart
sealed class ImageDraft { const ImageDraft(); }
class KeepImage extends ImageDraft { const KeepImage(); }
class ReplaceImage extends ImageDraft {
  final XFile file;
  const ReplaceImage(this.file);
}
class RemoveImage extends ImageDraft { const RemoveImage(); }

abstract class ProfileRepository {
  Future<Profile> getCurrentProfile();

  /// 이름 + 이미지 변경 (atomic).
  Future<Profile> updateProfile({
    required String name,
    required ImageDraft image,
  });

  /// Storage 업로드. 성공 시 public URL 반환.
  Future<String> uploadAvatar(XFile file, {required String userId});

  /// Storage에서 기존 avatar 파일 삭제 (best-effort).
  Future<void> deleteAvatarFromStorage(String url);

  /// 회원탈퇴.
  Future<void> deleteAccount();
}

class SupabaseProfileRepository implements ProfileRepository { ... }
```

### `lib/features/profile/viewmodel/profile_view_model.dart`
```dart
@riverpod
class ProfileViewModel extends _$ProfileViewModel {
  @override
  Future<Profile> build() => ref.watch(profileRepositoryProvider).getCurrentProfile();

  Future<void> updateProfile({
    required String name,
    required ImageDraft image,
  }) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      return ref.read(profileRepositoryProvider).updateProfile(
        name: name,
        image: image,
      );
    });
  }

  Future<void> deleteAccount() async {
    await ref.read(profileRepositoryProvider).deleteAccount();
    // signOut은 AuthViewModel.signOut() 또는 Repository 내부에서.
    await ref.read(authViewModelProvider.notifier).signOut();
  }
}
```

### `lib/features/profile/view/my_screen.dart` 수정
- `StatefulWidget` → `ConsumerStatefulWidget`.
- `_userName`, `_profileImageUrl` 제거.
- `ref.watch(profileViewModelProvider)`로 `AsyncValue<Profile>` 구독:
  - `loading` → 헤더 영역에 placeholder (위젯 트리는 그대로, 데이터만 빈 값).
  - `error` → SnackBar.
  - `data` → `profile.name`, `profile.avatarUrl` 사용.
- 회원탈퇴 다이얼로그 "확인" 콜백:
  ```dart
  await ref.read(profileViewModelProvider.notifier).deleteAccount();
  // router redirect로 /login으로 자동 이동.
  ```
- 프로필 편집 버튼: `Navigator.push` 대신 `context.push('/profile/edit')` (go_router 도입 후).
- 위젯 트리, 색상, BottomNav 등 **레이아웃 변경 금지**.

### `lib/features/profile/view/edit_profile_screen.dart` 수정
- `StatefulWidget` → `ConsumerStatefulWidget`.
- `_initialName` 하드코딩 제거 → 진입 시 `ref.read(profileViewModelProvider).valueOrNull?.name`로 prefill.
- `_pickedImage` (XFile?) → `ImageDraft` 로컬 변수로 교체:
  ```dart
  ImageDraft _imageDraft = const KeepImage();
  ```
- `_onPickImage`: 성공 시 `_imageDraft = ReplaceImage(picked)`.
- `_onRemoveImage`: `_imageDraft = const RemoveImage()`.
- avatar 표시 로직:
  ```dart
  switch (_imageDraft) {
    KeepImage() => 기존 profile.avatarUrl 또는 default icon,
    ReplaceImage(file: final f) => FileImage(File(f.path)),
    RemoveImage() => default icon,
  }
  ```
- `_onSubmit`:
  ```dart
  await ref.read(profileViewModelProvider.notifier).updateProfile(
    name: _nameController.text.trim(),
    image: _imageDraft,
  );
  if (mounted) Navigator.of(context).pop();
  ```
- 위젯 트리, Stack, 카메라 버튼, BottomSheet 구조 등 **레이아웃 변경 금지**.

---

## Supabase 스키마 / Storage / Edge Function

### profiles 테이블
이미 `01_auth.md`에서 정의됨. 추가 컬럼 불필요.

### Storage 버킷 `avatars`
- Public bucket (read public, write owner).
- Storage policy:
  ```sql
  -- read: public
  create policy "avatars are publicly readable"
    on storage.objects for select
    using (bucket_id = 'avatars');

  -- write: 본인 폴더만
  create policy "users can upload their own avatar"
    on storage.objects for insert
    with check (
      bucket_id = 'avatars'
      and (storage.foldername(name))[1] = auth.uid()::text
    );

  create policy "users can update their own avatar"
    on storage.objects for update
    using (
      bucket_id = 'avatars'
      and (storage.foldername(name))[1] = auth.uid()::text
    );

  create policy "users can delete their own avatar"
    on storage.objects for delete
    using (
      bucket_id = 'avatars'
      and (storage.foldername(name))[1] = auth.uid()::text
    );
  ```

### Edge Function `delete-account`
```ts
// supabase/functions/delete-account/index.ts
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

Deno.serve(async (req) => {
  const authHeader = req.headers.get('Authorization')
  if (!authHeader) return new Response('Unauthorized', { status: 401 })

  const userClient = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_ANON_KEY')!,
    { global: { headers: { Authorization: authHeader } } },
  )
  const { data: { user } } = await userClient.auth.getUser()
  if (!user) return new Response('Unauthorized', { status: 401 })

  const adminClient = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
  )
  const { error } = await adminClient.auth.admin.deleteUser(user.id)
  if (error) return new Response(error.message, { status: 500 })
  return new Response('ok', { status: 200 })
})
```

클라이언트 호출:
```dart
await supabase.functions.invoke('delete-account');
```

---

## 체크리스트

- [ ] `shared/models/profile.dart` 생성
- [ ] `avatars` Storage bucket + policy 생성
- [ ] (선택) Edge Function `delete-account` 배포
- [ ] `profile_repository.dart` 작성 (`ImageDraft` sealed class 포함)
- [ ] `profile_view_model.dart` 작성
- [ ] `my_screen.dart`를 `ConsumerStatefulWidget`으로 변환 + 콜백 연결
  - [ ] 회원탈퇴 다이얼로그 "확인" 콜백 연결
  - [ ] 하드코딩 `_userName`, `_profileImageUrl` 제거
- [ ] `edit_profile_screen.dart`를 `ConsumerStatefulWidget`으로 변환
  - [ ] `_initialName` 하드코딩 제거 → ViewModel state로 prefill
  - [ ] `_pickedImage` → `ImageDraft` 로컬 상태로 교체
  - [ ] `_onSubmit`을 ViewModel.updateProfile 호출로 교체
- [ ] 수동 테스트:
  - [ ] 이름 변경 → My 화면에 즉시 반영
  - [ ] 이미지 업로드 → 새 URL 표시
  - [ ] 이미지 제거 → 기본 아이콘으로 복원 + Storage에서 파일 삭제
  - [ ] 수정 없이 화면 이탈 → 변경 미반영
  - [ ] 회원탈퇴 → /login으로 이동, 같은 계정 재로그인 시 신규 프로필
