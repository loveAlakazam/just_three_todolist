import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../features/auth/view/login_screen.dart';
import '../features/auth/viewmodel/auth_view_model.dart';
import '../features/calendar/view/calendar_screen.dart';
import '../features/profile/view/edit_profile_screen.dart';
import '../features/profile/view/my_screen.dart';
import '../features/todo/view/todo_screen.dart';
import 'splash_screen.dart';

/// go_router 설정.
///
/// - **CR-1 (인증 가드)**: 로딩 중 → `/splash`, 비로그인 → `/login`, 로그인 →
///   `/todo`. redirect 가 전 구간을 단일 함수에서 판정한다.
/// - **CR-2 (탭 상태 유지)**: `StatefulShellRoute.indexedStack`으로 3개 탭 상태 보존.
/// - **CR-3 (세션 영속화)**: `Supabase.init` 이후 세션이 메모리에 있으므로 첫 redirect에서 자동 판정.
final routerProvider = Provider<GoRouter>((ref) {
  final rootKey = GlobalKey<NavigatorState>();
  final calendarKey = GlobalKey<NavigatorState>(debugLabel: 'calendar');
  final todoKey = GlobalKey<NavigatorState>(debugLabel: 'todo');
  final myKey = GlobalKey<NavigatorState>(debugLabel: 'my');

  return GoRouter(
    navigatorKey: rootKey,
    initialLocation: '/splash',

    // -------- CR-1: 인증 가드 --------
    redirect: (context, state) {
      final auth = ref.read(authViewModelProvider);
      final current = state.matchedLocation;
      final onSplash = current == '/splash';
      final onLogin = current == '/login';

      // 초기 세션 복원 중: splash 로 고정해 화면 번쩍임 방지.
      if (auth.isLoading) return onSplash ? null : '/splash';

      final loggedIn = auth.value != null;
      if (!loggedIn) return onLogin ? null : '/login';
      // loggedIn: splash / login 에서 왔다면 todo 로 이동.
      if (onSplash || onLogin) return '/todo';
      return null;
    },
    // 로그인/로그아웃 시점에 redirect 재평가.
    //
    // raw Supabase stream 대신 `authViewModelProvider` 자체를 구독한다.
    // 동일 stream 에 router / ViewModel 두 리스너가 붙었을 때 호출 순서에 따라
    // redirect 가 아직 AsyncLoading 인 ViewModel 을 읽어 `/splash` 로 고착되는
    // race 를 차단하기 위함. Provider notify 는 ViewModel state 가 확정된 뒤에만
    // 발생하므로 redirect 가 항상 최신 state 를 관찰한다.
    refreshListenable: _AuthStateListenable(ref),

    routes: [
      // 공개 라우트
      GoRoute(
        path: '/splash',
        builder: (_, _) => const SplashScreen(),
      ),
      GoRoute(
        path: '/login',
        builder: (_, _) => const LoginScreen(),
      ),

      // -------- CR-2: 보호 라우트 + 탭 상태 유지 --------
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) {
          // Option B: 각 화면이 자체 BottomNav를 유지.
          // AppShell은 BottomNav 없이 navigationShell만 표시.
          return navigationShell;
        },
        branches: [
          // index 0 — Calendar
          StatefulShellBranch(
            navigatorKey: calendarKey,
            routes: [
              GoRoute(
                path: '/calendar',
                builder: (_, _) => const CalendarScreen(),
              ),
            ],
          ),
          // index 1 — Todo (기본 탭)
          StatefulShellBranch(
            navigatorKey: todoKey,
            routes: [
              GoRoute(
                path: '/todo',
                builder: (_, _) => const TodoScreen(),
              ),
            ],
          ),
          // index 2 — My + Edit (push)
          StatefulShellBranch(
            navigatorKey: myKey,
            routes: [
              GoRoute(
                path: '/my',
                builder: (_, _) => const MyScreen(),
                routes: [
                  GoRoute(
                    path: 'edit',
                    builder: (_, _) => const EditProfileScreen(),
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

/// `authViewModelProvider` 의 상태 변화를 [Listenable] 로 노출한다.
///
/// go_router 의 `refreshListenable` 에 연결하면 ViewModel state 가 바뀔 때마다
/// redirect 가 재평가된다. raw `onAuthStateChange` stream 을 직접 구독하지
/// 않는 이유는 위 `refreshListenable` 의 코멘트 참조.
class _AuthStateListenable extends ChangeNotifier {
  _AuthStateListenable(Ref ref) {
    _sub = ref.listen<AsyncValue<User?>>(
      authViewModelProvider,
      (_, _) => notifyListeners(),
    );
  }

  late final ProviderSubscription<AsyncValue<User?>> _sub;

  @override
  void dispose() {
    _sub.close();
    super.dispose();
  }
}
