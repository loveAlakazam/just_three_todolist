# 04. 마이페이지 / 프로필 편집 비즈니스 로직

## 작업 브랜치 (git-flow)

- 브랜치: `feature/my-page`
- **`develop`에서 분기**하여 생성한다 (`main`에서 분기 금지):
  ```bash
  git checkout develop && git pull origin develop
  git checkout -b feature/my-page
  ```
- PR base 브랜치는 **`develop`**. 릴리즈는 `/release` 커맨드가 별도로 처리한다.
- 자세한 규칙은 `.claude/rules/git-flow.md` 및 `00_overview.md` §7 참조.

## 대상 View
- `lib/features/profile/view/my_screen.dart`
- `lib/features/profile/view/edit_profile_screen.dart`

## 사전 가드 (00_overview.md 핵심 제약)

- **CR-1 (인증 가드)**: `/my`, `/my/edit`는 로그인 회원 전용. 비로그인 차단은 router redirect가 책임지며, View / ViewModel에서 별도 분기 금지.
- **CR-2 (탭 상태 유지)**: `/my`는 BottomNav 탭이므로 `StatefulShellRoute`의 `IndexedStack`에 들어 있어야 하고, 다른 탭 갔다가 돌아와도 `ProfileViewModel` 캐시가 유지되어 다시 로딩이 발생하지 않아야 한다. `/my/edit`는 shell 위에 push되는 라우트이며, 닫고 돌아오면 `/my` 상태 그대로 복귀.
- **CR-3 (세션 영속화) & 로그아웃**: 로그아웃 / 회원탈퇴는 **이 화면에서만 트리거되는 유일한 세션 제거 경로**이다. 다른 어떤 화면/ViewModel도 임의로 `auth.signOut()`을 호출해서는 안 된다. 호출 직후 router redirect가 자동으로 `/login`으로 이동한다.

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
- 파일명 규칙: `<userId>/<uuid>.jpg` (Supabase Storage `profile-images` 버킷).
- `client.storage.from('profile-images').upload(path, file)` → signed URL `createSignedUrl(path, 3600)`.
- 업로드 성공 시 `profiles.avatar_url`에 Storage 경로(path)를 저장. 표시 시 signed URL을 생성.
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

#### 정책

- 사용자가 My 화면 → "회원탈퇴" → 다이얼로그 "확인"을 탭하면 즉시 탈퇴가 진행된다.
- 탈퇴 성공 시 **로그인 화면(`/login`)으로 리다이렉트**된다. View가 직접 push하지 않고, `signOut()` 후 router의 전역 redirect (CR-1)가 자동으로 `/login`으로 이동시킨다.
- **재가입 쿨다운 (14일)**: 탈퇴된 회원은 **탈퇴 시점으로부터 14일이 지나야 같은 Google 계정으로 재가입할 수 있다.** 14일 이내 재로그인 시도는 OAuth 자체는 성공하더라도 클라이언트에서 즉시 차단되며, 사용자는 로그인 화면에 머무른다.

#### 탈퇴 흐름 (My 화면 → 확인 시)

1. 클라이언트: Storage `profile-images` 버킷에서 본인 폴더 (`<userId>/`) 삭제 (best-effort, 실패해도 진행).
2. 클라이언트: `profiles` row 삭제 (RLS로 본인 row만 삭제 가능).
   - `todos`는 `auth.users` cascade로 4단계에서 함께 삭제됨.
3. 클라이언트: **Supabase Edge Function `delete-account`** 호출 (Authorization 헤더로 현재 사용자 JWT 전달).
   - Edge Function 내부에서 다음을 atomic하게 수행:
     - 현재 사용자 정보(`id`, `email`, `identities[].provider`, `identities[].provider_id`) 조회.
     - `deleted_accounts` 테이블에 row 삽입 (`email`, `provider`, `provider_user_id`, `deleted_at = now()`).
     - `auth.admin.deleteUser(userId)` 호출 → `auth.users` 삭제 → `todos` cascade 삭제.
4. 클라이언트: `auth.signOut()` → `authStateChanges`가 `SIGNED_OUT` 발행 → router redirect → `/login`.
5. View(`my_screen.dart`): 다이얼로그를 `Navigator.of(context).pop()`으로 닫기만 한다. 라우팅은 redirect가 처리.

> 단계 3이 실패하면 사용자 데이터(profiles/storage)는 이미 일부 삭제된 상태가 된다. ViewModel은 이 경우 SnackBar로 "탈퇴에 실패했습니다. 잠시 후 다시 시도해주세요." 안내 후 로딩 해제. 사용자가 다시 시도하면 step 1/2는 idempotent(이미 없는 row 삭제는 no-op)하므로 안전하게 재시도 가능.

