import 'package:flutter/material.dart';

/// 앱 부트스트랩 화면.
///
/// `authViewModelProvider` 가 `AsyncLoading` 인 동안 `router.dart` 의 redirect
/// 가 모든 라우트에서 이 화면으로 유도한다. 초기 세션 복원이 끝나면 redirect
/// 가 다시 실행되며 `/login` 또는 `/todo` 로 이동한다.
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3F4EB),
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Image.asset(
                'assets/images/just-three-logo.png',
                width: 200,
                fit: BoxFit.contain,
              ),
              const SizedBox(height: 32),
              const CircularProgressIndicator(
                color: Color(0xFF512DA8),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
