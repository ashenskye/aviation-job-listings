import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// The role a new user intends to take in the app.
enum SignUpPath { jobSeeker, employer }

abstract class SignInAuthService {
  Future<void> signUp({
    required String email,
    required String password,
    String? emailRedirectTo,
    Map<String, dynamic>? data,
  });

  Future<void> signInWithPassword({
    required String email,
    required String password,
  });

  Future<void> resendSignupConfirmation({
    required String email,
    String? emailRedirectTo,
  });

  Future<void> resetPasswordForEmail({
    required String email,
    String? redirectTo,
  });

  Future<void> updatePassword({required String password});
}

class SupabaseSignInAuthService implements SignInAuthService {
  const SupabaseSignInAuthService();

  static const SupabaseSignInAuthService instance = SupabaseSignInAuthService();

  @override
  Future<void> signUp({
    required String email,
    required String password,
    String? emailRedirectTo,
    Map<String, dynamic>? data,
  }) async {
    await Supabase.instance.client.auth.signUp(
      email: email,
      password: password,
      emailRedirectTo: emailRedirectTo,
      data: data,
    );
  }

  @override
  Future<void> signInWithPassword({
    required String email,
    required String password,
  }) async {
    await Supabase.instance.client.auth.signInWithPassword(
      email: email,
      password: password,
    );
  }

  @override
  Future<void> resendSignupConfirmation({
    required String email,
    String? emailRedirectTo,
  }) async {
    await Supabase.instance.client.auth.resend(
      type: OtpType.signup,
      email: email,
      emailRedirectTo: emailRedirectTo,
    );
  }

  @override
  Future<void> resetPasswordForEmail({
    required String email,
    String? redirectTo,
  }) async {
    await Supabase.instance.client.auth.resetPasswordForEmail(
      email,
      redirectTo: redirectTo,
    );
  }

  @override
  Future<void> updatePassword({required String password}) async {
    await Supabase.instance.client.auth.updateUser(
      UserAttributes(password: password),
    );
  }
}

/// Sign-in / sign-up screen shown when Supabase is configured but the user
/// has no active session.  Successful auth triggers the [AuthGate] stream,
/// which navigates to the main app automatically.
class SignInScreen extends StatefulWidget {
  const SignInScreen({
    super.key,
    this.authService,
    this.forcePasswordRecoveryMode = false,
  });

  final SignInAuthService? authService;
  final bool forcePasswordRecoveryMode;

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  StreamSubscription<AuthState>? _authStateSubscription;

  bool _isSignUp = false;
  bool _isPasswordRecoveryMode = false;
  bool _showPasswordUpdatedSuccess = false;
  bool _isLoading = false;
  bool _isResendingConfirmation = false;
  bool _isSendingPasswordReset = false;
  bool _showResendConfirmationLink = false;
  bool _showPasswordResetLink = false;
  String? _inlineAuthErrorBannerMessage;
  SignUpPath _signUpPath = SignUpPath.jobSeeker;
  String? _lastSignUpEmail;
  DateTime? _emailActionCooldownUntil;

  static const Duration _emailActionCooldown = Duration(seconds: 60);

  SignInAuthService get _authService =>
      widget.authService ?? SupabaseSignInAuthService.instance;

  bool _hasInitializedSupabase() {
    try {
      Supabase.instance.client;
      return true;
    } catch (_) {
      return false;
    }
  }

  bool _urlIndicatesPasswordRecovery() {
    if (!kIsWeb) {
      return false;
    }

    final uri = Uri.base;
    final queryType = uri.queryParameters['type']?.trim().toLowerCase() ?? '';
    if (queryType == 'recovery') {
      return true;
    }

    final fragment = uri.fragment;
    if (fragment.isEmpty) {
      return false;
    }

    final queryStart = fragment.indexOf('?');
    final fragmentQuery = queryStart >= 0
        ? fragment.substring(queryStart + 1)
        : fragment;

    try {
      final params = Uri.splitQueryString(fragmentQuery);
      final type = params['type']?.trim().toLowerCase() ?? '';
      return type == 'recovery';
    } catch (_) {
      return false;
    }
  }

