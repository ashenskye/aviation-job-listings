import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// The role a new user intends to take in the app.
enum SignUpPath { jobSeeker, employer }

/// Sign-in / sign-up screen shown when Supabase is configured but the user
/// has no active session.  Successful auth triggers the [AuthGate] stream,
/// which navigates to the main app automatically.
class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key});

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _isSignUp = false;
  bool _isLoading = false;
  bool _isResendingConfirmation = false;
  bool _isSendingPasswordReset = false;
  SignUpPath _signUpPath = SignUpPath.jobSeeker;
  String? _lastSignUpEmail;
  DateTime? _emailActionCooldownUntil;

  static const Duration _emailActionCooldown = Duration(seconds: 60);

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
    if (!kDebugMode || !kIsWeb) {
      return null;
    }

    final host = Uri.base.host.toLowerCase();
    if (host == 'localhost' || host == '127.0.0.1') {
      return Uri.base.origin;
    }
    return null;
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

  void _showEmailRateLimitMessage() {
    final waitSeconds = _emailActionSecondsRemaining > 0
        ? _emailActionSecondsRemaining
        : _emailActionCooldown.inSeconds;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Email rate limit reached. Please wait about $waitSeconds seconds before trying again.',
        ),
      ),
    );
  }

  bool _authMessageIndicatesRateLimit(String message) {
    final lower = message.toLowerCase();
    return lower.contains('rate limit') ||
        lower.contains('too many requests') ||
        lower.contains('429');
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final client = Supabase.instance.client;
      final email = _emailController.text.trim();
      final password = _passwordController.text;
      final redirectUrl = _developmentEmailRedirectUrl;

      if (_isSignUp) {
        final roleValue = _signUpPath == SignUpPath.employer
            ? 'employer'
            : 'job_seeker';
        await client.auth.signUp(
          email: email,
          password: password,
          emailRedirectTo: redirectUrl,
          data: {'profile_type': roleValue},
        );
        if (!mounted) return;
        final signedUpEmail = email;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Check your email to confirm your account, then sign in.',
            ),
          ),
        );
        setState(() {
          _lastSignUpEmail = signedUpEmail;
          _isSignUp = false;
        });
      } else {
        await client.auth.signInWithPassword(email: email, password: password);
        // AuthGate stream handles navigation — no explicit push needed.
      }
    } on AuthException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('An unexpected error occurred.')),
      );
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Enter the account email to resend confirmation.'),
        ),
      );
      return;
    }

    setState(() => _isResendingConfirmation = true);
    try {
      final redirectUrl = _developmentEmailRedirectUrl;
      await Supabase.instance.client.auth.resend(
        type: OtpType.signup,
        email: email,
        emailRedirectTo: redirectUrl,
      );
      if (!mounted) {
        return;
      }
      _startEmailActionCooldown();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Confirmation email sent to $email.')),
      );
    } on AuthException catch (e) {
      if (!mounted) {
        return;
      }
      if (_authMessageIndicatesRateLimit(e.message)) {
        _startEmailActionCooldown();
        _showEmailRateLimitMessage();
      } else {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.message)));
      }
    } catch (_) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not resend confirmation email right now.'),
        ),
      );
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Enter a valid account email to reset password.'),
        ),
      );
      return;
    }

    setState(() => _isSendingPasswordReset = true);
    try {
      final redirectUrl = _developmentEmailRedirectUrl;
      await Supabase.instance.client.auth.resetPasswordForEmail(
        email,
        redirectTo: redirectUrl,
      );
      if (!mounted) {
        return;
      }
      _startEmailActionCooldown();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Password reset email sent to $email.')),
      );
    } on AuthException catch (e) {
      if (!mounted) {
        return;
      }
      if (_authMessageIndicatesRateLimit(e.message)) {
        _startEmailActionCooldown();
        _showEmailRateLimitMessage();
      } else {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.message)));
      }
    } catch (_) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not send password reset email right now.'),
        ),
      );
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
        title: Text(_isSignUp ? 'Create Account' : 'Sign In'),
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
                    _isSignUp
                        ? 'Create an account and choose your role.'
                        : 'Sign in to access your jobs and profile.',
                    style: Theme.of(context).textTheme.bodyMedium,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  // Role picker — shown only during sign-up
                  if (_isSignUp) ..._buildRolePicker(),
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
                  TextFormField(
                    controller: _passwordController,
                    decoration: const InputDecoration(
                      labelText: 'Password',
                      border: OutlineInputBorder(),
                    ),
                    obscureText: true,
                    textInputAction: TextInputAction.done,
                    onFieldSubmitted: (_) => _isLoading ? null : _submit(),
                    validator: (v) {
                      if (v == null || v.isEmpty) return 'Enter your password.';
                      if (_isSignUp && v.length < 8) {
                        return 'Password must be at least 8 characters.';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: _isLoading ? null : _submit,
                    child: _isLoading
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(_isSignUp ? 'Create Account' : 'Sign In'),
                  ),
                  const SizedBox(height: 8),
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
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: _isLoading
                        ? null
                        : () => setState(() {
                            _isSignUp = !_isSignUp;
                            _signUpPath = SignUpPath.jobSeeker;
                            _formKey.currentState?.reset();
                          }),
                    child: Text(
                      _isSignUp
                          ? 'Already have an account? Sign in'
                          : 'New here? Create an account',
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