#### 부분 실패 / 재시도 안전성 (구현 계약)

> 탈퇴 흐름은 단계가 여러 개라 어느 단계에서든 실패할 수 있다. 다음 계약을 모두 만족해야 UI 측(`04_mypage.md`)이 "재시도 가능 + 화면 깨지지 않음"을 신뢰하고 단순한 SnackBar 처리만으로 끝낼 수 있다.

1. **모든 정리 단계는 idempotent**.
   - Storage 폴더 삭제: 이미 비어 있어도 throw하지 않는다 (best-effort, 404 silent).
   - `profiles` row 삭제: `delete().eq('id', uid)` 자체가 row 0개 삭제도 정상 응답.
   - `deleted_accounts` insert: 같은 user_id로 중복 row가 들어와도 에러나지 않게 unique 제약을 걸지 않는다 (가장 최근 row만 보면 되므로 누적되어도 무해).
   - `auth.admin.deleteUser`: 이미 존재하지 않는 user에 대해 호출되면 Edge Function이 200으로 swallow (또는 "이미 삭제됨"으로 간주하고 통과).

2. **부분 실패 후 fallback — `ProfileViewModel.build()`의 회복력**.
   - 탈퇴 도중 단계 2가 성공하고 단계 3이 실패하면 `profiles` row가 사라진 상태로 사용자가 여전히 로그인 상태가 된다.
   - 이때 사용자가 (a) 다른 탭으로 갔다가 My 탭으로 돌아오거나 (b) 회원탈퇴를 재시도하기 전에 화면을 다시 보면, `ProfileViewModel.build()`가 호출되어 `getCurrentProfile()`을 부른다.
   - `ProfileRepository.getCurrentProfile()`는 row가 없을 때 throw하지 않고 다음 중 하나를 수행:
     - **권장**: `ensureProfileExists()`와 동일한 로직으로 빈 row를 즉시 재생성한 뒤 반환. (auth.users는 살아 있으므로 RLS 통과.)
     - 또는 `Profile` 모델의 placeholder를 반환 (id = uid, name = email local-part, avatarUrl = null) — 단, 이 경우 다음 화면 로드 시 다시 깜빡일 수 있어 권장하지 않음.
   - 이 fallback 덕분에 UI는 `AsyncValue.error`를 받을 일이 거의 없고, View에 별도 분기 처리가 필요하지 않다.

3. **재시도 트리거 — UI 측 책임 분리**.
   - logic은 `deleteAccount()` 한 번 호출 = 한 번의 시도로 정의한다. 자동 retry / exponential backoff 없음 (사용자 의사 확인 없이 반복 호출은 부작용 위험).
   - 재시도는 사용자가 다시 "회원탈퇴" 버튼을 탭할 때만 일어난다 — UI 측에서 SnackBar 표시 후 별도 자동 재시도 금지.

4. **로딩/완료 상태 신호**.
   - `ProfileViewModel.deleteAccount()`는 시작 시 `state = AsyncLoading()`, 성공 시 `signOut()`을 통해 router가 자동 이동, 실패 시 fallback으로 state를 복구한 뒤 `Error.throwWithStackTrace`로 rethrow → View의 try/catch에서 SnackBar 표시.
   - View는 ViewModel의 `state.isLoading`을 직접 watch하지 않고, 다이얼로그 내부 로컬 `isDeleting` 플래그로 버튼/스피너를 제어한다 (다이얼로그 lifecycle을 ViewModel에 결합시키지 않기 위함).

#### 14일 쿨다운 강제 흐름 (로그인 시)

> 이 강제 로직은 `01_auth.md`의 로그인 흐름과 함께 구현된다. 본 문서에서는 정책과 데이터 모델만 정의한다.

- `signInWithOAuth(OAuthProvider.google)` 성공 직후, **`ensureProfileExists` 호출 전에** 클라이언트는 RPC `check_signin_cooldown()`을 호출한다.
- RPC는 현재 인증된 사용자의 `auth.email()` 또는 OAuth identity (`provider + provider_user_id`)를 키로 `deleted_accounts`에서 가장 최근 row를 조회한다.
- 결과:
  - `now() < deleted_at + interval '14 days'` → 쿨다운 활성. RPC는 `{ blocked: true, until: <timestamp>, remaining_days: N }` 반환.
  - 그 외 → `{ blocked: false }`.
