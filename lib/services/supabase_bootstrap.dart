import 'package:flutter/widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseBootstrap {
  static const String _url = String.fromEnvironment('SUPABASE_URL');
  static const String _anonKey = String.fromEnvironment('SUPABASE_ANON_KEY');
  static const String _publishableKey = String.fromEnvironment(
    'SUPABASE_PUBLISHABLE_KEY',
  );

  static String get _clientKey =>
      _anonKey.isNotEmpty ? _anonKey : _publishableKey;

  static bool get isConfigured => _url.isNotEmpty && _clientKey.isNotEmpty;

  static Future<void> initializeIfConfigured() async {
    if (!isConfigured) {
      return;
    }

    WidgetsFlutterBinding.ensureInitialized();
    await Supabase.initialize(url: _url, anonKey: _clientKey);
  }
}
