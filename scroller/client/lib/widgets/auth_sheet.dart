import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../state/auth_controller.dart';
import 'google_logo.dart';

class AuthSheet extends StatefulWidget {
  const AuthSheet({super.key, this.onSuccess});

  final VoidCallback? onSuccess;

  static Future<bool> show(
    BuildContext context, {
    VoidCallback? onSuccess,
  }) async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF121212),
      builder: (_) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: AuthSheet(onSuccess: onSuccess),
      ),
    );
    return result ?? false;
  }

  @override
  State<AuthSheet> createState() => _AuthSheetState();
}

class _AuthSheetState extends State<AuthSheet> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _codeController = TextEditingController();
  bool _createAccount = true;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _submitCredentials(AuthController auth) async {
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    if (email.isEmpty || password.isEmpty) {
      return;
    }
    if (_createAccount && password.length < 8) {
      auth.setError('Password must be at least 8 characters.');
      return;
    }

    if (_createAccount) {
      await auth.registerWithEmail(email: email, password: password);
      return;
    }

    await auth.signInWithEmail(email: email, password: password);
    await _finishIfLoggedIn(auth);
  }

  Future<void> _verify(AuthController auth) async {
    final code = _codeController.text.trim();
    if (code.length != 6) {
      return;
    }
    await auth.verifyEmail(code: code);
    await _finishIfLoggedIn(auth);
  }

  Future<void> _google(AuthController auth) async {
    await auth.signInWithGoogle();
    await _finishIfLoggedIn(auth);
  }

  Future<void> _finishIfLoggedIn(AuthController auth) async {
    if (!auth.isLoggedIn || !mounted) {
      return;
    }
    widget.onSuccess?.call();
    final navigator = Navigator.of(context);
    if (navigator.canPop()) {
      navigator.pop(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();
    final verifying = auth.pendingVerificationEmail != null;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: verifying ? _buildVerify(auth) : _buildCredentials(auth),
      ),
    );
  }

  Widget _buildCredentials(AuthController auth) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          _createAccount ? 'Create account' : 'Sign in',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        const Text('Sign in to like and comment.'),
        const SizedBox(height: 16),
        TextField(
          key: const Key('auth_email_field'),
          controller: _emailController,
          keyboardType: TextInputType.emailAddress,
          decoration: const InputDecoration(labelText: 'Email'),
        ),
        const SizedBox(height: 8),
        TextField(
          key: const Key('auth_password_field'),
          controller: _passwordController,
          obscureText: true,
          decoration: const InputDecoration(labelText: 'Password'),
        ),
        if (auth.error != null) ...[
          const SizedBox(height: 8),
          Text(auth.error!, style: const TextStyle(color: Colors.redAccent)),
        ],
        const SizedBox(height: 16),
        FilledButton(
          key: const Key('auth_submit_button'),
          onPressed: auth.busy ? null : () => _submitCredentials(auth),
          child: Text(_createAccount ? 'Create account' : 'Sign in'),
        ),
        TextButton(
          key: const Key('auth_toggle_mode_button'),
          onPressed: () => setState(() => _createAccount = !_createAccount),
          child: Text(_createAccount ? 'Have an account? Sign in' : 'Create account'),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          key: const Key('auth_google_button'),
          onPressed: auth.busy ? null : () => _google(auth),
          icon: const GoogleLogo(size: 20),
          label: const Text('Continue with Google'),
        ),
      ],
    );
  }

  void _backToSignIn(AuthController auth) {
    _codeController.clear();
    auth.clearPendingVerification();
    setState(() => _createAccount = false);
  }

  Widget _buildVerify(AuthController auth) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Check your email', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        Text('Enter the 6-digit code sent to ${auth.pendingVerificationEmail}.'),
        const SizedBox(height: 16),
        TextField(
          key: const Key('auth_code_field'),
          controller: _codeController,
          keyboardType: TextInputType.number,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(6),
          ],
          decoration: const InputDecoration(labelText: 'Verification code'),
        ),
        if (auth.error != null) ...[
          const SizedBox(height: 8),
          Text(auth.error!, style: const TextStyle(color: Colors.redAccent)),
        ],
        const SizedBox(height: 16),
        FilledButton(
          key: const Key('auth_verify_button'),
          onPressed: auth.busy ? null : () => _verify(auth),
          child: const Text('Verify'),
        ),
        TextButton(
          key: const Key('auth_resend_button'),
          onPressed: auth.busy ? null : () => auth.resendVerification(),
          child: const Text('Resend code'),
        ),
        TextButton(
          key: const Key('auth_back_to_sign_in_button'),
          onPressed: auth.busy ? null : () => _backToSignIn(auth),
          child: const Text('Back to sign in'),
        ),
      ],
    );
  }
}
