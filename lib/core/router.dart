import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/auth/repository/auth_repository.dart';
import '../features/auth/view/login_screen.dart';
import '../features/auth/viewmodel/auth_view_model.dart';
import '../features/calendar/view/calendar_screen.dart';
import '../features/profile/view/edit_profile_screen.dart';
import '../features/profile/view/my_screen.dart';
import '../features/todo/view/todo_screen.dart';

/// go_router 설정.
///
/// - **CR-1 (인증 가드)**: 비로그인 → `/login` redirect, 로그인 + `/login` → `/todo` redirect.
/// - **CR-2 (탭 상태 유지)**: `StatefulShellRoute.indexedStack`으로 3개 탭 상태 보존.
/// - **CR-3 (세션 영속화)**: `Supabase.init` 이후 세션이 메모리에 있으므로 첫 redirect에서 자동 판정.
final routerProvider = Provider<GoRouter>((ref) {
  final rootKey = GlobalKey<NavigatorState>();
  final calendarKey = GlobalKey<NavigatorState>(debugLabel: 'calendar');
  final todoKey = GlobalKey<NavigatorState>(debugLabel: 'todo');
  final myKey = GlobalKey<NavigatorState>(debugLabel: 'my');

  return GoRouter(
    navigatorKey: rootKey,
    initialLocation: '/todo',

    // -------- CR-1: 인증 가드 --------
    redirect: (context, state) {
      final auth = ref.read(authViewModelProvider);
      // AsyncLoading 동안에는 redirect 보류.
      if (auth.isLoading) return null;
      final loggedIn = auth.value != null;
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

/// authStateChanges Stream을 ChangeNotifier로 변환.
///
/// go_router의 `refreshListenable`에 연결하면,
/// 로그인/로그아웃 이벤트가 발생할 때마다 redirect가 재평가된다.
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
