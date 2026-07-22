import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/offline_downloads_controller.dart';
import '../domain/offline_download_task.dart';
import '../../player/application/player_controller.dart';
import '../../player/presentation/track_artwork.dart';

class OfflineDownloadsPage extends ConsumerWidget {
  const OfflineDownloadsPage({super.key});

  static const _minimumQuotaBytes = 256 * 1024 * 1024;
  static const _maximumQuotaBytes = 20 * 1024 * 1024 * 1024;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final downloads = ref.watch(offlineDownloadsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('离线下载')),
      body: downloads.when(
        data: (state) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _QuotaCard(
              state: state,
              onQuotaChanged: (value) {
                ref
                    .read(offlineDownloadsProvider.notifier)
                    .setQuotaBytes(value);
              },
            ),
            const SizedBox(height: 12),
            _DownloadDirectoryCard(
              state: state,
              onSelect: () {
                return ref
                    .read(offlineDownloadsProvider.notifier)
                    .selectDownloadDirectory();
              },
            ),
            const SizedBox(height: 20),
            Text(
              '下载列表',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 10),
            if (!state.cacheAvailable)
              const _MessageCard(
                icon: Icons.lock_outline,
                message: '登录后即可管理该账户的离线缓存。',
              )
            else if (state.tasks.isEmpty)
              const _MessageCard(
                icon: Icons.download_for_offline_outlined,
                message: '尚无离线内容。请在曲目操作中选择下载。',
              )
            else
              ...state.orderedTasks.map(
                (task) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _DownloadTaskCard(task: task),
                ),
              ),
          ],
        ),
        error: (error, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: _MessageCard(
              icon: Icons.error_outline,
              message: '无法读取离线缓存：$error',
            ),
          ),
        ),
        loading: () => const Center(child: CircularProgressIndicator()),
      ),
    );
  }
}

class _DownloadDirectoryCard extends StatelessWidget {
  const _DownloadDirectoryCard({
    required this.state,
    required this.onSelect,
  });

  final OfflineDownloadsState state;
  final Future<bool> Function() onSelect;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: const Icon(Icons.folder_outlined),
        title: const Text('下载位置'),
        subtitle: Text(
          state.downloadDirectory.isEmpty ? '使用应用存储' : state.downloadDirectory,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () async {
          await onSelect();
        },
      ),
    );
  }
}

class _QuotaCard extends StatelessWidget {
  const _QuotaCard({
    required this.state,
    required this.onQuotaChanged,
  });

  final OfflineDownloadsState state;
  final ValueChanged<int> onQuotaChanged;

  @override
  Widget build(BuildContext context) {
    final usedRatio = state.quotaBytes == 0
        ? 1.0
        : (state.usedBytes / state.quotaBytes).clamp(0, 1).toDouble();
    final sliderValue = state.quotaBytes
        .clamp(
          OfflineDownloadsPage._minimumQuotaBytes,
          OfflineDownloadsPage._maximumQuotaBytes,
        )
        .toDouble();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.storage_outlined),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '离线存储',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                Text('${_formatBytes(state.usedBytes)} / '
                    '${_formatBytes(state.quotaBytes)}'),
              ],
            ),
            const SizedBox(height: 14),
            LinearProgressIndicator(value: usedRatio),
            const SizedBox(height: 10),
            Text(
              '缓存配额',
              style: Theme.of(context).textTheme.labelLarge,
            ),
            Slider(
              value: sliderValue,
              min: OfflineDownloadsPage._minimumQuotaBytes.toDouble(),
              max: OfflineDownloadsPage._maximumQuotaBytes.toDouble(),
              divisions: 79,
              label: _formatBytes(sliderValue.round()),
              onChanged: state.cacheAvailable
                  ? (value) => onQuotaChanged(value.round())
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}

class _DownloadTaskCard extends ConsumerWidget {
  const _DownloadTaskCard({required this.task});

