import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/app_lifecycle_platform.dart';
import '../../player/application/player_controller.dart';

enum RootBackExitAction {
  cancel,
  keepPlayingInBackground,
  exitApplication,
}

class RootBackExitGuard extends ConsumerStatefulWidget {
  const RootBackExitGuard({
    required this.child,
    super.key,
    this.platform,
    this.targetPlatform,
    this.stopPlayback,
    this.isRootUri = true,
  });

  final Widget child;
  final AppLifecyclePlatform? platform;
  final TargetPlatform? targetPlatform;
  final Future<void> Function()? stopPlayback;
  final bool isRootUri;

  @override
  ConsumerState<RootBackExitGuard> createState() => _RootBackExitGuardState();
}

class _RootBackExitGuardState extends ConsumerState<RootBackExitGuard> {
  var _isDialogVisible = false;

  TargetPlatform get _targetPlatform =>
      widget.targetPlatform ?? defaultTargetPlatform;

  bool get _isAndroid => _targetPlatform == TargetPlatform.android;

  bool get _shouldInterceptRootBack => _isAndroid && widget.isRootUri;

  AppLifecyclePlatform get _platform =>
      widget.platform ?? appLifecyclePlatformFor(_targetPlatform);

  @override
  Widget build(BuildContext context) {
    return PopScope<Object?>(
      canPop: !_shouldInterceptRootBack,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _shouldInterceptRootBack) {
          unawaited(_handleRootBack());
        }
      },
      child: widget.child,
    );
  }

  Future<void> _handleRootBack() async {
    if (_isDialogVisible || !mounted) {
      return;
    }

    _isDialogVisible = true;
    try {
      final action = await showDialog<RootBackExitAction>(
        context: context,
        barrierDismissible: false,
        builder: (context) => _RootBackExitDialog(
          locale: Localizations.localeOf(context),
        ),
      );
      if (!mounted || action == null || action == RootBackExitAction.cancel) {
        return;
      }

      switch (action) {
        case RootBackExitAction.cancel:
          return;
        case RootBackExitAction.keepPlayingInBackground:
          await _platform.moveTaskToBack();
          return;
        case RootBackExitAction.exitApplication:
          try {
            await (widget.stopPlayback ??
                ref.read(playerControllerProvider.notifier).stop)();
          } finally {
            await _platform.exitApplication();
          }
          return;
      }
    } finally {
      _isDialogVisible = false;
    }
  }
}

class _RootBackExitDialog extends StatelessWidget {
  const _RootBackExitDialog({required this.locale});

  final Locale locale;

  @override
  Widget build(BuildContext context) {
    final strings = _RootBackExitStrings.fromLocale(locale);
    return AlertDialog(
      title: Text(strings.title),
      content: Text(strings.message),
      actions: [
        TextButton(
          onPressed: () {
            Navigator.of(context).pop(RootBackExitAction.cancel);
          },
          child: Text(strings.cancel),
        ),
        TextButton(
          onPressed: () {
            Navigator.of(context).pop(
              RootBackExitAction.keepPlayingInBackground,
            );
          },
          child: Text(strings.keepPlayingInBackground),
        ),
        FilledButton(
          onPressed: () {
            Navigator.of(context).pop(RootBackExitAction.exitApplication);
          },
          child: Text(strings.exitApplication),
        ),
      ],
    );
  }
}

class _RootBackExitStrings {
  const _RootBackExitStrings({
    required this.title,
    required this.message,
    required this.cancel,
    required this.keepPlayingInBackground,
    required this.exitApplication,
  });

  final String title;
  final String message;
  final String cancel;
  final String keepPlayingInBackground;
  final String exitApplication;

  factory _RootBackExitStrings.fromLocale(Locale locale) {
    if (locale.languageCode.toLowerCase() == 'zh') {
      return const _RootBackExitStrings(
        title: '要退出律巢吗？',
        message: '你可以保留后台播放，或完全退出应用。',
        cancel: '取消',
        keepPlayingInBackground: '保留后台播放',
        exitApplication: '退出应用',
      );
    }

    return const _RootBackExitStrings(
      title: 'Exit LyraNest?',
      message: 'Keep playing in the background or exit the app?',
      cancel: 'Cancel',
      keepPlayingInBackground: 'Keep playing',
      exitApplication: 'Exit app',
    );
  }
}
