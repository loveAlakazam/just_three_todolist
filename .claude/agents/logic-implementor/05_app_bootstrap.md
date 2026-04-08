# 05. 앱 부트스트랩 — main.dart / core / shared/models / 환경 변수 / 라우팅

## 작업 범위
- `lib/main.dart`
- `lib/core/` (신규)
- `lib/shared/models/` (신규)
- 프로젝트 루트 `.env` (신규, gitignore)

이 문서는 모든 feature가 동작하기 위해 **가장 먼저 갖춰져야 할** 공통 인프라를 정의한다.
다른 명세 (`01_auth.md` ~ `04_profile.md`)는 이 문서가 완료되었다는 가정하에 작성된다.

---

## 현재 상태

### `lib/main.dart`
```dart
import 'package:flutter/material.dart';
import 'package:just_three_todolist/features/todo/view/todo_screen.dart';
import 'features/auth/view/login_screen.dart';

void main() {
  runApp(const MainApp());
}

class MainApp extends StatelessWidget {
  const MainApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      title: 'Just Three',
      debugShowCheckedModeBanner: false,
      // home: LoginScreen(),
      home: TodoScreen(),
    );
  }
}
```
- `ProviderScope` 없음 → Riverpod 사용 불가.
- Supabase 초기화 없음.
- `MaterialApp.router` 미사용 → go_router 미적용.
- 환경 변수 로드 없음.
- `home: TodoScreen()` 임시 테스트 설정 (사용자가 commented out).

### `lib/core/`
존재하지 않음 (디렉토리 생성 필요).

### `lib/shared/models/`
존재하지 않음 (디렉토리 생성 필요).

---

## 구현해야 할 내용

### 1. 패키지 추가
```bash
flutter pub add flutter_riverpod supabase_flutter go_router flutter_dotenv
flutter pub add dev:build_runner dev:riverpod_generator dev:custom_lint dev:riverpod_lint  # (선택, 코드 생성 사용 시)
```

> `image_picker`는 이미 추가됨. `riverpod_generator` / `freezed`는 선택사항이지만 권장.

### 2. `.env` 파일
프로젝트 루트에 생성:
```
SUPABASE_URL=https://<project-ref>.supabase.co
SUPABASE_ANON_KEY=eyJhbGciOi...
```

`.gitignore`에 추가:
```
.env
.env.*
```

`pubspec.yaml`의 assets에 추가:
```yaml
flutter:
  assets:
    - assets/images/
    - .env
```

### 3. `lib/core/env.dart`
```dart
import 'package:flutter_dotenv/flutter_dotenv.dart';

/// 환경 변수 단일 진입점.
///
/// 앱 시작 전 [Env.load]를 반드시 호출해야 한다.
class Env {
  Env._();

  static Future<void> load() => dotenv.load(fileName: '.env');

  static String get supabaseUrl => _required('SUPABASE_URL');
  static String get supabaseAnonKey => _required('SUPABASE_ANON_KEY');

  static String _required(String key) {
    final v = dotenv.env[key];
    if (v == null || v.isEmpty) {
      throw StateError('Missing env var: $key');
    }
    return v;
  }
}
```

### 4. `lib/core/supabase_client.dart`
```dart
import 'package:supabase_flutter/supabase_flutter.dart';

import 'env.dart';

/// Supabase 글로벌 진입점.
///
/// 앱 시작 시 [SupabaseService.init]을 한 번 호출한 뒤,
/// 어디서든 [SupabaseService.client]로 접근한다.
class SupabaseService {
  SupabaseService._();

  static SupabaseClient get client => Supabase.instance.client;

  static Future<void> init() async {
    await Supabase.initialize(
      url: Env.supabaseUrl,
      anonKey: Env.supabaseAnonKey,
      authOptions: const FlutterAuthClientOptions(
        authFlowType: AuthFlowType.pkce,
      ),
    );
  }
}
```

### 5. `lib/core/router.dart`

> 이 파일은 **CR-1 (인증 가드)** 와 **CR-2 (탭 상태 유지)** 두 가지 핵심 제약을 동시에 만족시키는 단일 진입점이다. `StatefulShellRoute.indexedStack`을 사용해 BottomNav 3개 탭을 `IndexedStack`으로 감싸고, 전역 `redirect`로 비로그인 사용자를 차단한다.