- 쿨다운 활성이면 클라이언트는:
  1. 즉시 `auth.signOut()` 호출 (방금 만들어진 세션 제거).
  2. `CooldownException(remainingDays)` throw → ViewModel에서 catch하여 SnackBar 표시: "탈퇴 후 14일이 지나지 않은 계정입니다. (D-{remainingDays} 남음)"
  3. router redirect는 `signOut()` 결과로 자동으로 `/login`을 유지.
- 쿨다운 비활성이면 평소대로 `ensureProfileExists` → `/todo`.

#### 쿨다운 데이터 정리 (선택, 운영)

- `deleted_accounts`의 row는 14일이 지나면 더 이상 사용되지 않는다. 즉시 삭제하지 않고 90일 정도 보관 후 정리(통계/감사 목적). 정리는 Supabase Scheduled Function 또는 수동 SQL로 수행. MVP 단계에서는 누적되어도 무해하므로 별도 정리 작업 없음.

> "왜 14일인가?" — 충동적 탈퇴 후 즉시 재가입을 막아 데이터 잔여물 정리 / 어뷰징 방지 목적. 정책 변경 시 이 명세와 `01_auth.md` 양쪽을 함께 갱신할 것.

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
  /// 현재 사용자의 profile 조회.
  ///
  /// row가 존재하지 않으면 (탈퇴 부분 실패 등) 즉시 빈 row를 재생성한 뒤 반환한다.
  /// View가 fallback 분기를 가질 필요가 없도록, 이 메서드는 가능한 한 throw하지 않는다.
  /// 진짜 네트워크/권한 오류만 [ProfileFailure]로 rethrow.
  Future<Profile> getCurrentProfile();

  /// 이름 + 이미지 변경 (atomic).
  Future<Profile> updateProfile({
    required String name,
    required ImageDraft image,
  });

  /// Storage 업로드. 성공 시 Storage 경로(path) 반환.
  Future<String> uploadAvatar(XFile file, {required String userId});

  /// Storage에서 기존 avatar 파일 삭제 (best-effort).
  Future<void> deleteAvatarFromStorage(String url);

  /// 회원탈퇴.
  ///
  /// 다음을 atomic하게 수행한다:
  /// 1) Storage `profile-images/<userId>/` 폴더 정리 (best-effort)
  /// 2) `profiles` row 삭제
  /// 3) Edge Function `delete-account` 호출 (deleted_accounts 기록 + auth.users 삭제)
  ///
  /// signOut은 호출하지 않는다 — 호출 측(ViewModel)에서 처리.
  /// 실패 시 [AccountDeletionFailure] throw.
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
    state = const AsyncLoading();
    try {
      await ref.read(profileRepositoryProvider).deleteAccount();
      // 탈퇴 성공 → signOut으로 세션 제거.
      // authStateChanges가 SIGNED_OUT 발행 → router redirect로 자동 /login 이동.
      // View는 다이얼로그 pop만 하면 된다.
      await ref.read(authViewModelProvider.notifier).signOut();
    } catch (e, st) {
      // 실패 시 기존 profile 상태로 복구 후 rethrow → View에서 SnackBar 표시.
      state = await AsyncValue.guard(
        () => ref.read(profileRepositoryProvider).getCurrentProfile(),
      );
      Error.throwWithStackTrace(e, st);
    }
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
  Future<void> _onConfirmDelete() async {
    try {
      await ref.read(profileViewModelProvider.notifier).deleteAccount();
      // 성공: 다이얼로그만 닫고 끝낸다.
      // router redirect가 SIGNED_OUT 이벤트를 받아 자동으로 /login으로 이동시키므로,
      // 여기서 context.go('/login') 같은 호출은 절대 하지 않는다 (이중 navigation 방지).
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (mounted) Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('탈퇴에 실패했습니다. 잠시 후 다시 시도해주세요.')),
      );
    }
  }
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

### Storage 버킷 `profile-images`
- Private bucket (signed URL로 접근, owner read/write).
- Storage policy:
  ```sql
  -- read: 본인 폴더만
  create policy "users can read their own avatar"
    on storage.objects for select
    using (
      bucket_id = 'profile-images'
      and (storage.foldername(name))[1] = auth.uid()::text
    );

  -- write: 본인 폴더만
  create policy "users can upload their own avatar"
    on storage.objects for insert
    with check (
      bucket_id = 'profile-images'
      and (storage.foldername(name))[1] = auth.uid()::text
    );

  create policy "users can update their own avatar"
    on storage.objects for update
    using (
      bucket_id = 'profile-images'
      and (storage.foldername(name))[1] = auth.uid()::text
    );

  create policy "users can delete their own avatar"
    on storage.objects for delete
    using (
      bucket_id = 'profile-images'
      and (storage.foldername(name))[1] = auth.uid()::text
    );
  ```

