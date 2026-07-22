import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/config/server_config_controller.dart';
import '../../../core/network/api_error.dart';
import '../../../core/network/server_connection_validator.dart';
import '../../../core/widgets/loading_state.dart';
import '../../../features/auth/application/auth_controller.dart';
import '../../../features/preferences/player_preferences.dart';
import '../../../features/tracks/data/tracks_api.dart';
import '../../../l10n/l10n.dart';

import 'lyrics_settings_section.dart';

const aboutPageViewedPreferenceKey = 'about_page_viewed';

class ServerSettingsPage extends ConsumerStatefulWidget {
  const ServerSettingsPage({super.key});

  @override
  ConsumerState<ServerSettingsPage> createState() => _ServerSettingsPageState();
}

class _ServerSettingsPageState extends ConsumerState<ServerSettingsPage> {
  late final TextEditingController _internalController;
  late final TextEditingController _externalController;
  var _isSaving = false;
  bool? _hasViewedAboutPage;

  @override
  void initState() {
    super.initState();
    _internalController = TextEditingController();
    _externalController = TextEditingController();
    _loadAboutPageViewedState();
  }

  @override
  void dispose() {
    _internalController.dispose();
    _externalController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    ref.listen(serverConfigControllerProvider, (_, next) {
      next.whenData((config) {
        final internal = config.internalBaseUrl ?? config.baseUrl;
        final external = config.externalBaseUrl ?? '';
        if (_internalController.text != internal) {
          _internalController.text = internal;
        }
        if (_externalController.text != external) {
          _externalController.text = external;
        }
      });
    });

    final config = ref.watch(serverConfigControllerProvider);
    final preferences = ref.watch(playerPreferencesProvider);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.settingsTitle)),
      body: config.when(
        loading: () => const LoadingState(),
        error: (error, _) => Center(
          child: Text(l10n.serverSettingsLoadFailed(error.toString())),
        ),
        data: (value) {
          if (_internalController.text.isEmpty) {
            _internalController.text = value.internalBaseUrl ?? value.baseUrl;
          }
          if (_externalController.text.isEmpty &&
              value.externalBaseUrl != null) {
            _externalController.text = value.externalBaseUrl!;
          }

          return ListView(
            padding: const EdgeInsets.all(24),
            children: [
              TextField(
                key: const ValueKey('server-url-field'),
                controller: _internalController,
                readOnly: _isSaving,
                decoration: InputDecoration(
                  labelText: _internalServerLabel(context),
                  helperText: _internalServerHelper(context),
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.url,
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 16),
              TextField(
                key: const ValueKey('external-server-url-field'),
                controller: _externalController,
                readOnly: _isSaving,
                decoration: InputDecoration(
                  labelText: _externalServerLabel(context),
                  helperText: _externalServerHelper(context),
                  border: const OutlineInputBorder(),
                ),
                keyboardType: TextInputType.url,
                textInputAction: TextInputAction.done,
              ),
              const SizedBox(height: 8),
              Text(
                _automaticServerSelectionHint(context),
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _isSaving ? null : _saveServerUrl,
                child: Text(_isSaving ? l10n.connecting : l10n.save),
              ),
              const SizedBox(height: 24),
              const SizedBox(height: 24),
              preferences.when(
                loading: () => const Card(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                ),
                error: (error, _) => Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(_preferencesLoadFailed(context, error)),
                  ),
                ),
                data: (preferences) => LyricsSettingsSection(
                  backgroundOpacity: preferences.desktopLyricsBackgroundOpacity,
                  lyricsColorArgb: preferences.lyricsColorArgb,
                  desktopLyricsAlignment: preferences.desktopLyricsAlignment,
                  inAppLyricsAlignment: preferences.inAppLyricsAlignment,
                  desktopLyricsLineMode: preferences.desktopLyricsLineMode,
                  resetPositionOnOpen: preferences.resetPositionOnOpen,
                  onBackgroundOpacityChanged: (value) {
                    return _savePreference(
                      ref
                          .read(playerPreferencesProvider.notifier)
                          .setDesktopLyricsBackgroundOpacity(value),
                    );
                  },
                  onLyricsColorArgbChanged: (value) {
                    return _savePreference(
                      ref
                          .read(playerPreferencesProvider.notifier)
                          .setLyricsColorArgb(value),
                    );
                  },
                  onDesktopLyricsAlignmentChanged: (value) {
                    return _savePreference(
                      ref
                          .read(playerPreferencesProvider.notifier)
                          .setDesktopLyricsAlignment(value),
                    );
                  },
                  onInAppLyricsAlignmentChanged: (value) {
                    return _savePreference(
                      ref
                          .read(playerPreferencesProvider.notifier)
                          .setInAppLyricsAlignment(value),
                    );
                  },
                  onDesktopLyricsLineModeChanged: (value) {
                    return _savePreference(
                      ref
                          .read(playerPreferencesProvider.notifier)
                          .setDesktopLyricsLineMode(value),
                    );
                  },
                  onResetPositionOnOpenChanged: (value) {
                    return _savePreference(
                      ref
                          .read(playerPreferencesProvider.notifier)
                          .setResetPositionOnOpen(value),
                    );
                  },
                ),
              ),
              const SizedBox(height: 24),
              Text(
                l10n.appInfoTitle,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Card(
                child: Column(
                  children: [
                    ListTile(
                      key: const ValueKey('about-settings-entry'),
                      leading: const Icon(Icons.info_outline_rounded),
                      title: Text(l10n.aboutTitle),
                      subtitle: Text(l10n.aboutSubtitle),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (_hasViewedAboutPage == false)
                            Container(
                              key: const ValueKey(
                                'about-entry-unread-indicator',
                              ),
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: Theme.of(context).colorScheme.error,
                                shape: BoxShape.circle,
                              ),
                            ),
                          const SizedBox(width: 12),
                          const Icon(Icons.chevron_right_rounded),
                        ],
                      ),
                      onTap: _openAboutPage,
                    ),
                    const Divider(height: 1),
                    ListTile(
                      key: const ValueKey('support-author-settings-entry'),
                      leading: const Icon(Icons.volunteer_activism_outlined),
                      title: Text(l10n.supportAuthorTitle),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: _openSupportAuthorPage,
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<bool> _savePreference(Future<void> update) async {
    try {
      await update;
      return true;
    } catch (error) {
      if (!mounted) {
        return false;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_preferencesSaveFailed(context, error))),
      );
      return false;
    }
  }

  Future<void> _saveServerUrl() async {
    setState(() {
      _isSaving = true;
    });

    try {
      await ref.read(authControllerProvider.notifier).configureServerAddresses(
            internalBaseUrl: _internalController.text,
            externalBaseUrl: _externalController.text,
          );
      if (!mounted) {
        return;
      }

      ref.invalidate(tracksProvider);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.serverConnectionSucceeded)),
      );
      context.go('/tracks');
    } catch (error) {
      if (!mounted) {
        return;
      }

      final l10n = context.l10n;
      final detail = switch (error) {
        ArgumentError() => l10n.invalidServerUrl,
        ApiError apiError
            when Localizations.localeOf(context).languageCode == 'zh' &&
                apiError.statusCode == null =>
          l10n.serverConnectionFailedGeneric,
        ApiError apiError => apiError.localizedMessage(l10n),
        ServerHealthCheckException(
          failure: ServerHealthCheckFailure.invalidResponse,
        ) =>
          l10n.serverHealthCheckInvalidResponse,
        ServerHealthCheckException(status: final status) =>
          l10n.serverHealthCheckUnexpectedStatus('$status'),
        _ => error.toString(),
      };
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.serverConnectionFailed(detail))),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  Future<void> _loadAboutPageViewedState() async {
    final preferences = await SharedPreferences.getInstance();
    if (!mounted) {
      return;
    }

    setState(() {
      _hasViewedAboutPage =
          preferences.getBool(aboutPageViewedPreferenceKey) ?? false;
    });
  }

  Future<void> _openAboutPage() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(aboutPageViewedPreferenceKey, true);
    if (!mounted) {
      return;
    }

    setState(() {
      _hasViewedAboutPage = true;
    });
    context.push('/about');
  }

  void _openSupportAuthorPage() {
    context.push('/support');
  }
}

String _preferencesLoadFailed(BuildContext context, Object error) {
  final isChinese = Localizations.localeOf(context).languageCode == 'zh';
  return isChinese
      ? '?????????$error'
      : 'Could not load lyrics settings: $error';
}

String _preferencesSaveFailed(BuildContext context, Object error) {
  final isChinese = Localizations.localeOf(context).languageCode == 'zh';
  return isChinese
      ? '?????????$error'
      : 'Could not save lyrics settings: $error';
}

String _internalServerLabel(BuildContext context) {
  return context.l10n.internalServerAddressLabel;
}

String _internalServerHelper(BuildContext context) {
  return context.l10n.internalServerAddressHelper;
}

String _externalServerLabel(BuildContext context) {
  return context.l10n.externalServerAddressLabel;
}

String _externalServerHelper(BuildContext context) {
  return context.l10n.externalServerAddressHelper;
}

String _automaticServerSelectionHint(BuildContext context) {
  return context.l10n.serverAddressAutoSelectionHint;
}
