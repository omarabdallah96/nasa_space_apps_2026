import 'package:flutter/material.dart';

import '../../l10n/strings.dart';
import '../../services/auth_api.dart';
import '../../state/app_state.dart';
import '../../theme/app_theme.dart';
import '../brand/ember_logo.dart';

/// Sign in or create an account. Optional: "Continue as guest" just closes it.
/// Pops with `true` once signed in.
class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key, this.startWithRegister = false});

  final bool startWithRegister;

  /// Opens the screen as a full-screen dialog; true when the user signed in.
  static Future<bool> open(BuildContext context, {bool register = false}) async =>
      await Navigator.push<bool>(
        context,
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) => AuthScreen(startWithRegister: register),
        ),
      ) ??
      false;

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  late bool _register = widget.startWithRegister;
  bool _busy = false;
  bool _showPassword = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy || !_form.currentState!.validate()) return;
    final state = AppScope.read(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (_register) {
        await state.register(_email.text, _password.text, name: _name.text);
      } else {
        await state.signIn(_email.text, _password.text);
      }
      if (mounted) Navigator.pop(context, true);
    } on AuthException catch (e) {
      if (mounted) setState(() => _error = 'auth_err_${e.code}');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    String? error;
    if (_error != null) {
      final text = s.t(_error!);
      error = text == _error ? s.t('auth_err_unknown') : text;
    }

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close),
          tooltip: s.t('continue_guest'),
          onPressed: () => Navigator.pop(context, false),
        ),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Form(
                key: _form,
                child: AutofillGroup(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Center(child: EmberLogo(size: 64)),
                      const SizedBox(height: 16),
                      Text(
                        s.t(_register ? 'create_account' : 'sign_in'),
                        textAlign: TextAlign.center,
                        style: Theme.of(context)
                            .textTheme
                            .headlineSmall
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        s.t('account_why'),
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Ember.textMuted, height: 1.4),
                      ),
                      const SizedBox(height: 24),
                      SegmentedButton<bool>(
                        segments: [
                          ButtonSegment(value: false, label: Text(s.t('sign_in'))),
                          ButtonSegment(value: true, label: Text(s.t('create_account'))),
                        ],
                        selected: {_register},
                        onSelectionChanged: _busy
                            ? null
                            : (v) => setState(() {
                                  _register = v.first;
                                  _error = null;
                                }),
                      ),
                      const SizedBox(height: 20),
                      if (_register) ...[
                        TextFormField(
                          controller: _name,
                          enabled: !_busy,
                          textInputAction: TextInputAction.next,
                          textCapitalization: TextCapitalization.words,
                          autofillHints: const [AutofillHints.name],
                          maxLength: 60,
                          decoration: InputDecoration(
                            labelText: s.t('name_optional'),
                            prefixIcon: const Icon(Icons.person_outline),
                            counterText: '',
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],
                      TextFormField(
                        key: const ValueKey('auth_email'),
                        controller: _email,
                        enabled: !_busy,
                        keyboardType: TextInputType.emailAddress,
                        textInputAction: TextInputAction.next,
                        autocorrect: false,
                        autofillHints: const [AutofillHints.email],
                        decoration: InputDecoration(
                          labelText: s.t('email'),
                          prefixIcon: const Icon(Icons.alternate_email),
                        ),
                        validator: (v) =>
                            RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch((v ?? '').trim())
                                ? null
                                : s.t('auth_err_bad_email'),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        key: const ValueKey('auth_password'),
                        controller: _password,
                        enabled: !_busy,
                        obscureText: !_showPassword,
                        textInputAction: TextInputAction.done,
                        autofillHints: [
                          _register ? AutofillHints.newPassword : AutofillHints.password
                        ],
                        onFieldSubmitted: (_) => _submit(),
                        decoration: InputDecoration(
                          labelText: s.t('password'),
                          helperText: _register ? s.t('password_hint') : null,
                          prefixIcon: const Icon(Icons.lock_outline),
                          suffixIcon: IconButton(
                            icon: Icon(_showPassword ? Icons.visibility_off : Icons.visibility),
                            onPressed: () => setState(() => _showPassword = !_showPassword),
                          ),
                        ),
                        validator: (v) {
                          final pw = v ?? '';
                          if (pw.isEmpty) return s.t('auth_err_bad_password');
                          if (_register && pw.length < 8) return s.t('auth_err_weak_password');
                          return null;
                        },
                      ),
                      if (error != null) ...[
                        const SizedBox(height: 14),
                        Text(error,
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Ember.extreme)),
                      ],
                      const SizedBox(height: 22),
                      FilledButton(
                        key: const ValueKey('auth_submit'),
                        onPressed: _busy ? null : _submit,
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(50),
                          backgroundColor: Ember.ember,
                          foregroundColor: Ember.background,
                        ),
                        child: _busy
                            ? SizedBox.square(
                                dimension: 20,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Ember.background),
                              )
                            : Text(s.t(_register ? 'create_account' : 'sign_in'),
                                style: const TextStyle(fontWeight: FontWeight.w700)),
                      ),
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: _busy ? null : () => Navigator.pop(context, false),
                        child: Text(s.t('continue_guest'),
                            style: TextStyle(color: Ember.textMuted)),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