```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/auth/view/login_screen.dart';
import '../features/auth/viewmodel/auth_view_model.dart';
import '../features/auth/repository/auth_repository.dart';
import '../features/calendar/view/calendar_screen.dart';
import '../features/profile/view/edit_profile_screen.dart';
import '../features/profile/view/my_screen.dart';
import '../features/todo/view/todo_screen.dart';
import '../shared/widgets/app_shell.dart'; // BottomNavigationBar를 가진 shell

final routerProvider = Provider<GoRouter>((ref) {
  // navigator key는 상위(root)와 각 branch별로 분리해야 push 라우트가
  // 올바른 stack 위에 쌓인다.
  final rootKey = GlobalKey<NavigatorState>();
  final calendarKey = GlobalKey<NavigatorState>();
  final todoKey = GlobalKey<NavigatorState>();
  final myKey = GlobalKey<NavigatorState>();

  return GoRouter(
    navigatorKey: rootKey,
    initialLocation: '/todo',

    // -------- CR-1: 인증 가드 --------
    redirect: (context, state) {
      final auth = ref.read(authViewModelProvider);
      // AsyncLoading 동안에는 redirect 보류 (null 반환).
      if (auth.isLoading) return null;
      final loggedIn = auth.valueOrNull != null;
      final goingToLogin = state.matchedLocation == '/login';

      if (!loggedIn && !goingToLogin) return '/login';
      if (loggedIn && goingToLogin) return '/todo';
      return null;
    },
    // 로그인/로그아웃 시점에 redirect 재평가.
    refreshListenable: GoRouterRefreshStream(
      ref.read(authRepositoryProvider).authStateChanges,
    ),

    routes: [
      // 공개 라우트
      GoRoute(
        path: '/login',
        builder: (_, __) => const LoginScreen(),
      ),

      // -------- CR-2: 보호 라우트 + 탭 상태 유지 --------
      // StatefulShellRoute.indexedStack은 각 branch 화면을
      // IndexedStack에 보관하므로, 탭을 전환해도 widget이 dispose되지 않는다.
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) {
          // AppShell은 BottomNavigationBar를 그리고,
          // body로 navigationShell (현재 활성 branch의 Navigator)을 표시.
          return AppShell(navigationShell: navigationShell);
        },
        branches: [
          // index 0 — Calendar
          StatefulShellBranch(
            navigatorKey: calendarKey,
            routes: [
              GoRoute(
                path: '/calendar',
                builder: (_, __) => const CalendarScreen(),
              ),
            ],
          ),
          // index 1 — Todo (기본 탭)
          StatefulShellBranch(
            navigatorKey: todoKey,
            routes: [
              GoRoute(
                path: '/todo',
                builder: (_, __) => const TodoScreen(),
              ),
            ],
          ),
          // index 2 — My + Edit (push)
          StatefulShellBranch(
            navigatorKey: myKey,
            routes: [
              GoRoute(
                path: '/my',
                builder: (_, __) => const MyScreen(),
                routes: [
                  // /my/edit는 My branch의 Navigator 위에 push되므로,
                  // 다른 탭으로 갔다 돌아와도 EditProfileScreen이 그대로 살아 있다.
                  GoRoute(
                    path: 'edit',
                    builder: (_, __) => const EditProfileScreen(),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    ],
  );
});

/// authStateChanges Stream을 ChangeNotifier로 변환.
class GoRouterRefreshStream extends ChangeNotifier {
  GoRouterRefreshStream(Stream<dynamic> stream) {
    notifyListeners();
    _sub = stream.asBroadcastStream().listen((_) => notifyListeners());
  }
  late final StreamSubscription<dynamic> _sub;
  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }
}
```

#### `lib/shared/widgets/app_shell.dart` (신규)

`StatefulShellRoute.indexedStack`은 builder에 `StatefulNavigationShell`을 넘겨준다. 이를 감싸는 얇은 Scaffold가 필요하다 — BottomNavigationBar 위젯 자체는 ui-implementor가 관리하는 디자인이지만, **shell wrapping** 자체는 라우팅 인프라이므로 logic-implementor 범위 안.

```dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  void _onTabTapped(int index) {
    navigationShell.goBranch(
      index,
      // 같은 탭을 다시 누르면 해당 branch의 stack을 root로 reset.
      initialLocation: index == navigationShell.currentIndex,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // body는 IndexedStack 그대로 — 각 branch의 화면이 살아 있는 채로 전환.
      body: navigationShell,
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: navigationShell.currentIndex,
        onTap: _onTabTapped,
        // 아이콘 / 색상 / 라벨 등 디자인 디테일은 ui-implementor가 정의한
        // 기존 BottomNav 위젯 스펙을 그대로 이식.
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.calendar_month), label: 'Calendar'),
          BottomNavigationBarItem(icon: Icon(Icons.checklist), label: 'Todo'),
          BottomNavigationBarItem(icon: Icon(Icons.person), label: 'My'),
        ],
      ),
    );
  }
}
```

