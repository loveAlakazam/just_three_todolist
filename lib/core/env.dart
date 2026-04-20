import 'package:flutter_dotenv/flutter_dotenv.dart';

/// 환경 변수 단일 진입점.
///
/// 앱 시작 전 [Env.load]를 반드시 호출해야 한다.
class Env {
  Env._();

  static Future<void> load() => dotenv.load(fileName: '.env');

  static String get supabaseUrl => _required('SUPABASE_URL');
  static String get supabaseAnonKey => _required('SUPABASE_ANON_KEY');

  /// iOS 네이티브 Google Sign-In용 OAuth 2.0 Client ID.
  static String get googleOAuthIosClientId =>
      _required('GOOGLE_OAUTH_IOS_CLIENT_ID');

  /// Supabase가 idToken audience 검증에 사용하는 Web OAuth 2.0 Client ID.
  /// `GoogleSignIn(serverClientId: ...)`로 전달된다.
  static String get googleOAuthWebClientId =>
      _required('GOOGLE_OAUTH_WEB_CLIENT_ID');

  static String _required(String key) {
    final v = dotenv.env[key];
    if (v == null || v.isEmpty) {
      throw StateError('Missing env var: $key');
    }
    return v;
  }
}
