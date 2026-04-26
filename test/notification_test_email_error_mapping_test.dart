import 'package:flutter_test/flutter_test.dart';
import 'package:aviation_job_listings/services/supabase_app_repository.dart';

void main() {
  group('mapNotificationTestEmailError', () {
    test('maps network fetch errors to connectivity guidance', () {
      final message = mapNotificationTestEmailError(
        Exception('ClientException: Failed to fetch'),
      );

      expect(message, contains('Could not reach the notification service.'));
      expect(message, contains('RESEND_API_KEY/EMAIL_FROM'));
    });

    test('maps unverified domain errors to Resend domain guidance', () {
      final message = mapNotificationTestEmailError(
        Exception(
          'FunctionException: Resend failed: {"name":"validation_error","message":"The domain is not verified"}',
        ),
      );

      expect(
        message,
        'Email sender domain is not verified in Resend. '
        'Use a verified domain for EMAIL_FROM in Supabase secrets '
        '(or temporarily onboarding@resend.dev for testing).',
      );
    });

    test('falls back to generic message for unknown errors', () {
      final message = mapNotificationTestEmailError(
        Exception('Something unexpected happened'),
      );

      expect(message, contains('Could not send test notification:'));
      expect(message, contains('Something unexpected happened'));
    });
  });
}
