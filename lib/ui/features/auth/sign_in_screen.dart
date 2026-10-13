import 'package:firebase_auth/firebase_auth.dart' as auth;
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../config/app_constants.dart';
import '../../../core/l10n/app_strings.dart';
import '../../app/app_view_model.dart';

class SignInScreen extends StatefulWidget {
  const SignInScreen({required this.viewModel, super.key});

  final AppViewModel viewModel;

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _emailFormVisible = false;
  bool _creatingAccount = false;
  bool _obscurePassword = true;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(28, 24, 28, 20),
                child: Column(
                  children: [
                    const SizedBox(height: 36),
                    Container(
                      width: 108,
                      height: 108,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(34),
                        boxShadow: [
                          BoxShadow(
                            color: Theme.of(
                              context,
                            ).colorScheme.primary.withValues(alpha: 0.28),
                            blurRadius: 38,
                            offset: const Offset(0, 18),
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(34),
                        child: Image.asset(
                          'assets/branding/oneframe_icon.png',
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                    const SizedBox(height: 34),
                    Text(
                      strings.appName,
                      style: Theme.of(context).textTheme.displaySmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        letterSpacing: -1.8,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      strings.tagline,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 44),
                    ListenableBuilder(
                      listenable: widget.viewModel,
                      builder: (context, _) =>
                          _buildAuthOptions(context, strings),
                    ),
                    const SizedBox(height: 22),
                    _buildConsent(context, strings),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAuthOptions(BuildContext context, AppStrings strings) {
    final busy = widget.viewModel.busy;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FilledButton.tonal(
          onPressed: busy ? null : () => _signInWithGoogle(context, strings),
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(56),
            backgroundColor: Theme.of(context).colorScheme.surface,
            foregroundColor: Theme.of(context).colorScheme.onSurface,
            side: BorderSide(color: Theme.of(context).dividerColor),
          ),
          child: busy && !_emailFormVisible
              ? const SizedBox.square(
                  dimension: 22,
                  child: CircularProgressIndicator(strokeWidth: 2.4),
                )
              : Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text(
                      'G',
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(strings.continueWithGoogle),
                  ],
                ),
        ),
        const SizedBox(height: 12),
        OutlinedButton(
          onPressed: busy
              ? null
              : () => setState(() => _emailFormVisible = !_emailFormVisible),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(52),
          ),
          child: Text(strings.continueWithEmail),
        ),
        if (_emailFormVisible) ...[
          const SizedBox(height: 18),
          _buildEmailForm(context, strings),
        ],
      ],
    );
  }

  Widget _buildEmailForm(BuildContext context, AppStrings strings) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      TextField(
        controller: _emailController,
        enabled: !widget.viewModel.busy,
        keyboardType: TextInputType.emailAddress,
        textInputAction: TextInputAction.next,
        autofillHints: const [AutofillHints.email],
        decoration: InputDecoration(
          labelText: strings.emailAddress,
          prefixIcon: const Icon(Icons.email_outlined),
        ),
      ),
      const SizedBox(height: 12),
      TextField(
        controller: _passwordController,
        enabled: !widget.viewModel.busy,
        obscureText: _obscurePassword,
        textInputAction: TextInputAction.done,
        autofillHints: const [AutofillHints.password],
        onSubmitted: widget.viewModel.busy
            ? null
            : (_) => _submitEmail(context, strings),
        decoration: InputDecoration(
          labelText: strings.password,
          prefixIcon: const Icon(Icons.lock_outline),
          suffixIcon: IconButton(
            onPressed: () =>
                setState(() => _obscurePassword = !_obscurePassword),
            icon: Icon(
              _obscurePassword
                  ? Icons.visibility_outlined
                  : Icons.visibility_off_outlined,
            ),
            tooltip: strings.showPassword,
          ),
        ),
      ),
      const SizedBox(height: 14),
      FilledButton(
        onPressed: widget.viewModel.busy
            ? null
            : () => _submitEmail(context, strings),
        child: widget.viewModel.busy
            ? const SizedBox.square(
                dimension: 20,
                child: CircularProgressIndicator(strokeWidth: 2.2),
              )
            : Text(_creatingAccount ? strings.createAccount : strings.signIn),
      ),
      if (!_creatingAccount)
        Align(
          alignment: Alignment.center,
          child: TextButton(
            onPressed: widget.viewModel.busy
                ? null
                : () => _resetPassword(context, strings),
            child: Text(strings.forgotPassword),
          ),
        ),
      TextButton(
        onPressed: widget.viewModel.busy
            ? null
            : () => setState(() => _creatingAccount = !_creatingAccount),
        child: Text(
          _creatingAccount ? strings.haveAccount : strings.createNewAccount,
        ),
      ),
    ],
  );

  Widget _buildConsent(BuildContext context, AppStrings strings) => Wrap(
    alignment: WrapAlignment.center,
    crossAxisAlignment: WrapCrossAlignment.center,
    spacing: 4,
    runSpacing: 0,
    children: [
      Text(
        strings.consentPrefix,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
          height: 1.35,
        ),
      ),
      _LegalLink(
        label: strings.privacyPolicy,
        url: AppConstants.privacyPolicyUrl,
      ),
      Text(
        strings.consentJoiner,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
          height: 1.35,
        ),
      ),
      _LegalLink(label: strings.termsOfUse, url: AppConstants.termsOfUseUrl),
      Text(
        strings.consentSuffix,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
          height: 1.35,
        ),
      ),
    ],
  );

  Future<void> _signInWithGoogle(
    BuildContext context,
    AppStrings strings,
  ) async {
    try {
      await widget.viewModel.signInWithGoogle();
    } catch (_) {
      if (!context.mounted) return;
      _showError(context, strings.signInFailed);
    }
  }

  Future<void> _submitEmail(BuildContext context, AppStrings strings) async {
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    if (!_isValidEmail(email)) {
      _showError(context, strings.invalidEmail);
      return;
    }
    if (password.length < 6) {
      _showError(context, strings.passwordTooShort);
      return;
    }

    try {
      if (_creatingAccount) {
        await widget.viewModel.registerWithEmail(
          email: email,
          password: password,
        );
      } else {
        await widget.viewModel.signInWithEmail(
          email: email,
          password: password,
        );
      }
    } on auth.FirebaseAuthException catch (error) {
      if (!context.mounted) return;
      _showError(context, _messageForAuthError(strings, error));
    } catch (_) {
      if (!context.mounted) return;
      _showError(context, strings.emailAuthFailed);
    }
  }

  Future<void> _resetPassword(BuildContext context, AppStrings strings) async {
    final email = _emailController.text.trim();
    if (!_isValidEmail(email)) {
      _showError(context, strings.invalidEmail);
      return;
    }
    try {
      await widget.viewModel.sendPasswordResetEmail(email);
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(strings.passwordResetSent)));
      }
    } on auth.FirebaseAuthException catch (error) {
      if (!context.mounted) return;
      _showError(context, _messageForAuthError(strings, error));
    } catch (_) {
      if (!context.mounted) return;
      _showError(context, strings.emailAuthFailed);
    }
  }

  void _showError(BuildContext context, String message) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  String _messageForAuthError(
    AppStrings strings,
    auth.FirebaseAuthException error,
  ) => switch (error.code) {
    'invalid-credential' ||
    'user-not-found' ||
    'wrong-password' => strings.invalidCredentials,
    'email-already-in-use' => strings.emailAlreadyInUse,
    'weak-password' => strings.passwordTooShort,
    'invalid-email' => strings.invalidEmail,
    'network-request-failed' => strings.networkError,
    _ => strings.emailAuthFailed,
  };

  static bool _isValidEmail(String value) =>
      RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(value);
}

class _LegalLink extends StatelessWidget {
  const _LegalLink({required this.label, required this.url});

  final String label;
  final String url;

  @override
  Widget build(BuildContext context) => TextButton(
    onPressed: () =>
        launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
    style: TextButton.styleFrom(
      padding: EdgeInsets.zero,
      minimumSize: Size.zero,
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.compact,
    ),
    child: Text(label),
  );
}
