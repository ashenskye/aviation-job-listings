import 'package:aviation_job_listings/screens/sign_in_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _FakeSignInAuthService implements SignInAuthService {
  _FakeSignInAuthService({this.signInErrorMessage});

  final String? signInErrorMessage;
  int updatePasswordCallCount = 0;
  String? lastUpdatedPassword;

  @override
  Future<void> resetPasswordForEmail({
    required String email,
    String? redirectTo,
  }) async {}

  @override
  Future<void> resendSignupConfirmation({
    required String email,
    String? emailRedirectTo,
  }) async {}

  @override
  Future<void> signInWithPassword({
    required String email,
    required String password,
  }) async {
    if (signInErrorMessage != null) {
      throw AuthException(signInErrorMessage!);
    }
  }

  @override
  Future<void> signUp({
    required String email,
    required String password,
    String? emailRedirectTo,
    Map<String, dynamic>? data,
  }) async {}

  @override
  Future<void> updatePassword({required String password}) async {
    updatePasswordCallCount++;
    lastUpdatedPassword = password;
  }
}

void main() {
  testWidgets('sign in screen hides recovery links by default', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: SignInScreen()));
    await tester.pumpAndSettle();

    expect(find.text('Sign In'), findsWidgets);
    expect(find.text('Resend Confirmation Email'), findsNothing);
    expect(find.text('Send Password Reset Email'), findsNothing);
    expect(find.text('New here? Create an account'), findsOneWidget);
  });

  testWidgets('sign up mode does not show recovery links', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: SignInScreen()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('New here? Create an account'));
    await tester.pumpAndSettle();

    expect(find.text('Create Account'), findsWidgets);
    expect(find.text('Resend Confirmation Email'), findsNothing);
    expect(find.text('Send Password Reset Email'), findsNothing);
  });

  testWidgets('shows resend link after unconfirmed email sign-in error', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: SignInScreen(
          authService: _FakeSignInAuthService(
            signInErrorMessage: 'Email not confirmed',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField).at(0), 'pilot@example.com');
    await tester.enterText(find.byType(TextFormField).at(1), 'password123');
    await tester.tap(find.widgetWithText(FilledButton, 'Sign In'));
    await tester.pumpAndSettle();

    expect(find.text('Resend Confirmation Email'), findsOneWidget);
    expect(find.text('Send Password Reset Email'), findsNothing);
  });

  testWidgets('shows password reset link after invalid credentials error', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: SignInScreen(
          authService: _FakeSignInAuthService(
            signInErrorMessage: 'Invalid login credentials',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField).at(0), 'pilot@example.com');
    await tester.enterText(find.byType(TextFormField).at(1), 'password123');
    await tester.tap(find.widgetWithText(FilledButton, 'Sign In'));
    await tester.pumpAndSettle();

    expect(find.text('Resend Confirmation Email'), findsNothing);
    expect(find.text('Send Password Reset Email'), findsOneWidget);
  });

  testWidgets('password recovery mode shows update-password flow', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: SignInScreen(forcePasswordRecoveryMode: true),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Reset Password'), findsWidgets);
    expect(find.text('Update Password'), findsOneWidget);
    expect(find.text('Confirm New Password'), findsOneWidget);
    expect(find.text('New here? Create an account'), findsNothing);
    expect(find.text('Send Password Reset Email'), findsNothing);
  });

  testWidgets('password recovery submits updated password', (
    WidgetTester tester,
  ) async {
    final auth = _FakeSignInAuthService();
    await tester.pumpWidget(
      MaterialApp(
        home: SignInScreen(
          authService: auth,
          forcePasswordRecoveryMode: true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField).at(0), 'new-password-123');
    await tester.enterText(find.byType(TextFormField).at(1), 'new-password-123');
    await tester.tap(find.widgetWithText(FilledButton, 'Update Password'));
    await tester.pumpAndSettle();

    expect(auth.updatePasswordCallCount, 1);
    expect(auth.lastUpdatedPassword, 'new-password-123');
    expect(find.text('Password Updated'), findsWidgets);
    expect(find.text('Continue to Sign In'), findsOneWidget);

    await tester.tap(find.text('Continue to Sign In'));
    await tester.pumpAndSettle();

    expect(find.text('Sign In'), findsWidgets);
    expect(find.text('Continue to Sign In'), findsNothing);
  });
}