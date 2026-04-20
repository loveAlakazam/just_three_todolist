# 01. 로그인 / 인증 비즈니스 로직

## 작업 브랜치 (git-flow)

- 브랜치: `feature/login`
- **`develop`에서 분기**하여 생성한다 (`main`에서 분기 금지):
  ```bash
  git checkout develop && git pull origin develop
  git checkout -b feature/login
  ```
- PR base 브랜치는 **`develop`**. 릴리즈는 `/release` 커맨드가 별도로 처리한다.
- 자세한 규칙은 `.claude/rules/git-flow.md` 및 `00_overview.md` §7 참조.

## 대상 View
- `lib/features/auth/view/login_screen.dart`

### 현재 상태 (UI 구현 완료, 로직 미연결)
- `LoginScreen`은 `StatelessWidget`이며, "Google로 로그인" 버튼만 표시한다.
- `_handleGoogleSignIn(BuildContext context)` 메서드는 비어 있고 주석에 다음과 같이 명시되어 있다:
  > TODO: ViewModel 연결 후 실제 로그인 처리로 교체. 로그인 실패 시 [SnackBar]로 에러 메시지 표시.

---

## 구현해야 할 비즈니스 로직

### 1. Google 로그인 (네이티브 방식)

Supabase의 **브라우저 기반 `signInWithOAuth`는 사용하지 않는다.** 모바일 UX / 설정 단순화 / `redirect_uri_mismatch` 리스크 제거를 위해 **네이티브 Google Sign-In SDK → idToken → Supabase `signInWithIdToken`** 흐름을 사용한다.

#### 흐름

```
앱 → google_sign_in SDK가 OS 네이티브 시트 표시 → 사용자 인증
  → SDK가 idToken/accessToken 반환
  → supabase.auth.signInWithIdToken(provider: google, idToken, accessToken)
  → Supabase가 idToken 서명 검증 → 세션 발급 → SDK가 로컬에 자동 저장
```

- **redirect URL 불필요**: 브라우저를 거치지 않으므로 deep link / callback URL 설정이 전혀 필요 없다.
- **세션 영속화**: Supabase SDK가 기존과 동일하게 access / refresh token을 기기 로컬 저장소에 저장한다 (CR-3 유지).

#### 사용 패키지

- `google_sign_in` (pub.dev 공식, `^6.2.0`).

#### 필수 환경 변수 (`.env`)

| 키 | 설명 | 비고 |
|---|---|---|
| `GOOGLE_OAUTH_IOS_CLIENT_ID` | Google Cloud Console의 **iOS** OAuth 2.0 Client ID | `GoogleSignIn(clientId: ...)`에 전달. iOS 전용. |
| `GOOGLE_OAUTH_WEB_CLIENT_ID` | Google Cloud Console의 **Web application** OAuth 2.0 Client ID | `GoogleSignIn(serverClientId: ...)`에 전달. Supabase가 idToken 검증에 사용하는 audience와 반드시 일치해야 한다. |
| `GOOGLE_OAUTH_ANDROID_CLIENT_ID` | Google Cloud Console의 **Android** OAuth 2.0 Client ID | 문서화 목적으로만 `.env`에 둔다. `google_sign_in` 패키지는 Android 클라이언트 ID를 코드로 전달받지 않고, SHA-1 지문 + 패키지명으로 Google Cloud가 자동 매칭한다. |
| `SUPABASE_URL`, `SUPABASE_ANON_KEY` | Supabase 프로젝트 | 기존과 동일 |

`Env` 클래스에 `googleOAuthIosClientId` / `googleOAuthWebClientId` getter를 추가한다. Android 클라이언트 ID는 코드에서 참조하지 않으므로 getter는 만들지 않는다.

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
- 세션 변화는 `AuthViewModel` 이 `client.auth.onAuthStateChange` stream 으로 구독해 `state`(`AsyncValue<User?>`) 에 반영한다. Router 는 raw Supabase stream 대신 **이 `authViewModelProvider` 자체를 `refreshListenable` 로 구독**한다 — stream 에 두 구독자(router / ViewModel) 가 동시에 붙었을 때 리스너 호출 순서에 따라 router 가 아직 갱신되지 않은 ViewModel state 를 읽어버리는 race (로그인 성공 직후 `/splash` 에 고착) 를 차단하기 위함.
- refresh token 갱신은 SDK가 자동 처리 → 별도 timer / 수동 갱신 금지.
- **금지 사항**: 임의로 `auth.signOut()`을 호출하거나 로컬 저장소를 직접 비우지 말 것. 에러가 발생해도 세션을 지우지 않는다 (네트워크 일시 장애로 사용자가 강제 로그아웃되는 것을 방지). 세션 제거는 오직 §5 (사용자가 My 화면에서 호출) 또는 회원탈퇴 한 군데서만 발생한다.

