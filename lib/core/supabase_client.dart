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
      // 네이티브 Google Sign-In + signInWithIdToken 방식은 웹 OAuth 를
      // 사용하지 않는다. implicit 으로 명시해 PKCE 딥링크 핸들러 비활성화.
      authOptions: const FlutterAuthClientOptions(
        authFlowType: AuthFlowType.implicit,
      ),
    );
  }
}
