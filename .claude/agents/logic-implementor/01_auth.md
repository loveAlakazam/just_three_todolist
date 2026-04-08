# 01. 로그인 / 인증 비즈니스 로직

## 작업 브랜치
`feature/login`

## 대상 View
- `lib/features/auth/view/login_screen.dart`

### 현재 상태 (UI 구현 완료, 로직 미연결)
- `LoginScreen`은 `StatelessWidget`이며, "Google로 로그인" 버튼만 표시한다.
- `_handleGoogleSignIn(BuildContext context)` 메서드는 비어 있고 주석에 다음과 같이 명시되어 있다:
  > TODO: ViewModel 연결 후 실제 로그인 처리로 교체. 로그인 실패 시 [SnackBar]로 에러 메시지 표시.

---

## 구현해야 할 비즈니스 로직

### 1. Google OAuth 로그인
- Supabase Auth의 `signInWithOAuth(OAuthProvider.google)` 사용.
- iOS / Android 모바일 환경 → `LaunchMode.externalApplication` 또는 deep link redirect.
- redirect URL은 Supabase 대시보드에 등록된 값과 일치해야 함 (예: `io.supabase.justthree://login-callback`).
- `flutter_dotenv`로 `.env`에서 Supabase URL / anon key 로드 (실제 초기화는 `05_app_bootstrap.md` 참조).

### 2. 첫 로그인 시 profiles row 생성
- 로그인 성공 직후 `profiles` 테이블을 조회.
- row가 없으면 신규 row를 생성한다:
  - `id` = `auth.user.id`
  - `name` = `user.userMetadata['full_name']` 또는 `user.email`의 local-part
  - `avatar_url` = `null` (Google avatar URL을 그대로 쓰지 않는다 — 사용자가 Edit Profile에서 별도 업로드)
  - `created_at`, `updated_at` = `now()`
- 이미 row가 있으면 그대로 둔다.

> 더 깔끔한 대안: Supabase의 **Database Trigger** (`auth.users` insert 시 `profiles` row 자동 생성)를 사용. 이 경우 클라이언트에서는 별도 처리 없이 바로 다음 단계로 넘어간다.

### 3. 세션 복원 / 자동 로그인 (영속화)

> **불변 규칙 (CR-3)**: 한 번 로그인하면 사용자가 명시적으로 로그아웃하지 않는 한, 앱을 완전히 종료/재실행해도 자동으로 로그인 상태가 복원되어야 한다.

- `supabase_flutter`는 로그인 성공 시 access token / refresh token을 **기기 로컬 저장소**(`SharedPreferences` 기반, iOS/Android 모두 OS 보안 영역)에 자동으로 저장한다. → 별도의 SecureStorage 연동 코드를 작성할 필요는 없다.
- 앱 시작 시 (`main.dart`):
  1. `WidgetsFlutterBinding.ensureInitialized()`
  2. `await Env.load()`
  3. `await SupabaseService.init()` — 이 호출이 끝나면 SDK가 디스크에서 세션을 읽어 메모리에 로드한다.
  4. `runApp(...)` — 이 시점에 `Supabase.instance.client.auth.currentSession`이 이미 채워져 있다.
- 세션이 있으면 → router redirect로 `/todo`, 없으면 → `/login` (CR-1과 동일 메커니즘).
- 세션 변화는 `client.auth.onAuthStateChange` stream으로 구독하고, `GoRouterRefreshStream`으로 router에 연결한다.
- refresh token 갱신은 SDK가 자동 처리 → 별도 timer / 수동 갱신 금지.
- **금지 사항**: 임의로 `auth.signOut()`을 호출하거나 로컬 저장소를 직접 비우지 말 것. 에러가 발생해도 세션을 지우지 않는다 (네트워크 일시 장애로 사용자가 강제 로그아웃되는 것을 방지). 세션 제거는 오직 §5 (사용자가 My 화면에서 호출) 또는 회원탈퇴 한 군데서만 발생한다.

### 4. 로그인 후 라우팅
- 로그인 성공 → go_router로 `/todo`(또는 `/calendar`) replace.
- 라우팅은 ViewModel이 직접 호출하지 않는다. 대신 ViewModel의 상태(`isAuthenticated`)를 go_router의 `redirect` 함수에서 감시 → 자동 이동.

### 5. 로그아웃 (My 화면에서 호출)
- `client.auth.signOut()` 호출.
- onAuthStateChange가 `SIGNED_OUT` 이벤트 발행 → router redirect로 `/login`으로 이동.

### 6. 에러 처리
- OAuth 취소 (`AuthException` with code `user_cancelled`) → 조용히 무시.
- 그 외 에러 → SnackBar로 "로그인에 실패했습니다. 다시 시도해주세요."

---

## 구현해야 할 파일