### 4. 로그인 후 라우팅
- 로그인 성공 → go_router로 `/todo`(또는 `/calendar`) replace.
- 라우팅은 ViewModel이 직접 호출하지 않는다. 대신 ViewModel의 상태(`isAuthenticated`)를 go_router의 `redirect` 함수에서 감시 → 자동 이동.

### 5. 로그아웃 (My 화면에서 호출)
- `client.auth.signOut()` 호출.
- **그 직후 `GoogleSignIn.signOut()`도 호출**하여 네이티브 Google 세션(캐시된 계정 선택 상태)도 함께 정리한다. 누락 시 다음 로그인에서 계정 선택 없이 기존 계정으로 자동 재로그인될 수 있다.
- onAuthStateChange가 `SIGNED_OUT` 이벤트 발행 → router redirect로 `/login`으로 이동.

### 6. 에러 처리
- **사용자 취소**: `GoogleSignIn.signIn()`이 `null`을 반환한다 (예외 아님). Repository에서 `AuthFailure('Google 로그인이 취소되었습니다.')`로 감싸 throw → View는 "취소" 문자열 포함 여부로 SnackBar 억제 (기존 로직 유지).
- **idToken 누락**: `googleUser.authentication`에서 `idToken`이 null인 경우(서버 클라이언트 ID 미설정 등 설정 오류) → `AuthFailure('로그인 토큰을 가져오지 못했습니다.')`.
- **Supabase 검증 실패** (`AuthException`): idToken 서명 / audience 불일치 등. → `AuthFailure('로그인에 실패했습니다.', e)`.
- **그 외 예외**: 네트워크 장애 등. → `AuthFailure('로그인에 실패했습니다.', e)`.
- View: `AsyncError`로 전이되면 SnackBar "로그인에 실패했습니다. 다시 시도해주세요." (취소 메시지는 제외).

---

## 구현해야 할 파일

### `lib/features/auth/repository/auth_repository.dart`

- `profiles` row 생성은 Supabase `handle_new_user` DB trigger가 처리하므로 `ensureProfileExists()`는 **정의하지 않는다**.
- `GoogleSignIn` 인스턴스는 Repository 생성 시 1회 초기화하고 `signOut` 시 재사용한다.

