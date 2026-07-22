import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/network/api_error.dart';
import '../../../features/tracks/data/tracks_api.dart';
import '../../../l10n/l10n.dart';
import '../data/library_management_api.dart';
import '../domain/library_scan_result.dart';
import '../domain/library_status.dart';

class ManagementPage extends ConsumerStatefulWidget {
  const ManagementPage({super.key});

  @override
  ConsumerState<ManagementPage> createState() => _ManagementPageState();
}

class _ManagementPageState extends ConsumerState<ManagementPage> {
  var _isScanning = false;
  Object? _scanError;
  LibraryScanResult? _scanResult;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final status = ref.watch(libraryStatusProvider);
    final statusValue = status.valueOrNull;
    final scanInProgress = _isScanning || statusValue?.scanning == true;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.managementTitle)),
      body: RefreshIndicator(
        onRefresh: _refreshStatus,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              l10n.managementDescription,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            const SizedBox(height: 16),
            _StatusCard(
              status: status,
              onRefresh: _refreshStatus,
            ),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      l10n.rescanLibrary,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    Text(l10n.scanLibraryDescription),
                    if (scanInProgress) ...[
                      const SizedBox(height: 16),
                      const LinearProgressIndicator(),
                    ],
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: scanInProgress ? null : _scanLibrary,
                      icon: _isScanning
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                              ),
                            )
                          : const Icon(Icons.refresh),
                      label: Text(
                        scanInProgress ? l10n.scanningLibrary : l10n.scanNow,
                      ),
                    ),
                    if (_scanError case final error?) ...[
                      const SizedBox(height: 16),
                      _ErrorPanel(
                        title: l10n.scanRequestFailedTitle,
                        message: _scanErrorMessage(error, l10n),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            if (_scanResult case final result?) ...[
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.check_circle,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            l10n.scanResultTitle,
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      _ValueRow(
                        label: l10n.scanResultTotalTracks,
                        value: '${result.total}',
                      ),
                      _ValueRow(
                        label: l10n.scanResultReturnedTracks,
                        value: '${result.tracks.length}',
                      ),
                      _ValueRow(
                        label: l10n.scanResultTime,
                        value: _formatDateTime(result.scannedAt, l10n),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _refreshStatus() async {
    ref.invalidate(libraryStatusProvider);
    try {
      await ref.read(libraryStatusProvider.future);
    } catch (_) {
      // The provider renders the localized error state.
    }
  }

  Future<void> _scanLibrary() async {
    setState(() {
      _isScanning = true;
      _scanError = null;
    });

    try {
      final result = await ref.read(libraryManagementApiProvider).scanLibrary();
      if (!mounted) {
        return;
      }

      setState(() {
        _scanResult = result;
      });

      ref.invalidate(tracksProvider);
      ref.invalidate(libraryStatusProvider);
      try {
        await Future.wait([
          ref.read(tracksProvider.future),
          ref.read(libraryStatusProvider.future),
        ]);
      } catch (_) {
        // Each refreshed provider owns its visible error state.
      }

      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.scanCompleted(result.total))),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _scanError = error;
      });
      ref.invalidate(libraryStatusProvider);
    } finally {
      if (mounted) {
        setState(() {
          _isScanning = false;
        });
      }
    }
  }

  String _scanErrorMessage(Object error, AppLocalizations l10n) {
    final apiError = ApiError.fromObject(error);
    if (apiError.statusCode == 409) {
      return l10n.libraryScanAlreadyInProgress;
    }
    if (apiError.statusCode == 404 || apiError.statusCode == 405) {
      return l10n.libraryScanEndpointUnavailable;
    }
    return l10n.scanFailed(apiError.localizedMessage(l10n));
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({
    required this.status,
    required this.onRefresh,
  });

  final AsyncValue<LibraryStatus> status;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    l10n.libraryStatusTitle,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                IconButton(
                  tooltip: l10n.refresh,
                  onPressed: status.isLoading ? null : onRefresh,
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
            const SizedBox(height: 8),
            status.when(
              loading: () => const LinearProgressIndicator(),
              error: (error, _) => _ErrorPanel(
                title: l10n.libraryStatusLoadFailedTitle,
                message: _statusErrorMessage(error, l10n),
              ),
              data: (value) => _LibraryStatusDetails(status: value),
            ),
          ],
        ),
      ),
    );
  }

  String _statusErrorMessage(Object error, AppLocalizations l10n) {
    final apiError = ApiError.fromObject(error);
    if (apiError.statusCode == 404 || apiError.statusCode == 405) {
      return l10n.libraryStatusEndpointUnavailable;
    }
    return l10n.libraryStatusFailed(apiError.localizedMessage(l10n));
  }
}

class _LibraryStatusDetails extends StatelessWidget {
  const _LibraryStatusDetails({required this.status});

  final LibraryStatus status;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (status.scanning) ...[
          const LinearProgressIndicator(),
          const SizedBox(height: 12),
        ],
        _ValueRow(
          label: l10n.libraryDirectoryLabel,
          value: status.directory.isEmpty
              ? l10n.libraryDirectoryNotConfigured
              : status.directory,
          selectable: true,
        ),
        _ValueRow(
          label: l10n.libraryTrackCountLabel,
          value: '${status.trackCount}',
        ),
        _ValueRow(
          label: l10n.libraryScannerStatusLabel,
          value: status.scanning ? l10n.libraryScanning : l10n.libraryIdle,
        ),
        _ValueRow(
          label: l10n.lastScanLabel,
          value: status.lastScannedAt == null
              ? l10n.neverScanned
              : _formatDateTime(status.lastScannedAt!, l10n),
        ),
        if (status.lastError case final error?) ...[
          const SizedBox(height: 12),
          _ErrorPanel(
            title: l10n.lastScanErrorTitle,
            message: error,
          ),
        ],
      ],
    );
  }
}

class _ValueRow extends StatelessWidget {
  const _ValueRow({
    required this.label,
    required this.value,
    this.selectable = false,
  });

  final String label;
  final String value;
  final bool selectable;

  @override
  Widget build(BuildContext context) {
    final valueWidget = selectable
        ? SelectableText(value, textAlign: TextAlign.end)
        : Text(value, textAlign: TextAlign.end);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: Text(label)),
          const SizedBox(width: 16),
          Flexible(child: valueWidget),
        ],
      ),
    );
  }
}

class _ErrorPanel extends StatelessWidget {
  const _ErrorPanel({
    required this.title,
    required this.message,
  });

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.errorContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.error_outline, color: colors.onErrorContainer),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: colors.onErrorContainer,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    message,
                    style: TextStyle(color: colors.onErrorContainer),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _formatDateTime(DateTime value, AppLocalizations l10n) {
  return DateFormat.yMMMd(l10n.localeName).add_Hm().format(value.toLocal());
}
