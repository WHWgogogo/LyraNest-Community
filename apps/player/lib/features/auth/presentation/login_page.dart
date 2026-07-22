import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/server_config.dart';
import '../../../core/config/server_config_controller.dart';
import '../../../core/network/api_error.dart';
import '../../../core/network/server_connection_validator.dart';
import '../../../l10n/l10n.dart';
import '../application/auth_controller.dart';

class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _internalServerController = TextEditingController();
  final _externalServerController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _serverLoaded = false;
  bool _passwordVisible = false;
  bool _submitting = false;
  String? _errorMessage;

  @override
  void dispose() {
    _internalServerController.dispose();
    _externalServerController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final auth = ref.watch(authControllerProvider);
    final config = ref.watch(serverConfigControllerProvider).valueOrNull;
    if (!_serverLoaded && config != null) {
      _serverLoaded = true;
      _internalServerController.text = config.internalBaseUrl ?? config.baseUrl;
      _externalServerController.text = config.externalBaseUrl ?? '';
    }

    final initialized = auth.valueOrNull?.serverInitialized ?? true;
    final initialError = auth.hasError
        ? l10n.authStatusCheckFailed(_messageFor(context, auth.error!))
        : null;
    final errorMessage = _errorMessage ?? initialError;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(28),
                  child: Form(
                    key: _formKey,
                    child: AutofillGroup(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Icon(Icons.graphic_eq_rounded, size: 52),
                          const SizedBox(height: 18),
                          Text(
                            initialized
                                ? l10n.loginTitle
                                : l10n.createAdminTitle,
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.headlineSmall,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            initialized
                                ? l10n.loginDescription
                                : l10n.createAdminDescription,
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                          const SizedBox(height: 28),
                          TextFormField(
                            key: const ValueKey('auth-server-field'),
                            controller: _internalServerController,
                            enabled: !_submitting,
                            keyboardType: TextInputType.url,
                            textInputAction: TextInputAction.next,
                            autocorrect: false,
                            decoration: InputDecoration(
                              labelText: l10n.internalServerAddressLabel,
                              helperText: l10n.internalServerAddressHelper,
                              prefixIcon: const Icon(Icons.home_outlined),
                              border: const OutlineInputBorder(),
                            ),
                            validator: (value) {
                              try {
                                normalizeServerUrl(value ?? '');
                                return null;
                              } on ArgumentError {
                                return l10n.invalidServerUrl;
                              }
                            },
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            key: const ValueKey(
                              'auth-external-server-field',
                            ),
                            controller: _externalServerController,
                            enabled: !_submitting,
                            keyboardType: TextInputType.url,
                            textInputAction: TextInputAction.next,
                            autocorrect: false,
                            decoration: InputDecoration(
                              labelText: l10n.externalServerAddressLabel,
                              helperText: l10n.externalServerAddressHelper,
                              prefixIcon: const Icon(Icons.public_outlined),
                              border: const OutlineInputBorder(),
                            ),
                            validator: (value) {
                              if (value == null || value.trim().isEmpty) {
                                return null;
                              }
                              try {
                                normalizeServerUrl(value);
                                return null;
                              } on ArgumentError {
                                return l10n.invalidServerUrl;
                              }
                            },
                          ),
                          const SizedBox(height: 8),
                          Text(
                            l10n.serverAddressAutoSelectionHint,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            key: const ValueKey('auth-username-field'),
                            controller: _usernameController,
                            enabled: !_submitting,
                            textInputAction: TextInputAction.next,
                            autofillHints: const [AutofillHints.username],
                            autocorrect: false,
                            decoration: InputDecoration(
                              labelText: l10n.usernameLabel,
                              prefixIcon: Icon(Icons.person_outline),
                              border: OutlineInputBorder(),
                            ),
                            validator: (value) => value?.trim().isEmpty != false
                                ? l10n.usernameLabel
                                : null,
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            key: const ValueKey('auth-password-field'),
                            controller: _passwordController,
                            enabled: !_submitting,
                            obscureText: !_passwordVisible,
                            textInputAction: TextInputAction.done,
                            autofillHints: const [AutofillHints.password],
                            onFieldSubmitted: (_) => _submit(),
                            decoration: InputDecoration(
                              labelText: l10n.passwordLabel,
                              prefixIcon: const Icon(Icons.lock_outline),
                              border: const OutlineInputBorder(),
                              suffixIcon: IconButton(
                                tooltip: _passwordVisible
                                    ? l10n.hidePassword
                                    : l10n.showPassword,
                                onPressed: _submitting
                                    ? null
                                    : () {
                                        setState(() {
                                          _passwordVisible = !_passwordVisible;
                                        });
                                      },
                                icon: Icon(
                                  _passwordVisible
                                      ? Icons.visibility_off_outlined
                                      : Icons.visibility_outlined,
                                ),
                              ),
                            ),
                            validator: (value) => value?.isEmpty != false
                                ? l10n.passwordLabel
                                : null,
                          ),
                          if (errorMessage != null) ...[
                            const SizedBox(height: 16),
                            _ErrorMessage(message: errorMessage),
                          ],
                          const SizedBox(height: 22),
                          FilledButton.icon(
                            key: const ValueKey('auth-submit-button'),
                            onPressed: _submitting ? null : _submit,
                            icon: _submitting
                                ? const SizedBox.square(
                                    dimension: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : Icon(
                                    initialized
                                        ? Icons.login_rounded
                                        : Icons.admin_panel_settings_outlined,
                                  ),
                            label: Text(
                              _submitting
                                  ? l10n.connecting
                                  : initialized
                                      ? l10n.login
                                      : l10n.registerAdministrator,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            l10n.loginConnectionHint,
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _submit() async {
    if (_submitting || _formKey.currentState?.validate() != true) {
      return;
    }

    setState(() {
      _submitting = true;
      _errorMessage = null;
    });

    try {
      final controller = ref.read(authControllerProvider.notifier);
      await controller.configureServerAddresses(
        internalBaseUrl: _internalServerController.text,
        externalBaseUrl: _externalServerController.text,
      );
      final initialized = await controller.refreshServerInitialization();
      if (initialized) {
        await controller.login(
          username: _usernameController.text,
          password: _passwordController.text,
        );
      } else {
        await controller.registerAdmin(
          username: _usernameController.text,
          password: _passwordController.text,
        );
      }
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorMessage = _messageFor(context, error);
      });
    } finally {
      if (mounted) {
        setState(() {
          _submitting = false;
        });
      }
    }
  }
}

class _ErrorMessage extends StatelessWidget {
  const _ErrorMessage({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Text(
          message,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onErrorContainer,
          ),
        ),
      ),
    );
  }
}

String _messageFor(BuildContext context, Object error) {
  final l10n = context.l10n;
  return switch (error) {
    ArgumentError() => l10n.invalidServerUrl,
    ServerHealthCheckException(
      failure: ServerHealthCheckFailure.invalidResponse,
    ) =>
      l10n.serverHealthCheckInvalidResponse,
    ServerHealthCheckException(status: final status) =>
      l10n.serverHealthCheckUnexpectedStatus('$status'),
    ApiError apiError
        when Localizations.localeOf(context).languageCode == 'zh' &&
            apiError.statusCode == null =>
      l10n.serverConnectionFailedGeneric,
    ApiError apiError => apiError.localizedMessage(l10n),
    _ => ApiError.fromObject(error).localizedMessage(l10n),
  };
}