> **주의**: 위 BottomNavigationBar는 placeholder다. 현재 각 화면 (`calendar_screen`, `todo_screen`, `my_screen`) 안에 이미 BottomNav UI가 그려져 있다. logic 구현 시 다음 둘 중 하나를 선택:
> - **A. 위로 올리기**: 각 화면의 BottomNav를 제거하고 `AppShell`로 통합. 더 정석적이고 탭 상태 유지가 자연스럽지만, View 위젯 트리 변경이 발생 → ui-implementor 범위 침범. **사전 합의 필수**.
> - **B. 그대로 두기**: 각 화면이 자체 BottomNav를 유지하고, `AppShell`은 BottomNav 없이 `Scaffold(body: navigationShell)`만 둔다. View 변경 없이 진행 가능하지만, 탭 누를 때마다 `context.go(...)`가 아닌 `navigationShell.goBranch(...)`로 교체해야 한다. → 각 View의 `_onTabTapped`가 `Navigator.pushReplacement` 대신 `StatefulNavigationShell.of(context).goBranch(index)` 호출하도록 수정. 이 정도는 logic 변환의 일환으로 허용.
>
> 권장: **B 방식**으로 시작 → 추후 디자인 통일 작업 시 A로 리팩터링.

#### 라우트 path 정리

| Path | 화면 | 분류 |
|------|------|------|
| `/login` | LoginScreen | 공개 |
| `/calendar` | CalendarScreen | 보호 / shell branch 0 |
| `/todo` | TodoScreen | 보호 / shell branch 1 (기본) |
| `/my` | MyScreen | 보호 / shell branch 2 |
| `/my/edit` | EditProfileScreen | 보호 / branch 2 위에 push |

### 6. `lib/main.dart` 재작성
```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/env.dart';
import 'core/router.dart';
import 'core/supabase_client.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Env.load();
  await SupabaseService.init();
  runApp(const ProviderScope(child: MainApp()));
}

class MainApp extends ConsumerWidget {
  const MainApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    return MaterialApp.router(
      title: 'Just Three',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        scaffoldBackgroundColor: const Color(0xFFF3F4EB),
        // 한글: Noto Sans Korean / 영문: Google Sans (Google Fonts)
        // 폰트는 google_fonts 패키지 도입 시 ThemeData.textTheme로 일괄 적용.
      ),
      routerConfig: router,
    );
  }
}
```

> 사용자가 임시로 `home: TodoScreen()`으로 바꿔둔 부분은 ProviderScope + router 적용 후 자동으로 해소된다.

#### CR-3 (세션 영속화) 동작 보장

- `await SupabaseService.init()`가 끝나는 시점에 SDK는 디스크에 저장된 세션을 메모리로 복원해 둔다. 이후 `Supabase.instance.client.auth.currentSession`이 즉시 valid한 값을 돌려준다.
- 따라서 `runApp` 이후 router의 첫 redirect가 호출될 때, 자동 로그인 사용자는 곧바로 `loggedIn = true`로 평가되어 `/todo`에 머무른다 (`/login`으로 빠지지 않는다).
- `SupabaseService.init`을 `runApp` 이전에 `await`하지 않으면 첫 프레임에서 `currentSession == null`이 되어 잠시 `/login`으로 깜빡이는 버그가 발생한다 — **반드시 await**.
- `flutter_secure_storage` 등 별도 패키지 추가 불필요. `supabase_flutter`가 기본 제공.

### 7. `lib/shared/models/`
- `profile.dart` — `04_profile.md` 참고
- `todo.dart` — `02_todo.md` 참고

이 두 모델만 우선 만들면 충분. `freezed`를 도입한다면 둘 다 freezed 클래스로 작성하는 것을 권장 (불변 + copyWith + JSON 자동 생성).

---

## 작업 순서 (권장)

1. **인프라**: 패키지 추가 → `.env` → `core/env.dart` → `core/supabase_client.dart` → `core/router.dart` → `main.dart`.
2. **모델**: `shared/models/profile.dart`, `shared/models/todo.dart`.
3. **DB / Storage**: Supabase 대시보드에서 `profiles`, `todos` 테이블 + RLS + `avatars` 버킷 생성. (`01~04` 명세의 SQL 참고.)
4. **인증**: `01_auth.md` → 로그인 동작 확인.
5. **Todo**: `02_todo.md`.
6. **Calendar**: `03_calendar.md` (Todo 동작 확인 후 진행해야 데이터가 보임).
7. **Profile**: `04_profile.md` (Todo와 무관, 로그인 후 바로 가능).

각 단계가 끝날 때마다 `flutter analyze` + 수동 테스트.

---

## BottomNavigationBar 이동 방식 변경 (모든 View 공통)

> **CR-2 (탭 상태 유지) 핵심 구현**: 단순 `context.go(...)`로는 탭 상태가 유지되지 않는다. 반드시 `StatefulNavigationShell.goBranch(index)`를 사용해야 `IndexedStack` 안에서 화면이 살아 있는 채로 전환된다.

