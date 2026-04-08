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
```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/auth/view/login_screen.dart';
import '../features/auth/viewmodel/auth_view_model.dart';
import '../features/calendar/view/calendar_screen.dart';
import '../features/profile/view/edit_profile_screen.dart';
import '../features/profile/view/my_screen.dart';
import '../features/todo/view/todo_screen.dart';

final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/todo',
    redirect: (context, state) {
      final auth = ref.read(authViewModelProvider);
      final loggedIn = auth.valueOrNull != null;
      final goingToLogin = state.matchedLocation == '/login';

      if (!loggedIn && !goingToLogin) return '/login';
      if (loggedIn && goingToLogin) return '/todo';
      return null;
    },
    refreshListenable: GoRouterRefreshStream(
      ref.read(authRepositoryProvider).authStateChanges,
    ),
    routes: [
      GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),
      GoRoute(path: '/todo', builder: (_, __) => const TodoScreen()),
      GoRoute(path: '/calendar', builder: (_, __) => const CalendarScreen()),
      GoRoute(
        path: '/my',
        builder: (_, __) => const MyScreen(),
        routes: [
          GoRoute(path: 'edit', builder: (_, __) => const EditProfileScreen()),
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
  void dispose() { _sub.cancel(); super.dispose(); }
}
```

> 라우트 path 결정:
> - `/login` — LoginScreen
> - `/todo` — TodoScreen (기본 진입점)
> - `/calendar` — CalendarScreen
> - `/my` — MyScreen
> - `/my/edit` — EditProfileScreen
>
> BottomNav 탭 이동도 `context.go('/calendar' | '/todo' | '/my')`로 교체. 현재 View들은
> `Navigator.pushReplacement`를 쓰고 있으므로, 라우터 도입 시 한꺼번에 교체.
> ui-implementor의 `BottomNavigationBar` 절 참고.

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

현재 모든 View는 `Navigator.pushReplacement(MaterialPageRoute(...))`를 사용한다.
go_router 도입 후에는:
```dart
void _onTabTapped(int index) {
  if (index == _tabIndex) return;
  switch (index) {
    case 0: context.go('/calendar');
    case 1: context.go('/todo');
    case 2: context.go('/my');
  }
}
```
- 4개 화면 (`calendar_screen.dart`, `todo_screen.dart`, `my_screen.dart`, `edit_profile_screen.dart`) 모두 동일하게 교체.
- import도 해당 라우트에서 더 이상 다른 화면을 직접 import 할 필요 없다 → 정리.

---

## 체크리스트

- [ ] `flutter pub add flutter_riverpod supabase_flutter go_router flutter_dotenv`
- [ ] `.env` 작성 + `.gitignore` 등록 + `pubspec.yaml`의 assets에 추가
- [ ] `lib/core/env.dart` 작성
- [ ] `lib/core/supabase_client.dart` 작성
- [ ] `lib/core/router.dart` 작성
- [ ] `lib/main.dart` 재작성 (`ProviderScope` + `MaterialApp.router`)
- [ ] `lib/shared/models/profile.dart` 작성
- [ ] `lib/shared/models/todo.dart` 작성
- [ ] Supabase 대시보드: `profiles`, `todos` 테이블 + RLS + `avatars` 버킷
- [ ] (선택) `handle_new_user` trigger / `delete-account` Edge Function
- [ ] 4개 View의 BottomNav 이동을 `context.go(...)`로 교체
- [ ] `flutter analyze` 통과
- [ ] 수동 테스트: 앱 시작 → 자동 리다이렉트 → 로그인/로그아웃 → 모든 화면 접근
