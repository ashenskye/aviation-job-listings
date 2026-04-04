import '../repositories/app_repository.dart';
import 'local_app_repository.dart';
import 'supabase_app_repository.dart';
import 'supabase_bootstrap.dart';

class AppRepositoryFactory {
  static AppRepository create() {
    final local = LocalAppRepository();

    if (!SupabaseBootstrap.isConfigured) {
      return local;
    }

    return SupabaseAppRepository(localFallback: local);
  }
}
