import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../tracks/domain/track.dart';
import '../application/offline_downloads_controller.dart';
import '../domain/offline_download_task.dart';

class OfflineDownloadButton extends ConsumerWidget {
  const OfflineDownloadButton({
    required this.track,
    this.compact = true,
    super.key,
  });

  final Track track;
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final downloads = ref.watch(offlineDownloadsProvider);
    final task = downloads.valueOrNull?.tasks[track.id];
    final action = _actionFor(task);
    final controller = ref.read(offlineDownloadsProvider.notifier);

    Future<void> runAction() async {
      try {
        switch (action) {
          case _DownloadButtonAction.download:
            return controller.downloadTrack(track);
          case _DownloadButtonAction.cancel:
            return controller.delete(track.id);
          case _DownloadButtonAction.pause:
            return controller.pause(track.id);
          case _DownloadButtonAction.resume:
            return controller.resume(track.id);
          case _DownloadButtonAction.none:
            return;
        }
      } catch (error) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('离线下载操作失败：$error')),
          );
        }
      }
    }

    final config = _configFor(task);
    final isLoading = downloads.isLoading && task == null;
    final enabled = !isLoading && action != _DownloadButtonAction.none;

    if (compact) {
      return IconButton(
        tooltip: config.tooltip,
        onPressed: enabled ? runAction : null,
        icon: _actionIcon(task, config.icon),
      );
    }
    return OutlinedButton.icon(
      onPressed: enabled ? runAction : null,
      icon: _actionIcon(task, config.icon, size: 18),
      label: Text(config.label),
    );
  }
}

enum _DownloadButtonAction {
  download,
  cancel,
  pause,
  resume,
  none,
}

_DownloadButtonAction _actionFor(OfflineDownloadTask? task) {
  return switch (task?.status) {
    OfflineDownloadStatus.queued => _DownloadButtonAction.cancel,
    OfflineDownloadStatus.downloading => _DownloadButtonAction.pause,
    OfflineDownloadStatus.paused ||
    OfflineDownloadStatus.failed =>
      _DownloadButtonAction.resume,
    OfflineDownloadStatus.completed => _DownloadButtonAction.none,
    _ => _DownloadButtonAction.download,
  };
}

({IconData icon, String label, String tooltip}) _configFor(
  OfflineDownloadTask? task,
) {
  if (task?.status == OfflineDownloadStatus.completed) {
    return (
      icon: Icons.download_done_outlined,
      label: 'Downloaded',
      tooltip: 'Downloaded',
    );
  }
  return switch (task?.status) {
    OfflineDownloadStatus.queued => (
        icon: Icons.hourglass_top_outlined,
        label: '等待下载',
        tooltip: '等待下载，点击取消',
      ),
    OfflineDownloadStatus.downloading => (
        icon: Icons.pause,
        label: '下载中',
        tooltip: '下载中，点击暂停',
      ),
    OfflineDownloadStatus.paused => (
        icon: Icons.play_circle_outline,
        label: '已暂停',
        tooltip: '已暂停，点击继续',
      ),
    OfflineDownloadStatus.failed => (
        icon: Icons.refresh_outlined,
        label: '重试下载',
        tooltip: '下载失败，点击重试',
      ),
    OfflineDownloadStatus.completed => (
        icon: Icons.download_done_outlined,
        label: '已下载',
        tooltip: '已下载，点击删除本地文件',
      ),
    null => (
        icon: Icons.download_outlined,
        label: '下载',
        tooltip: '下载到本地',
      ),
  };
}

Widget _actionIcon(
  OfflineDownloadTask? task,
  IconData icon, {
  double size = 24,
}) {
  if (task?.status != OfflineDownloadStatus.downloading) {
    return Icon(icon, size: size);
  }

  return SizedBox.square(
    dimension: size,
    child: Stack(
      alignment: Alignment.center,
      children: [
        CircularProgressIndicator(
          value: task?.progress?.clamp(0, 1).toDouble(),
          strokeWidth: size <= 18 ? 1.5 : 2,
        ),
        Icon(icon, size: size * 0.58),
      ],
    ),
  );
}