### `deleted_accounts` 테이블 (재가입 쿨다운)

> 14일 쿨다운 정책을 강제하기 위한 별도 테이블. **`auth.users`를 참조하지 않는다** — 탈퇴 시 `auth.users` row가 삭제되므로 FK가 dangling되기 때문. 이메일 / OAuth identity를 plain column으로 저장한다.

| 컬럼 | 타입 | 제약 | 설명 |
|------|------|------|------|
| `id` | `uuid` | PK, default `gen_random_uuid()` | 레코드 고유 ID |
| `email` | `text` | nullable | 탈퇴 시점의 이메일 (소문자 정규화) |
| `provider` | `text` | NOT NULL | OAuth 제공자 (`'google'` 등) |
| `provider_user_id` | `text` | NOT NULL | OAuth 제공자의 사용자 식별자 (Google sub 등) |
| `deleted_at` | `timestamptz` | NOT NULL, default `now()` | 탈퇴 시각 |
| `reactivation_at` | `timestamptz` | generated always as (`deleted_at + 14 days`) stored | 재가입 가능 시점 (자동 계산) |

- 인덱스: `(email, deleted_at desc)` + `(provider, provider_user_id, deleted_at desc)`
- RLS 활성화 + 정책 없음 → 일반 사용자 접근 완전 차단. `service_role` / `security definer` RPC만 접근

```sql
create table public.deleted_accounts (
  id            uuid primary key default gen_random_uuid(),
  email         text,                              -- 탈퇴 시점의 이메일 (소문자 정규화 권장)
  provider      text not null,                     -- 'google' 등
  provider_user_id text not null,                  -- Google sub 등
  deleted_at    timestamptz not null default now(),
  reactivation_at timestamptz generated always as (deleted_at + interval '14 days') stored
);

create index idx_deleted_accounts_email_recent
  on public.deleted_accounts (email, deleted_at desc);
create index idx_deleted_accounts_provider_recent
  on public.deleted_accounts (provider, provider_user_id, deleted_at desc);

-- 일반 사용자에게는 직접 조회/조작 권한을 주지 않는다.
alter table public.deleted_accounts enable row level security;
-- (정책 없음 = 모든 일반 사용자 접근 차단. service_role / security definer RPC만 접근.)
```

### RPC `check_signin_cooldown` (security definer)

로그인 직후 클라이언트가 호출. 현재 인증된 사용자의 이메일/OAuth identity를 기준으로 쿨다운 중인지 판단.

```sql
create or replace function public.check_signin_cooldown()
returns table(blocked boolean, until timestamptz, remaining_days int)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_email text;
  v_provider text;
  v_provider_uid text;
  v_row deleted_accounts%rowtype;
begin
  -- 현재 사용자 식별. auth.jwt()에서 email + provider identity를 추출.
  v_email := lower(auth.jwt() ->> 'email');
  v_provider := coalesce(auth.jwt() -> 'app_metadata' ->> 'provider', '');
  v_provider_uid := coalesce(auth.jwt() -> 'user_metadata' ->> 'provider_id', '');

  select *
    into v_row
    from deleted_accounts
   where (email = v_email)
      or (provider = v_provider and provider_user_id = v_provider_uid)
   order by deleted_at desc
   limit 1;

  if not found or v_row.reactivation_at <= now() then
    return query select false, null::timestamptz, 0;
    return;
  end if;

  return query
    select true,
           v_row.reactivation_at,
           greatest(0, ceil(extract(epoch from (v_row.reactivation_at - now())) / 86400)::int);
end;
$$;

revoke all on function public.check_signin_cooldown() from public;
grant execute on function public.check_signin_cooldown() to authenticated;
```

> `auth.jwt()`에서 provider identity를 가져오는 키는 Supabase 버전에 따라 다를 수 있다. 구현 시점에 실제 토큰을 dump해 정확한 키를 확인할 것 (`provider_id`, `sub`, `identities[0].id` 등). 이메일 단독 매칭만으로도 1차 차단은 충분하지만, 사용자가 Google 계정 이메일을 변경한 경우를 대비해 provider_id 매칭을 함께 둔다.

### Edge Function `delete-account`