  final OfflineDownloadTask task;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(offlineDownloadsProvider.notifier);
    final progress = task.progress;
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: task.status == OfflineDownloadStatus.completed
            ? () {
                ref
                    .read(playerControllerProvider.notifier)
                    .select(task.trackSnapshot.toTrack(task.trackId));
              }
            : null,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  SizedBox(
                    width: 42,
                    height: 42,
                    child: task.trackSnapshot.artworkUrl == null
                        ? const Icon(Icons.music_note_outlined)
                        : TrackArtwork(
                            artworkUrl: task.trackSnapshot.artworkUrl!,
                            identity: task.trackId,
                            title: task.trackSnapshot.displayTitle,
                            borderRadius: 10,
                          ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      task.trackSnapshot.displayTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ),
                  IconButton(
                    tooltip: '删除本地文件',
                    onPressed: () => controller.delete(task.trackId),
                    icon: const Icon(Icons.delete_outline),
                  ),
                ],
              ),
              if (task.trackSnapshot.displayArtist != null ||
                  task.trackSnapshot.displayAlbum != null) ...[
                const SizedBox(height: 4),
                Text(
                  _trackDetails(task.trackSnapshot),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
              const SizedBox(height: 10),
              LinearProgressIndicator(value: progress),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '${_statusLabel(task.status)} · '
                      '${_formatBytes(task.downloadedBytes)}'
                      '${task.totalBytes == null ? '' : ' / ${_formatBytes(task.totalBytes!)}'}'
                      '${task.trackSnapshot.durationSeconds == null ? '' : ' · ${_formatDuration(task.trackSnapshot.durationSeconds!)}'}',
                    ),
                  ),
                  if (task.status == OfflineDownloadStatus.downloading)
                    TextButton.icon(
                      onPressed: () => controller.pause(task.trackId),
                      icon: const Icon(Icons.pause, size: 18),
                      label: const Text('暂停'),
                    )
                  else if (task.status != OfflineDownloadStatus.completed)
                    TextButton.icon(
                      onPressed: () => controller.resume(task.trackId),
                      icon: const Icon(Icons.play_arrow, size: 18),
                      label: const Text('继续'),
                    ),
                ],
              ),
              if (task.errorMessage != null) ...[
                const SizedBox(height: 4),
                Text(
                  task.errorMessage!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _MessageCard extends StatelessWidget {
  const _MessageCard({
    required this.icon,
    required this.message,
  });

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Row(
          children: [
            Icon(icon),
            const SizedBox(width: 14),
            Expanded(child: Text(message)),
          ],
        ),
      ),
    );
  }
}

String _statusLabel(OfflineDownloadStatus status) {
  return switch (status) {
    OfflineDownloadStatus.queued => '等待下载',
    OfflineDownloadStatus.downloading => '下载中',
    OfflineDownloadStatus.paused => '已暂停',
    OfflineDownloadStatus.failed => '下载失败',
    OfflineDownloadStatus.completed => '已下载',
  };
}

String _formatBytes(int value) {
  if (value < 1024) {
    return '$value B';
  }
  if (value < 1024 * 1024) {
    return '${(value / 1024).toStringAsFixed(1)} KB';
  }
  if (value < 1024 * 1024 * 1024) {
    return '${(value / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  return '${(value / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
}

String _formatDuration(int seconds) {
  final duration = Duration(seconds: seconds);
  final minutes = duration.inMinutes;
  final remainderSeconds = duration.inSeconds.remainder(60);
  return '$minutes:${remainderSeconds.toString().padLeft(2, '0')}';
}

String _trackDetails(OfflineTrackSnapshot snapshot) {
  final details = <String>[];
  final artist = snapshot.displayArtist;
  final album = snapshot.displayAlbum;
  if (artist != null) {
    details.add(artist);
  }
  if (album != null) {
    details.add(album);
  }
  return details.join(' · ');
}