  String? _urlAuthErrorMessage() {
    if (!kIsWeb) {
      return null;
    }

    final uri = Uri.base;
    final queryErrorCode =
        uri.queryParameters['error_code']?.trim().toLowerCase() ?? '';
    if (queryErrorCode.isNotEmpty) {
      if (queryErrorCode == 'otp_expired') {
        return 'This password reset link has expired or was already used. Request a new reset email and use the newest link.';
      }
      final queryErrorDescription =
          uri.queryParameters['error_description']?.trim() ?? '';
      return queryErrorDescription.isNotEmpty
          ? queryErrorDescription
          : 'Authentication link could not be used. Please request a new password reset email.';
    }

    final fragment = uri.fragment;
    if (fragment.isEmpty) {
      return null;
    }

    final queryStart = fragment.indexOf('?');
    final fragmentQuery = queryStart >= 0
        ? fragment.substring(queryStart + 1)
        : fragment;

    try {
      final params = Uri.splitQueryString(fragmentQuery);
      final errorCode = params['error_code']?.trim().toLowerCase() ?? '';
      if (errorCode == 'otp_expired') {
        return 'This password reset link has expired or was already used. Request a new reset email and use the newest link.';
      }

      if (errorCode.isNotEmpty) {
        final errorDescription = params['error_description']?.trim() ?? '';
        return errorDescription.isNotEmpty
            ? errorDescription
            : 'Authentication link could not be used. Please request a new password reset email.';
      }
    } catch (_) {
      return null;
    }

    return null;
  }