현재 모든 View는 `Navigator.pushReplacement(MaterialPageRoute(...))`를 사용 → 이는 매번 새 화면을 만들어 상태가 사라진다. go_router + `StatefulShellRoute` 도입 후에는:

```dart
void _onTabTapped(int index) {
  final shell = StatefulNavigationShell.of(context);
  if (index == shell.currentIndex) return;
  shell.goBranch(
    index,
    initialLocation: index == shell.currentIndex,
  );
}
```

- 3개 탭 화면(`calendar_screen.dart`, `todo_screen.dart`, `my_screen.dart`)의 `_onTabTapped` 핸들러를 위 코드로 일괄 교체.
- `edit_profile_screen.dart`는 BottomNav가 없으므로 해당 없음. `/my/edit` 진입은 기존대로 `context.push('/my/edit')`를 사용 (push 라우트).
- 각 화면에서 다른 화면을 직접 import하던 라인은 모두 제거 (탭 전환은 `goBranch`만으로 이루어짐).
- `Navigator.pushReplacement`, `Navigator.push(MaterialPageRoute(...))` 사용을 전부 제거. 남아 있으면 새 화면이 IndexedStack 바깥에 쌓여 탭 상태가 깨진다.

### 동작 검증 시나리오 (수동 테스트 필수)

1. Todo 탭에서 첫 칸에 "회의 준비" 입력 (저장 안 한 상태) → Calendar 탭 → Todo 탭 복귀: 입력값이 그대로 남아 있어야 한다.
2. Calendar 탭에서 9월로 이동 → My 탭 → Calendar 탭 복귀: 여전히 9월 화면.
3. My 탭에서 프로필 편집(`/my/edit`) 진입 → 이미지 1장 선택 → Calendar 탭 → My 탭 복귀: 여전히 EditProfileScreen이 떠 있고 선택한 이미지가 살아 있어야 한다.
4. 앱 완전 종료 후 재실행: 자동 로그인 → `/todo`로 바로 진입 (CR-3).
5. My 탭에서 로그아웃 → 즉시 `/login`으로 이동 (CR-1).
6. 로그아웃 상태에서 deep link 등으로 `/todo` 직접 진입 시도 → `/login`으로 redirect (CR-1).

---

## 체크리스트

- [ ] `flutter pub add flutter_riverpod supabase_flutter go_router flutter_dotenv`
- [ ] `.env` 작성 + `.gitignore` 등록 + `pubspec.yaml`의 assets에 추가
- [ ] `lib/core/env.dart` 작성
- [ ] `lib/core/supabase_client.dart` 작성
- [ ] `lib/core/router.dart` 작성 — `StatefulShellRoute.indexedStack` + 전역 `redirect` 적용 (CR-1, CR-2)
- [ ] `lib/shared/widgets/app_shell.dart` 작성 (또는 기존 BottomNav를 `goBranch`로 연결)
- [ ] `lib/main.dart` 재작성 (`ProviderScope` + `MaterialApp.router`, `Supabase.init` await로 CR-3 보장)
- [ ] `lib/shared/models/profile.dart` 작성
- [ ] `lib/shared/models/todo.dart` 작성
- [ ] Supabase 대시보드: `profiles`, `todos` 테이블 + RLS + `avatars` 버킷
- [ ] (선택) `handle_new_user` trigger / `delete-account` Edge Function
- [ ] 3개 탭 View의 BottomNav `_onTabTapped`를 `StatefulNavigationShell.goBranch(index)`로 교체
- [ ] `Navigator.pushReplacement` / `Navigator.push(MaterialPageRoute)` 잔존 호출 모두 제거
- [ ] `flutter analyze` 통과
- [ ] 수동 테스트 (CR-1/CR-2/CR-3 검증):
  - [ ] 앱 첫 실행 → `/login` 표시 → Google 로그인 → `/todo` 자동 이동
  - [ ] 앱 완전 종료 후 재실행 → 자동 로그인 → `/todo` 바로 진입 (CR-3)
  - [ ] Todo 입력 중 → Calendar → Todo 복귀: 입력값 유지 (CR-2)
  - [ ] Calendar 9월 이동 → My → Calendar 복귀: 9월 유지 (CR-2)
  - [ ] My → 프로필 편집 → 이미지 선택 → Calendar → My 복귀: EditProfileScreen + 선택 이미지 유지 (CR-2)
  - [ ] My → 로그아웃 → `/login`으로 이동 (CR-1)
  - [ ] 로그아웃 상태에서 `/todo` 등 보호 라우트 직접 접근 시도 → `/login`으로 redirect (CR-1)