### `lib/features/auth/repository/auth_repository.dart`
```dart
abstract class AuthRepository {
  /// 현재 세션이 있는지 여부 (앱 시작 시 사용).
  Session? get currentSession;

  /// 인증 상태 변화 stream. router redirect에서 구독.
  Stream<AuthState> get authStateChanges;

  /// Google OAuth 로그인. 성공 시 세션은 SDK가 자동 저장.
  /// 실패 시 [AuthFailure] throw.
  Future<void> signInWithGoogle();

  /// 로그아웃.
  Future<void> signOut();

  /// 첫 로그인 시 profiles row 생성 (있으면 no-op).
  /// DB trigger로 처리한다면 이 메서드는 생략 가능.
  Future<void> ensureProfileExists();
}

class SupabaseAuthRepository implements AuthRepository { ... }

class AuthFailure implements Exception {
  final String message;
  final Object? cause;
  const AuthFailure(this.message, [this.cause]);
}
```

### `lib/features/auth/viewmodel/auth_view_model.dart`
```dart
@riverpod
class AuthViewModel extends _$AuthViewModel {
  @override
  AsyncValue<User?> build() {
    final repo = ref.watch(authRepositoryProvider);
    // authStateChanges 구독 → state 업데이트
    final sub = repo.authStateChanges.listen((authState) {
      state = AsyncData(authState.session?.user);
    });
    ref.onDispose(sub.cancel);
    return AsyncData(repo.currentSession?.user);
  }

  Future<void> signInWithGoogle() async {
    state = const AsyncLoading();
    try {
      await ref.read(authRepositoryProvider).signInWithGoogle();
      await ref.read(authRepositoryProvider).ensureProfileExists();
    } on AuthFailure catch (e, st) {
      state = AsyncError(e, st);
    }
  }

  Future<void> signOut() async {
    await ref.read(authRepositoryProvider).signOut();
  }
}
```

### `lib/features/auth/view/login_screen.dart` 수정
- `StatelessWidget` → `ConsumerWidget`.
- `_handleGoogleSignIn`을 `ref.read(authViewModelProvider.notifier).signInWithGoogle()` 호출로 교체.
- `ref.listen(authViewModelProvider, ...)`로 에러 구독 → SnackBar 표시.
- 위젯 트리 / 색상 / 패딩 / 버튼 스타일은 절대 변경하지 않는다.

---

## Supabase 스키마

### `profiles` 테이블
```sql
create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  name text not null,
  avatar_url text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.profiles enable row level security;

create policy "profiles are viewable by owner"
  on public.profiles for select
  using (auth.uid() = id);

create policy "profiles can be updated by owner"
  on public.profiles for update
  using (auth.uid() = id);

create policy "profiles can be inserted by owner"
  on public.profiles for insert
  with check (auth.uid() = id);
```

### (선택) auth.users insert trigger
```sql
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  insert into public.profiles (id, name)
  values (
    new.id,
    coalesce(
      new.raw_user_meta_data->>'full_name',
      split_part(new.email, '@', 1)
    )
  );
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();
```

---

## Supabase 대시보드 / 환경 설정

### Supabase 대시보드
1. **Authentication > Providers > Google** 활성화.
   - Google Cloud Console에서 OAuth 2.0 Client ID 발급 (iOS / Web 각각).
   - Authorized redirect URI: `https://<project-ref>.supabase.co/auth/v1/callback`.
2. **Authentication > URL Configuration**
   - Additional Redirect URLs에 `io.supabase.justthree://login-callback` 등록 (deep link).

### iOS
- `ios/Runner/Info.plist`에 URL Scheme 등록:
  ```xml
  <key>CFBundleURLTypes</key>
  <array>
    <dict>
      <key>CFBundleURLSchemes</key>
      <array>
        <string>io.supabase.justthree</string>
      </array>
    </dict>
  </array>
  ```

### Android
- `android/app/src/main/AndroidManifest.xml`의 `MainActivity`에 intent-filter 추가:
  ```xml
  <intent-filter>
    <action android:name="android.intent.action.VIEW"/>
    <category android:name="android.intent.category.DEFAULT"/>
    <category android:name="android.intent.category.BROWSABLE"/>
    <data android:scheme="io.supabase.justthree" android:host="login-callback"/>
  </intent-filter>
  ```

---

## 체크리스트

- [ ] `flutter pub add supabase_flutter flutter_riverpod go_router flutter_dotenv`
- [ ] `.env` 작성 + `.gitignore` 등록
- [ ] `core/supabase_client.dart` 초기화 (`05_app_bootstrap.md`)
- [ ] `core/router.dart`에 auth redirect 추가 (`05_app_bootstrap.md`)
- [ ] iOS / Android deep link 설정
- [ ] Supabase 대시보드 Google provider 활성화
- [ ] `profiles` 테이블 + RLS 생성
- [ ] (옵션) `handle_new_user` trigger 생성
- [ ] `auth_repository.dart` + `auth_view_model.dart` 작성
- [ ] `login_screen.dart`를 `ConsumerWidget`으로 변환 + 콜백 연결
- [ ] 수동 테스트: 로그인 → 자동 라우팅 → 앱 재시작 시 세션 복원 → 로그아웃