  @override
  void initState() {
    super.initState();

    _isPasswordRecoveryMode =
        widget.forcePasswordRecoveryMode || _urlIndicatesPasswordRecovery();
    final urlAuthError = _urlAuthErrorMessage();
    if (urlAuthError != null) {
      _isPasswordRecoveryMode = false;
      _showPasswordResetLink = true;
      _inlineAuthErrorBannerMessage = urlAuthError;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        _showMessage(urlAuthError);
      });
    }

    if (_hasInitializedSupabase()) {
      _authStateSubscription = Supabase.instance.client.auth.onAuthStateChange
          .listen((authState) {
            if (!mounted) {
              return;
            }
            if (authState.event == AuthChangeEvent.passwordRecovery) {
              setState(() {
                _isPasswordRecoveryMode = true;
                _showPasswordUpdatedSuccess = false;
                _isSignUp = false;
                _showResendConfirmationLink = false;
                _showPasswordResetLink = false;
              });
            }
          });
    }
  }

  bool get _emailActionCoolingDown {
    final until = _emailActionCooldownUntil;
    return until != null && DateTime.now().isBefore(until);
  }

  int get _emailActionSecondsRemaining {
    final until = _emailActionCooldownUntil;
    if (until == null) {
      return 0;
    }
    final diff = until.difference(DateTime.now()).inSeconds;
    return diff > 0 ? diff : 0;
  }

  String? get _developmentEmailRedirectUrl {
    if (!kIsWeb) {
      return null;
    }

    return Uri.base.origin;
  }

  void _startEmailActionCooldown([Duration duration = _emailActionCooldown]) {
    final until = DateTime.now().add(duration);
    setState(() => _emailActionCooldownUntil = until);

    Future<void>.delayed(duration, () {
      if (!mounted) {
        return;
      }
      if (_emailActionCooldownUntil == null ||
          DateTime.now().isBefore(_emailActionCooldownUntil!)) {
        return;
      }
      setState(() => _emailActionCooldownUntil = null);
    });
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: SelectableText(
            message,
            style: const TextStyle(color: Colors.white),
          ),
          duration: const Duration(minutes: 10),
          action: SnackBarAction(
            label: 'Dismiss',
            onPressed: () =>
                ScaffoldMessenger.of(context).hideCurrentSnackBar(),
          ),
        ),
      );
  }

  void _dismissCurrentMessage() {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
  }

  void _showEmailRateLimitMessage() {
    final waitSeconds = _emailActionSecondsRemaining > 0
        ? _emailActionSecondsRemaining
        : _emailActionCooldown.inSeconds;
    _showMessage(
      'Email rate limit reached. Please wait about $waitSeconds seconds before trying again.',
    );
  }

  bool _authMessageIndicatesRateLimit(String message) {
    final lower = message.toLowerCase();
    return lower.contains('rate limit') ||
        lower.contains('too many requests') ||
        lower.contains('429');
  }

  bool _authMessageIndicatesUnconfirmedEmail(String message) {
    final lower = message.toLowerCase();
    return lower.contains('email not confirmed') ||
        (lower.contains('confirm') && lower.contains('email'));
  }

  bool _authMessageIndicatesInvalidCredentials(String message) {
    final lower = message.toLowerCase();
    return lower.contains('invalid login credentials') ||
        lower.contains('invalid credentials') ||
        lower.contains('invalid email or password');
  }

  @override
  void dispose() {
    _authStateSubscription?.cancel();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _submitPasswordUpdate() async {
    _dismissCurrentMessage();

    final newPassword = _passwordController.text;
    final confirmPassword = _confirmPasswordController.text;

    if (newPassword.length < 8) {
      _showMessage('New password must be at least 8 characters.');
      return;
    }
    if (newPassword != confirmPassword) {
      _showMessage('Passwords do not match.');
      return;
    }

    setState(() => _isLoading = true);
    try {
      await _authService.updatePassword(password: newPassword);
      if (_hasInitializedSupabase()) {
        await Supabase.instance.client.auth.signOut(scope: SignOutScope.local);
      }
      if (!mounted) {
        return;
      }
      setState(() {
        _isPasswordRecoveryMode = false;
        _showPasswordUpdatedSuccess = true;
        _isSignUp = false;
        _showPasswordResetLink = false;
        _showResendConfirmationLink = false;
      });
      _dismissCurrentMessage();
      _passwordController.clear();
      _confirmPasswordController.clear();
    } on AuthException catch (e) {
      if (!mounted) {
        return;
      }
      _showMessage(e.message);
    } catch (_) {
      if (!mounted) {
        return;
      }
      _showMessage('Could not update password right now.');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _submit() async {
    if (_isPasswordRecoveryMode) {
      await _submitPasswordUpdate();
      return;
    }

    _dismissCurrentMessage();

    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final email = _emailController.text.trim();
      final password = _passwordController.text;
      final redirectUrl = _developmentEmailRedirectUrl;

      if (_isSignUp) {
        final roleValue = _signUpPath == SignUpPath.employer
            ? 'employer'
            : 'job_seeker';
        await _authService.signUp(
          email: email,
          password: password,
          emailRedirectTo: redirectUrl,
          data: {'profile_type': roleValue},
        );
        if (!mounted) return;
        final signedUpEmail = email;
        _showMessage('Check your email to confirm your account, then sign in.');
        setState(() {
          _lastSignUpEmail = signedUpEmail;
          _isSignUp = false;
          _showResendConfirmationLink = true;
          _showPasswordResetLink = false;
        });
      } else {
        await _authService.signInWithPassword(email: email, password: password);
        if (mounted) {
          _dismissCurrentMessage();
        }
        // AuthGate stream handles navigation — no explicit push needed.
      }
    } on AuthException catch (e) {
      if (!mounted) return;
      setState(() {
        if (_authMessageIndicatesUnconfirmedEmail(e.message)) {
          _showResendConfirmationLink = true;
          _showPasswordResetLink = false;
        } else if (_authMessageIndicatesInvalidCredentials(e.message)) {
          _showPasswordResetLink = true;
        }
      });
      _showMessage(e.message);
    } catch (_) {
      if (!mounted) return;
      _showMessage('An unexpected error occurred.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _resendConfirmationEmail() async {
    if (_emailActionCoolingDown) {
      _showEmailRateLimitMessage();
      return;
    }

    final email = _emailController.text.trim().isNotEmpty
        ? _emailController.text.trim()
        : (_lastSignUpEmail ?? '').trim();

    if (email.isEmpty || !email.contains('@')) {
      _showMessage('Enter the account email to resend confirmation.');
      return;
    }

    setState(() => _isResendingConfirmation = true);
    try {
      final redirectUrl = _developmentEmailRedirectUrl;
      await _authService.resendSignupConfirmation(
        email: email,
        emailRedirectTo: redirectUrl,
      );
      if (!mounted) {
        return;
      }
      _startEmailActionCooldown();
      _showMessage('Confirmation email sent to $email.');
    } on AuthException catch (e) {
      if (!mounted) {
        return;
      }
      if (_authMessageIndicatesRateLimit(e.message)) {
        _startEmailActionCooldown();
        _showEmailRateLimitMessage();
      } else {
        _showMessage(e.message);
      }
    } catch (_) {
      if (!mounted) {
        return;
      }
      _showMessage('Could not resend confirmation email right now.');
    } finally {
      if (mounted) {
        setState(() => _isResendingConfirmation = false);
      }
    }
  }

  Future<void> _sendPasswordResetEmail() async {
    if (_emailActionCoolingDown) {
      _showEmailRateLimitMessage();
      return;
    }

    final email = _emailController.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      _showMessage('Enter a valid account email to reset password.');
      return;
    }

    setState(() => _isSendingPasswordReset = true);
    try {
      final redirectUrl = _developmentEmailRedirectUrl;
      await _authService.resetPasswordForEmail(
        email: email,
        redirectTo: redirectUrl,
      );
      if (!mounted) {
        return;
      }
      _startEmailActionCooldown();
      _showMessage('Password reset email sent to $email.');
    } on AuthException catch (e) {
      if (!mounted) {
        return;
      }
      if (_authMessageIndicatesRateLimit(e.message)) {
        _startEmailActionCooldown();
        _showEmailRateLimitMessage();
      } else {
        _showMessage(e.message);
      }
    } catch (_) {
      if (!mounted) {
        return;
      }
      _showMessage('Could not send password reset email right now.');
    } finally {
      if (mounted) {
        setState(() => _isSendingPasswordReset = false);
      }
    }
  }

  List<Widget> _buildRolePicker() {
    return [
      Text('I am joining as a', style: Theme.of(context).textTheme.titleSmall),
      const SizedBox(height: 8),
      Container(
        decoration: BoxDecoration(
          border: Border.all(color: Theme.of(context).dividerColor),
          borderRadius: BorderRadius.circular(12),
        ),
        child: RadioGroup<SignUpPath>(
          groupValue: _signUpPath,
          onChanged: (value) {
            if (_isLoading || value == null) {
              return;
            }
            setState(() => _signUpPath = value);
          },
          child: Column(
            children: [
              RadioListTile<SignUpPath>(
                title: const Text('Job Seeker'),
                subtitle: const Text(
                  'Browse jobs, save favorites, and compare your qualifications.',
                ),
                value: SignUpPath.jobSeeker,
              ),
              RadioListTile<SignUpPath>(
                title: const Text('Employer'),
                subtitle: const Text(
                  'Create a company profile and post aviation job listings.',
                ),
                value: SignUpPath.employer,
              ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 24),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: Text(
          _showPasswordUpdatedSuccess
              ? 'Password Updated'
              : _isPasswordRecoveryMode
              ? 'Reset Password'
              : (_isSignUp ? 'Create Account' : 'Sign In'),
        ),
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Aviation Job Listings',
                    style: Theme.of(context).textTheme.headlineSmall,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _showPasswordUpdatedSuccess
                        ? 'Your password was updated successfully.'
                        : _isPasswordRecoveryMode
                        ? 'Set a new password for your account.'
                        : _isSignUp
                        ? 'Create an account and choose your role.'
                        : 'Sign in to access your jobs and profile.',
                    style: Theme.of(context).textTheme.bodyMedium,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  if (_inlineAuthErrorBannerMessage != null) ...[
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        border: Border.all(color: Colors.red.shade300),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.error_outline,
                            size: 20,
                            color: Colors.red.shade700,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: SelectableText(
                              _inlineAuthErrorBannerMessage!,
                              style: TextStyle(
                                color: Colors.red.shade900,
                                fontSize: 13,
                              ),
                            ),
                          ),
                          IconButton(
                            tooltip: 'Dismiss',
                            visualDensity: VisualDensity.compact,
                            onPressed: () =>
                                setState(() => _inlineAuthErrorBannerMessage = null),
                            icon: Icon(
                              Icons.close,
                              size: 18,
                              color: Colors.red.shade700,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  if (_showPasswordUpdatedSuccess) ...[
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.green.shade50,
                        border: Border.all(color: Colors.green.shade300),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        children: [
                          Icon(
                            Icons.check_circle_outline,
                            color: Colors.green.shade700,
                            size: 36,
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'You can now sign in with your new password.',
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: _isLoading
                          ? null
                          : () {
                              setState(() {
                                _showPasswordUpdatedSuccess = false;
                                _isPasswordRecoveryMode = false;
                                _isSignUp = false;
                                _showResendConfirmationLink = false;
                                _showPasswordResetLink = false;
                              });
                            },
                      child: const Text('Continue to Sign In'),
                    ),
                  ] else ...[
                  // Role picker — shown only during sign-up
                  if (_isSignUp) ..._buildRolePicker(),
                  if (!_isPasswordRecoveryMode) ...[
                    TextFormField(
                      controller: _emailController,
                      decoration: const InputDecoration(
                        labelText: 'Email',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.emailAddress,
                      autocorrect: false,
                      textInputAction: TextInputAction.next,
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) {
                          return 'Enter your email address.';
                        }
                        if (!v.contains('@')) {
                          return 'Enter a valid email address.';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                  ],
                  TextFormField(
                    controller: _passwordController,
                    decoration: InputDecoration(
                      labelText:
                          _isPasswordRecoveryMode ? 'New Password' : 'Password',
                      border: OutlineInputBorder(),
                    ),
                    obscureText: true,
                    textInputAction: TextInputAction.done,
                    onFieldSubmitted: (_) => _isLoading ? null : _submit(),
                    validator: (v) {
                      if (v == null || v.isEmpty) return 'Enter your password.';
                      if ((_isSignUp || _isPasswordRecoveryMode) &&
                          v.length < 8) {
                        return 'Password must be at least 8 characters.';
                      }
                      return null;
                    },
                  ),
                  if (_isPasswordRecoveryMode) ...[
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _confirmPasswordController,
                      decoration: const InputDecoration(
                        labelText: 'Confirm New Password',
                        border: OutlineInputBorder(),
                      ),
                      obscureText: true,
                      textInputAction: TextInputAction.done,
                      onFieldSubmitted: (_) => _isLoading ? null : _submit(),
                    ),
                  ],
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: _isLoading ? null : _submit,
                    child: _isLoading
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(
                            _isPasswordRecoveryMode
                                ? 'Update Password'
                                : (_isSignUp ? 'Create Account' : 'Sign In'),
                          ),
                  ),
                  if (!_isSignUp &&
                      !_isPasswordRecoveryMode &&
                      (_showResendConfirmationLink ||
                          _showPasswordResetLink))
                    const SizedBox(height: 8),
                  if (!_isSignUp &&
                      !_isPasswordRecoveryMode &&
                      _showResendConfirmationLink)
                    TextButton(
                      onPressed:
                          (_isLoading ||
                              _isResendingConfirmation ||
                              _emailActionCoolingDown)
                          ? null
                          : _resendConfirmationEmail,
                      child: _isResendingConfirmation
                          ? const SizedBox(
                              height: 18,
                              width: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Resend Confirmation Email'),
                    ),
                  if (!_isSignUp &&
                      !_isPasswordRecoveryMode &&
                      _showPasswordResetLink)
                    TextButton(
                      onPressed:
                          (_isLoading ||
                              _isResendingConfirmation ||
                              _isSendingPasswordReset ||
                              _emailActionCoolingDown)
                          ? null
                          : _sendPasswordResetEmail,
                      child: _isSendingPasswordReset
                          ? const SizedBox(
                              height: 18,
                              width: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Send Password Reset Email'),
                    ),
                  if (!_isPasswordRecoveryMode) ...[
                    const SizedBox(height: 12),
                    TextButton(
                      onPressed: _isLoading
                          ? null
                          : () => setState(() {
                              _isSignUp = !_isSignUp;
                              _signUpPath = SignUpPath.jobSeeker;
                              if (_isSignUp) {
                                _showResendConfirmationLink = false;
                                _showPasswordResetLink = false;
                              }
                              _formKey.currentState?.reset();
                            }),
                      child: Text(
                        _isSignUp
                            ? 'Already have an account? Sign in'
                            : 'New here? Create an account',
                      ),
                    ),
                  ],
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
