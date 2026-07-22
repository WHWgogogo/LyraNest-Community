import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/app_lifecycle/data/app_lifecycle_platform.dart';
import '../../features/player/application/player_controller.dart';
import '../../l10n/l10n.dart';

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
        builder: (context) => const _RootBackExitDialog(),
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
  const _RootBackExitDialog();

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return AlertDialog(
      title: Text(l10n.exitApplicationTitle),
      content: Text(l10n.exitApplicationMessage),
      actions: [
        TextButton(
          onPressed: () {
            Navigator.of(context).pop(RootBackExitAction.cancel);
          },
          child: Text(l10n.cancel),
        ),
        TextButton(
          onPressed: () {
            Navigator.of(context).pop(
              RootBackExitAction.keepPlayingInBackground,
            );
          },
          child: Text(l10n.keepPlayingInBackground),
        ),
        FilledButton(
          onPressed: () {
            Navigator.of(context).pop(RootBackExitAction.exitApplication);
          },
          child: Text(l10n.exitApplication),
        ),
      ],
    );
  }
}