```dart
abstract class AuthRepository {
  /// 현재 세션이 있는지 여부 (앱 시작 시 사용).
  Session? get currentSession;

  /// 인증 상태 변화 stream. router redirect에서 구독.
  Stream<AuthState> get authStateChanges;

  /// 네이티브 Google Sign-In → Supabase `signInWithIdToken`.
  /// 사용자 취소 / idToken 누락 / Supabase 검증 실패 시 [AuthFailure] throw.
  /// 성공 시 세션은 supabase_flutter가 자동 저장한다.
  Future<void> signInWithGoogle();

  /// Supabase + Google 네이티브 세션 모두 로그아웃.
  Future<void> signOut();
}

class SupabaseAuthRepository implements AuthRepository {
  SupabaseAuthRepository()
      : _googleSignIn = GoogleSignIn(
          clientId: Env.googleOAuthIosClientId,
          serverClientId: Env.googleOAuthWebClientId,
        );

  final SupabaseClient _client = SupabaseService.client;
  final GoogleSignIn _googleSignIn;

  @override
  Future<void> signInWithGoogle() async {
    try {
      final googleUser = await _googleSignIn.signIn();
      if (googleUser == null) {
        throw const AuthFailure('Google 로그인이 취소되었습니다.');
      }

      final googleAuth = await googleUser.authentication;
      final idToken = googleAuth.idToken;
      if (idToken == null) {
        throw const AuthFailure('로그인 토큰을 가져오지 못했습니다.');
      }

      await _client.auth.signInWithIdToken(
        provider: OAuthProvider.google,
        idToken: idToken,
        accessToken: googleAuth.accessToken,
      );
    } on AuthFailure {
      rethrow;
    } on AuthException catch (e) {
      throw AuthFailure('로그인에 실패했습니다.', e);
    } catch (e) {
      throw AuthFailure('로그인에 실패했습니다.', e);
    }
  }

  @override
  Future<void> signOut() async {
    await _client.auth.signOut();
    await _googleSignIn.signOut();
  }
}

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

| 컬럼 | 타입 | 제약 | 설명 |
|------|------|------|------|
| `id` | `uuid` | PK, FK → `auth.users(id)` ON DELETE CASCADE | Supabase Auth 사용자 ID와 1:1 매핑 |
| `name` | `text` | NOT NULL | 표시 이름 (최초 가입 시 Google 이름 또는 이메일 앞부분) |
| `avatar_url` | `text` | nullable | 프로필 이미지 Storage 경로 (`<userId>/<uuid>.jpg`). null이면 기본 이미지 |
| `created_at` | `timestamptz` | NOT NULL, default `now()` | 프로필 생성 시각 |
| `updated_at` | `timestamptz` | NOT NULL, default `now()` | 마지막 수정 시각 |

- RLS: 본인(`auth.uid() = id`)만 SELECT / UPDATE / INSERT
- `auth.users` 삭제 시 cascade로 함께 삭제됨

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

### auth.users insert trigger

#### 목적

`auth.users` 테이블에 새 사용자가 추가되는 순간, **DB 레벨에서 자동으로** `profiles` row를 생성하는 트리거다.

#### 왜 필요한가

| | trigger 없이 (클라이언트 처리) | trigger 사용 |
|---|---|---|
| 동작 방식 | 로그인 성공 후 클라이언트가 `profiles` 조회 → row 없으면 INSERT | `auth.users`에 row가 들어가는 즉시 DB가 자동으로 `profiles` INSERT |
| 장점 | 별도 DB 설정 불필요 | 클라이언트 코드 단순화, race condition 없음, 어떤 클라이언트에서 로그인하든 일관성 보장 |
| 단점 | 네트워크 끊김/앱 강제종료 시 profile 생성이 누락될 수 있음. 여러 기기에서 동시 로그인 시 race condition 가능 | Supabase SQL Editor에서 트리거를 직접 생성해야 함 |

#### 권장

trigger 방식을 사용하면 `AuthRepository.ensureProfileExists()` 메서드가 불필요해지고, 로그인 흐름이 단순해진다. **특별한 이유가 없으면 trigger 사용을 권장**한다.

#### 동작 흐름

1. 사용자가 Google OAuth로 첫 로그인
2. Supabase Auth가 `auth.users` 테이블에 새 row INSERT
3. 트리거 `on_auth_user_created`가 자동 실행
4. `handle_new_user()` 함수가 `profiles` 테이블에 row 생성
   - `name`: Google 계정의 `full_name`, 없으면 이메일의 `@` 앞 부분
   - `avatar_url`: null (기본 이미지)
5. 클라이언트는 별도 처리 없이 바로 `/todo` 화면으로 이동

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

## Supabase / Google Cloud / 플랫폼 설정

### Google Cloud Console (OAuth 2.0 Client IDs)

네이티브 방식에서는 플랫폼별 3개의 OAuth 클라이언트를 각각 발급해야 한다.

| 타입 | 용도 | 필요한 등록 정보 |
|------|------|------------------|
| **iOS** | iOS 앱에서 `GoogleSignIn(clientId: ...)`로 직접 사용 | iOS Bundle ID (`com.ignite-ek.justThreeTodolist` 또는 현재 설정된 값) |
| **Android** | Android 앱의 네이티브 사인인 검증 | Android 패키지명 + **SHA-1 fingerprint** (`cd android && ./gradlew signingReport`로 debug/release 지문 모두 등록) |
| **Web application** | Supabase가 idToken audience 검증에 사용 / `GoogleSignIn(serverClientId: ...)`에 전달 | **Authorized redirect URIs 등록 불필요** (브라우저 경유 안 함). Client Secret은 Supabase Provider 설정에 입력. |

> 네이티브 방식에서는 **Supabase callback URL(`https://<ref>.supabase.co/auth/v1/callback`)을 Web 클라이언트의 redirect URIs에 등록할 필요가 없다.** 브라우저 리다이렉트 흐름 자체가 없기 때문.