탈퇴 시 `deleted_accounts`에 쿨다운 row를 기록한 뒤 `auth.users`를 삭제한다.

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
  const { data: { user }, error: userErr } = await userClient.auth.getUser()
  if (userErr || !user) return new Response('Unauthorized', { status: 401 })

  const adminClient = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
  )

  // 1) identities에서 google provider 정보를 추출.
  //    (회원가입을 Google OAuth로만 받기 때문에 identities[0]이 google이라고 가정.)
  const identity = (user.identities ?? [])[0]
  const provider = identity?.provider ?? 'unknown'
  const providerUserId = identity?.id ?? identity?.identity_data?.sub ?? user.id
  const email = (user.email ?? '').toLowerCase()

  // 2) 쿨다운 기록 (auth.users 삭제 전에 먼저 INSERT — 실패 시 삭제 중단).
  const { error: insertErr } = await adminClient
    .from('deleted_accounts')
    .insert({
      email,
      provider,
      provider_user_id: providerUserId,
    })
  if (insertErr) {
    return new Response(`failed to record cooldown: ${insertErr.message}`, { status: 500 })
  }

  // 3) auth.users 삭제 → todos cascade 삭제.
  const { error: deleteErr } = await adminClient.auth.admin.deleteUser(user.id)
  if (deleteErr) {
    return new Response(deleteErr.message, { status: 500 })
  }

  return new Response(JSON.stringify({ ok: true }), {
    status: 200,
    headers: { 'content-type': 'application/json' },
  })
})
```

클라이언트 호출:
```dart
await supabase.functions.invoke('delete-account');
```

> Edge Function 환경이 준비되지 않았다면 MVP 임시 대안으로 **soft delete**를 사용할 수 있다. 단, 이 경우에도 14일 쿨다운 정책은 동일하게 강제해야 하므로 `deleted_accounts` 기록 + `check_signin_cooldown` 호출은 반드시 같이 도입한다.

---

## 체크리스트

- [ ] `shared/models/profile.dart` 생성
- [ ] `profile-images` Storage bucket + policy 생성
- [ ] **`deleted_accounts` 테이블 + index + RLS 생성** (14일 쿨다운)
- [ ] **RPC `check_signin_cooldown` 생성** (security definer, authenticated execute)
- [ ] **Edge Function `delete-account` 배포** (`deleted_accounts` insert + `auth.admin.deleteUser`)
- [ ] `01_auth.md` 흐름에 `check_signin_cooldown` 호출 연결 (로그인 직후, `ensureProfileExists` 이전)
- [ ] `profile_repository.dart` 작성 (`ImageDraft` sealed class + `deleteAccount` 포함)
- [ ] `profile_view_model.dart` 작성 (`deleteAccount` 내부에서 `signOut` 호출까지)
- [ ] `my_screen.dart`를 `ConsumerStatefulWidget`으로 변환 + 콜백 연결
  - [ ] 회원탈퇴 다이얼로그 "확인" → `_onConfirmDelete` (성공 시 다이얼로그 pop만, 라우팅은 redirect에 위임)
  - [ ] 다이얼로그 본문에 "탈퇴 후 14일 동안 재가입 불가" 안내 추가
  - [ ] 다이얼로그 `barrierDismissible: false` + 로딩 중 "취소"/"확인" 비활성 + 중복 클릭 가드
  - [ ] `getCurrentProfile()`이 row 미존재 시 빈 row 재생성 fallback 동작 (부분 실패 회복)
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
  - [ ] 회원탈퇴 "확인" → 다이얼로그 닫힘 → `/login`으로 자동 이동
  - [ ] 탈퇴 직후 같은 Google 계정으로 재로그인 시도 → SnackBar "탈퇴 후 14일이 지나지 않은 계정입니다. (D-14 남음)" + 로그인 화면 유지
  - [ ] `deleted_accounts.deleted_at`을 `now() - interval '15 days'`로 수동 변경 후 재로그인 → 정상 가입 (신규 프로필)
  - [ ] 탈퇴 시 `todos`도 cascade 삭제되어 재가입 후 빈 상태로 시작하는지 확인
  - [ ] **부분 실패 시뮬레이션**: 비행기 모드 ON → "확인" 탭 → SnackBar 표시 → 비행기 모드 OFF → 다시 "확인" 탭 → 정상 탈퇴 완료 (재시도 idempotency 검증)
  - [ ] **부분 실패 후 화면 진입**: 비행기 모드로 탈퇴 실패 → 다른 탭(Todo) 갔다가 My 탭 복귀 시 화면이 깨지지 않고 빈 프로필이 표시되는지 확인 (`getCurrentProfile` fallback)
  - [ ] **로딩 중 다이얼로그 닫기 차단**: "확인" 탭 직후 다이얼로그 바깥 영역 탭 → 닫히지 않음, "취소" 버튼 비활성