### Supabase Dashboard

- **Authentication > Providers > Google** 활성화.
  - **Client ID for OAuth**: Web 클라이언트 ID (iOS/Android 아님!).
  - **Client Secret for OAuth**: Web 클라이언트의 secret.
  - **Authorized Client IDs (for native sign-in)**: iOS 클라이언트 ID, Android 클라이언트 ID, Web 클라이언트 ID를 **쉼표로 구분하여 모두 등록**한다. 이 목록에 등록되지 않은 audience의 idToken은 Supabase가 거부한다.
- **Authentication > URL Configuration**: 네이티브 방식에서는 수정 사항 없음.

### iOS (`ios/Runner/Info.plist`)

1. **`GIDClientID`** 키에 **iOS 클라이언트 ID** 전체 값을 등록한다.
2. **`CFBundleURLTypes`**에 **iOS 클라이언트 ID를 뒤집은(reversed) 형태**를 URL scheme으로 등록한다.
   - 예: iOS 클라이언트 ID가 `123456789-abcdefg.apps.googleusercontent.com`이면, reversed는 `com.googleusercontent.apps.123456789-abcdefg`.
3. **기존 `io.supabase.justthree` URL scheme은 삭제한다** (deep link 불필요).

```xml
<key>GIDClientID</key>
<string>123456789-abcdefg.apps.googleusercontent.com</string> <!-- 실제 iOS 클라이언트 ID -->
<key>CFBundleURLTypes</key>
<array>
  <dict>
    <key>CFBundleTypeRole</key>
    <string>Editor</string>
    <key>CFBundleURLSchemes</key>
    <array>
      <string>com.googleusercontent.apps.123456789-abcdefg</string> <!-- reversed -->
    </array>
  </dict>
</array>
```

### Android (`android/app/src/main/AndroidManifest.xml`)

- **기존 `io.supabase.justthree` intent-filter는 삭제한다** (deep link 불필요).
- Google Sign-In SDK는 추가 manifest 설정을 요구하지 않는다. Google Cloud Console에 Android 클라이언트의 SHA-1 지문 + 패키지명이 등록되어 있으면 자동으로 매칭된다.
- `google-services.json` 불필요 (Firebase 연동이 아닌 순수 OAuth 경로).

---

## 체크리스트

- [ ] `flutter pub add supabase_flutter flutter_riverpod go_router flutter_dotenv google_sign_in`
- [ ] `.env` 작성 (`SUPABASE_URL`, `SUPABASE_ANON_KEY`, `GOOGLE_OAUTH_IOS_CLIENT_ID`, `GOOGLE_OAUTH_WEB_CLIENT_ID`, 참고용 `GOOGLE_OAUTH_ANDROID_CLIENT_ID`) + `.gitignore` 등록
- [ ] `core/env.dart`에 `googleOAuthIosClientId` / `googleOAuthWebClientId` getter 추가
- [ ] `core/supabase_client.dart` 초기화 (`05_app_bootstrap.md`)
- [ ] `core/router.dart`에 auth redirect 추가 (`05_app_bootstrap.md`)
- [ ] Google Cloud Console에 iOS / Android / Web 3개 클라이언트 발급 (Android는 SHA-1 지문 등록 필수)
- [ ] iOS `Info.plist`에 `GIDClientID` + reversed client ID URL scheme 등록 (기존 `io.supabase.justthree` 제거)
- [ ] Android `AndroidManifest.xml`에서 기존 `io.supabase.justthree` intent-filter 제거
- [ ] Supabase 대시보드 Google provider 활성화 + **Authorized Client IDs**에 iOS/Android/Web 3개 ID 모두 등록
- [ ] `profiles` 테이블 + RLS 생성
- [ ] `handle_new_user` trigger 생성 (프로필 자동 생성)
- [ ] `auth_repository.dart` + `auth_view_model.dart` 작성
- [ ] `login_screen.dart`를 `ConsumerWidget`으로 변환 + 콜백 연결
- [ ] 수동 테스트: 로그인 (네이티브 시트 노출) → 자동 라우팅 → 앱 재시작 시 세션 복원 → 로그아웃 (다음 로그인 시 계정 선택 시트 다시 뜨는지 확인)
