import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_error.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../features/tracks/data/tracks_api.dart';
import '../../../features/tracks/domain/track.dart';
import '../../../l10n/l10n.dart';
import '../data/scrape_api.dart';
import '../domain/scrape_models.dart';

class ScrapePage extends ConsumerStatefulWidget {
  const ScrapePage({
    required this.trackId,
    this.track,
    this.searchLimit,
    super.key,
  }) : assert(searchLimit == null || searchLimit > 0);

  final String trackId;
  final Track? track;
  final int? searchLimit;

  @override
  ConsumerState<ScrapePage> createState() => _ScrapePageState();
}

class _ScrapePageState extends ConsumerState<ScrapePage> {
  late final TextEditingController _titleController;
  late final TextEditingController _artistController;
  late final TextEditingController _albumController;

  late Track? _currentTrack;
  late ScrapeSearchQuery _activeQuery;
  String? _selectedCandidateId;
  ScrapeApplyResult? _lastApplied;

  ScrapeSearchRequest get _searchRequest => ScrapeSearchRequest(
        trackId: widget.trackId,
        query: _activeQuery,
      );

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController();
    _artistController = TextEditingController();
    _albumController = TextEditingController();
    _currentTrack = widget.track;
    _activeQuery = ScrapeSearchQuery(limit: widget.searchLimit);
    _populateSearchFields(widget.track);
  }

  @override
  void didUpdateWidget(covariant ScrapePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.trackId != widget.trackId) {
      _currentTrack = widget.track;
      _activeQuery = ScrapeSearchQuery(limit: widget.searchLimit);
      _selectedCandidateId = null;
      _lastApplied = null;
      _populateSearchFields(widget.track);
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _artistController.dispose();
    _albumController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final strings = _ScrapeWorkbenchStrings.of(context);
    final search = ref.watch(scrapeSearchProvider(_searchRequest));

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.scrapeTitle),
        actions: [
          IconButton(
            tooltip: l10n.searchAgain,
            onPressed: search.isLoading ? null : _searchAgain,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth >= 980) {
            return _buildDesktopWorkbench(
              context,
              search,
              strings,
            );
          }
          return _buildMobileWorkbench(
            context,
            search,
            strings,
          );
        },
      ),
    );
  }

  Widget _buildDesktopWorkbench(
    BuildContext context,
    AsyncValue<ScrapeSearchResult> search,
    _ScrapeWorkbenchStrings strings,
  ) {
    final l10n = context.l10n;
    final selectedCandidate = _selectedCandidate(search);

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 372,
            child: Card(
              clipBehavior: Clip.antiAlias,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _TrackSummaryCard(
                    track: _currentTrack,
                    trackId: widget.trackId,
                    strings: strings,
                  ),
                  const SizedBox(height: 16),
                  _SearchForm(
                    titleController: _titleController,
                    artistController: _artistController,
                    albumController: _albumController,
                    isSearching: search.isLoading,
                    onSearch: _searchWithEditedDetails,
                    onReset: _resetSearchFields,
                    strings: strings,
                  ),
                  const SizedBox(height: 20),
                  _SearchQuerySummary(
                    query: _activeQuery,
                    strings: strings,
                  ),
                  const SizedBox(height: 12),
                  _CandidateListSection(
                    search: search,
                    selectedCandidateId: selectedCandidate?.id,
                    onSelect: _selectCandidate,
                    strings: strings,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Card(
              clipBehavior: Clip.antiAlias,
              child: _buildDesktopDetails(
                context,
                search,
                selectedCandidate,
                l10n,
                strings,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDesktopDetails(
    BuildContext context,
    AsyncValue<ScrapeSearchResult> search,
    ScrapeCandidate? selectedCandidate,
    AppLocalizations l10n,
    _ScrapeWorkbenchStrings strings,
  ) {
    if (search.isLoading) {
      return _WorkbenchPlaceholder(
        icon: Icons.travel_explore,
        title: strings.searching,
        message: strings.searchingDetails,
      );
    }
    if (search.hasError) {
      return _ScrapeErrorState(
        message: _friendlyError(search.error!, l10n),
        onRetry: _searchAgain,
      );
    }
    if (selectedCandidate == null) {
      return _WorkbenchPlaceholder(
        icon: Icons.auto_fix_high_outlined,
        title: l10n.noScrapeCandidatesTitle,
        message: l10n.noScrapeCandidatesMessage,
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_lastApplied case final applied?) ...[
            _AppliedPanel(result: applied),
            const SizedBox(height: 16),
          ],
          Text(
            strings.candidateDetails,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 4),
          Text(l10n.scrapeReviewDifferences),
          const SizedBox(height: 16),
          _CandidateDetail(
            key: ValueKey(selectedCandidate.id),
            candidate: selectedCandidate,
            track: _currentTrack,
            differences:
                _candidateDifferences(selectedCandidate, _currentTrack),
            onApply: (fields) => _applyCandidate(selectedCandidate, fields),
            embedded: true,
            strings: strings,
          ),
        ],
      ),
    );
  }

  Widget _buildMobileWorkbench(
    BuildContext context,
    AsyncValue<ScrapeSearchResult> search,
    _ScrapeWorkbenchStrings strings,
  ) {
    final l10n = context.l10n;
    final selectedCandidate = _selectedCandidate(search);

    return RefreshIndicator(
      onRefresh: _searchAgain,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          _TrackSummaryCard(
            track: _currentTrack,
            trackId: widget.trackId,
            strings: strings,
          ),
          const SizedBox(height: 16),
          _SearchForm(
            titleController: _titleController,
            artistController: _artistController,
            albumController: _albumController,
            isSearching: search.isLoading,
            onSearch: _searchWithEditedDetails,
            onReset: _resetSearchFields,
            strings: strings,
          ),
          const SizedBox(height: 20),
          _SearchQuerySummary(
            query: _activeQuery,
            strings: strings,
          ),
          const SizedBox(height: 12),
          if (search.isLoading)
            const _MobileLoadingPanel()
          else if (search.hasError)
            _ScrapeErrorState(
              message: _friendlyError(search.error!, l10n),
              onRetry: _searchAgain,
            )
          else if (search.value!.candidates.isEmpty)
            _EmptyCandidatesPanel(onRetry: _searchAgain)
          else ...[
            _CandidateListSection(
              search: search,
              selectedCandidateId: selectedCandidate?.id,
              onSelect: _selectCandidate,
              strings: strings,
            ),
            if (selectedCandidate != null) ...[
              const SizedBox(height: 20),
              if (_lastApplied case final applied?) ...[
                _AppliedPanel(result: applied),
                const SizedBox(height: 16),
              ],
              Text(
                strings.candidateDetails,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 4),
              Text(l10n.scrapeReviewDifferences),
              const SizedBox(height: 12),
              _CandidateDetail(
                key: ValueKey(selectedCandidate.id),
                candidate: selectedCandidate,
                track: _currentTrack,
                differences: _candidateDifferences(
                  selectedCandidate,
                  _currentTrack,
                ),
                onApply: (fields) => _applyCandidate(selectedCandidate, fields),
                strings: strings,
              ),
            ],
          ],
        ],
      ),
    );
  }

  ScrapeCandidate? _selectedCandidate(AsyncValue<ScrapeSearchResult> search) {
    final candidates = search.valueOrNull?.candidates;
    if (candidates == null || candidates.isEmpty) {
      return null;
    }
    for (final candidate in candidates) {
      if (candidate.id == _selectedCandidateId) {
        return candidate;
      }
    }
    return candidates.first;
  }

  void _selectCandidate(String candidateId) {
    setState(() {
      _selectedCandidateId = candidateId;
    });
  }

  void _populateSearchFields(Track? track) {
    _titleController.text = track?.title ?? '';
    _artistController.text = track?.artist ?? '';
    _albumController.text = track?.album ?? '';
  }

  void _resetSearchFields() {
    _populateSearchFields(_currentTrack);
  }

  Future<void> _searchWithEditedDetails() async {
    final query = ScrapeSearchQuery(
      title: _titleController.text,
      artist: _artistController.text,
      album: _albumController.text,
      limit: widget.searchLimit,
    );
    final request = ScrapeSearchRequest(
      trackId: widget.trackId,
      query: query,
    );

    setState(() {
      _activeQuery = query;
      _selectedCandidateId = null;
      _lastApplied = null;
    });
    ref.invalidate(scrapeSearchProvider(request));
    try {
      await ref.read(scrapeSearchProvider(request).future);
    } catch (_) {
      // The provider renders the localized error state.
    }
  }

  Future<void> _searchAgain() async {
    final request = _searchRequest;
    ref.invalidate(scrapeSearchProvider(request));
    try {
      await ref.read(scrapeSearchProvider(request).future);
    } catch (_) {
      // The provider renders the localized error state.
    }
  }

  Future<void> _applyCandidate(
    ScrapeCandidate candidate,
    List<ScrapeField> fields,
  ) async {
    if (fields.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.scrapeSelectAtLeastOneField)),
      );
      return;
    }

    try {
      final result = await ref.read(scrapeApiProvider).apply(
            trackId: widget.trackId,
            candidateId: candidate.id,
            provider: candidate.provider,
            fields: fields,
          );
      ref.invalidate(tracksProvider);
      try {
        await ref.read(tracksProvider.future);
      } catch (_) {
        // The tracks page owns its refresh error state.
      }

      if (!mounted) {
        return;
      }
      setState(() {
        _lastApplied = result;
        _currentTrack = result.track;
        _populateSearchFields(result.track);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.l10n.scrapeApplySucceeded(
              result.provider,
              result.appliedFields.length,
            ),
          ),
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      final l10n = context.l10n;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            l10n.scrapeApplyFailed(_friendlyError(error, l10n)),
          ),
        ),
      );
    }
  }

  String _friendlyError(Object error, AppLocalizations l10n) {
    final apiError = ApiError.fromObject(error);
    if (apiError.statusCode == 404 || apiError.statusCode == 405) {
      return l10n.scrapeEndpointUnavailable;
    }
    return apiError.localizedMessage(l10n);
  }
}

class _TrackSummaryCard extends StatelessWidget {
  const _TrackSummaryCard({
    required this.track,
    required this.trackId,
    required this.strings,
  });

  final Track? track;
  final String trackId;
  final _ScrapeWorkbenchStrings strings;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              strings.currentTrack,
              style: Theme.of(context).textTheme.labelLarge,
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.music_note, size: 36),
                const SizedBox(width: 12),
                Expanded(
                  child: track == null
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              strings.trackDetailsUnavailable,
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const SizedBox(height: 4),
                            SelectableText(trackId),
                          ],
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              track!.localizedTitle(l10n),
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const SizedBox(height: 4),
                            Text(track!.localizedArtist(l10n)),
                            if (track!.album?.trim().isNotEmpty == true) ...[
                              const SizedBox(height: 2),
                              Text(track!.album!),
                            ],
                          ],
                        ),
                ),
              ],
            ),
            if (track?.genres.isNotEmpty == true) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final genre in track!.genres)
                    Chip(
                      visualDensity: VisualDensity.compact,
                      label: Text(genre),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SearchForm extends StatelessWidget {
  const _SearchForm({
    required this.titleController,
    required this.artistController,
    required this.albumController,
    required this.isSearching,
    required this.onSearch,
    required this.onReset,
    required this.strings,
  });

  final TextEditingController titleController;
  final TextEditingController artistController;
  final TextEditingController albumController;
  final bool isSearching;
  final VoidCallback onSearch;
  final VoidCallback onReset;
  final _ScrapeWorkbenchStrings strings;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final titleField = TextField(
      key: const ValueKey('scrape-search-title'),
      controller: titleController,
      enabled: !isSearching,
      textInputAction: TextInputAction.next,
      decoration: InputDecoration(
        labelText: l10n.scrapeFieldTitle,
        prefixIcon: const Icon(Icons.music_note_outlined),
        border: const OutlineInputBorder(),
      ),
    );
    final artistField = TextField(
      key: const ValueKey('scrape-search-artist'),
      controller: artistController,
      enabled: !isSearching,
      textInputAction: TextInputAction.next,
      decoration: InputDecoration(
        labelText: l10n.scrapeFieldArtist,
        prefixIcon: const Icon(Icons.person_outline),
        border: const OutlineInputBorder(),
      ),
    );
    final albumField = TextField(
      key: const ValueKey('scrape-search-album'),
      controller: albumController,
      enabled: !isSearching,
      onSubmitted: (_) => onSearch(),
      decoration: InputDecoration(
        labelText: l10n.scrapeFieldAlbum,
        prefixIcon: const Icon(Icons.album_outlined),
        border: const OutlineInputBorder(),
      ),
    );

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              strings.searchDetails,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(strings.searchDetailsHint),
            const SizedBox(height: 16),
            LayoutBuilder(
              builder: (context, constraints) {
                if (constraints.maxWidth >= 640) {
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: titleField),
                      const SizedBox(width: 12),
                      Expanded(child: artistField),
                      const SizedBox(width: 12),
                      Expanded(child: albumField),
                    ],
                  );
                }

                return Column(
                  children: [
                    titleField,
                    const SizedBox(height: 12),
                    artistField,
                    const SizedBox(height: 12),
                    albumField,
                  ],
                );
              },
            ),
            const SizedBox(height: 12),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: isSearching ? null : onReset,
                  icon: const Icon(Icons.undo),
                  label: Text(strings.reset),
                ),
                FilledButton.icon(
                  onPressed: isSearching ? null : onSearch,
                  icon: isSearching
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.search),
                  label: Text(l10n.searchAgain),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SearchQuerySummary extends StatelessWidget {
  const _SearchQuerySummary({
    required this.query,
    required this.strings,
  });

  final ScrapeSearchQuery query;
  final _ScrapeWorkbenchStrings strings;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final entries = <(String, String)>[
      if (query.title?.trim().isNotEmpty == true)
        (l10n.scrapeFieldTitle, query.title!.trim()),
      if (query.artist?.trim().isNotEmpty == true)
        (l10n.scrapeFieldArtist, query.artist!.trim()),
      if (query.album?.trim().isNotEmpty == true)
        (l10n.scrapeFieldAlbum, query.album!.trim()),
    ];

    if (entries.isEmpty) {
      return Text(
        strings.usingSavedTrackMetadata,
        style: Theme.of(context).textTheme.bodySmall,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          strings.activeSearch,
          style: Theme.of(context).textTheme.labelLarge,
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final entry in entries)
              Chip(
                visualDensity: VisualDensity.compact,
                label: Text('${entry.$1}: ${entry.$2}'),
              ),
          ],
        ),
      ],
    );
  }
}

class _CandidateListSection extends StatelessWidget {
  const _CandidateListSection({
    required this.search,
    required this.selectedCandidateId,
    required this.onSelect,
    required this.strings,
  });

  final AsyncValue<ScrapeSearchResult> search;
  final String? selectedCandidateId;
  final ValueChanged<String> onSelect;
  final _ScrapeWorkbenchStrings strings;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    if (search.isLoading) {
      return const _CandidateListLoading();
    }
    if (search.hasError) {
      return Text(
        l10n.scrapeSearchFailedTitle,
        style: Theme.of(context).textTheme.titleMedium,
      );
    }
    final candidates = search.value!.candidates;
    if (candidates.isEmpty) {
      return Text(
        l10n.noScrapeCandidatesTitle,
        style: Theme.of(context).textTheme.titleMedium,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          strings.candidates,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 2),
        Text(
          l10n.scrapeCandidatesCount(candidates.length),
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 8),
        for (final candidate in candidates) ...[
          _CandidateListItem(
            candidate: candidate,
            selected: candidate.id == selectedCandidateId,
            onTap: () => onSelect(candidate.id),
          ),
          const SizedBox(height: 8),
        ],
      ],
    );
  }
}

class _CandidateListItem extends StatelessWidget {
  const _CandidateListItem({
    required this.candidate,
    required this.selected,
    required this.onTap,
  });

  final ScrapeCandidate candidate;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = Theme.of(context).colorScheme;
    final title =
        candidate.metadata[ScrapeField.title]?.toString() ?? l10n.untitledTrack;
    final artist = candidate.metadata[ScrapeField.artist]?.toString();
    final album = candidate.metadata[ScrapeField.album]?.toString();
    final details = [artist, album]
        .whereType<String>()
        .where((value) => value.trim().isNotEmpty)
        .join(' · ');

    return Material(
      color: selected ? colors.secondaryContainer : colors.surfaceContainerLow,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Icon(
                selected
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
                color: selected ? colors.onSecondaryContainer : null,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      details.isEmpty ? candidate.provider : details,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                l10n.scrapeConfidence((candidate.confidence * 100).round()),
                style: Theme.of(context).textTheme.labelSmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CandidateDetail extends StatefulWidget {
  const _CandidateDetail({
    required this.candidate,
    required this.track,
    required this.differences,
    required this.onApply,
    required this.strings,
    this.embedded = false,
    super.key,
  });

  final ScrapeCandidate candidate;
  final Track? track;
  final List<ScrapeFieldDifference> differences;
  final Future<void> Function(List<ScrapeField> fields) onApply;
  final _ScrapeWorkbenchStrings strings;
  final bool embedded;

  @override
  State<_CandidateDetail> createState() => _CandidateDetailState();
}

class _CandidateDetailState extends State<_CandidateDetail> {
  late Set<ScrapeField> _selectedFields;
  var _isApplying = false;

  @override
  void initState() {
    super.initState();
    _selectedFields = _initialFields();
  }

  @override
  void didUpdateWidget(covariant _CandidateDetail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.candidate.id != widget.candidate.id ||
        oldWidget.differences != widget.differences) {
      _selectedFields = _initialFields();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final candidate = widget.candidate;
    final percentage = (candidate.confidence * 100).round();
    final candidateTitle = candidate.metadata[ScrapeField.title]?.toString() ??
        widget.track?.localizedTitle(l10n) ??
        l10n.untitledTrack;
    final availableFields =
        widget.differences.map((difference) => difference.field).toSet();
    final allSelected = availableFields.isNotEmpty &&
        availableFields.every(_selectedFields.contains);

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    candidateTitle,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 4),
                  Text(l10n.scrapeProvider(candidate.provider)),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Text(
              l10n.scrapeConfidence(percentage),
              style: Theme.of(context).textTheme.labelLarge,
            ),
          ],
        ),
        const SizedBox(height: 10),
        LinearProgressIndicator(value: candidate.confidence),
        if (candidate.sourceUrl case final sourceUrl?) ...[
          const SizedBox(height: 16),
          Text(
            widget.strings.source,
            style: Theme.of(context).textTheme.labelSmall,
          ),
          const SizedBox(height: 2),
          SelectableText(sourceUrl),
        ],
        const SizedBox(height: 16),
        if (widget.differences.isEmpty)
          Text(l10n.scrapeNoDifferences)
        else ...[
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                l10n.scrapeFieldsSelected(_selectedFields.length),
                style: Theme.of(context).textTheme.labelLarge,
              ),
              TextButton(
                onPressed:
                    _isApplying ? null : () => _toggleAll(availableFields),
                child: Text(
                  allSelected
                      ? widget.strings.clearSelection
                      : widget.strings.selectAll,
                ),
              ),
            ],
          ),
          for (final difference in widget.differences)
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: _selectedFields.contains(difference.field),
              onChanged: _isApplying
                  ? null
                  : (selected) {
                      setState(() {
                        if (selected ?? false) {
                          _selectedFields.add(difference.field);
                        } else {
                          _selectedFields.remove(difference.field);
                        }
                      });
                    },
              title: Text(_fieldLabel(difference.field, l10n)),
              subtitle: _DifferenceValues(difference: difference),
            ),
        ],
        const SizedBox(height: 8),
        FilledButton.icon(
          onPressed: _isApplying || _selectedFields.isEmpty ? null : _apply,
          icon: _isApplying
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.check),
          label: Text(
            _isApplying ? l10n.applyingCandidate : l10n.applyCandidate,
          ),
        ),
      ],
    );

    if (widget.embedded) {
      return content;
    }
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: content,
      ),
    );
  }

  Set<ScrapeField> _initialFields() {
    final changed = widget.differences
        .where((difference) => difference.changed)
        .map((difference) => difference.field)
        .toSet();
    if (changed.isNotEmpty) {
      return changed;
    }
    return widget.differences.map((difference) => difference.field).toSet();
  }

  void _toggleAll(Set<ScrapeField> availableFields) {
    setState(() {
      if (availableFields.every(_selectedFields.contains)) {
        _selectedFields.removeAll(availableFields);
      } else {
        _selectedFields.addAll(availableFields);
      }
    });
  }

  Future<void> _apply() async {
    setState(() {
      _isApplying = true;
    });
    try {
      await widget.onApply(_selectedFields.toList(growable: false));
    } finally {
      if (mounted) {
        setState(() {
          _isApplying = false;
        });
      }
    }
  }
}

class _DifferenceValues extends StatelessWidget {
  const _DifferenceValues({required this.difference});

  final ScrapeFieldDifference difference;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final current = _displayValue(difference.current, l10n);
    final candidate = _displayValue(difference.candidate, l10n);

    return LayoutBuilder(
      builder: (context, constraints) {
        final currentValue = _LabeledValue(
          label: l10n.scrapeCurrentValue,
          value: current,
        );
        final candidateValue = _LabeledValue(
          label: l10n.scrapeCandidateValue,
          value: candidate,
          emphasized: difference.changed,
        );

        if (constraints.maxWidth < 420) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              currentValue,
              const SizedBox(height: 6),
              candidateValue,
            ],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: currentValue),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8, vertical: 18),
              child: Icon(Icons.arrow_forward, size: 16),
            ),
            Expanded(child: candidateValue),
          ],
        );
      },
    );
  }
}

class _LabeledValue extends StatelessWidget {
  const _LabeledValue({
    required this.label,
    required this.value,
    this.emphasized = false,
  });

  final String label;
  final String value;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: theme.textTheme.labelSmall),
        const SizedBox(height: 2),
        Text(
          value,
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          style: emphasized
              ? theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                )
              : theme.textTheme.bodyMedium,
        ),
      ],
    );
  }
}

class _AppliedPanel extends StatelessWidget {
  const _AppliedPanel({required this.result});

  final ScrapeApplyResult result;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = Theme.of(context).colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.primaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Icon(Icons.check_circle, color: colors.onPrimaryContainer),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                l10n.scrapeApplySucceeded(
                  result.provider,
                  result.appliedFields.length,
                ),
                style: TextStyle(color: colors.onPrimaryContainer),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyCandidatesPanel extends StatelessWidget {
  const _EmptyCandidatesPanel({required this.onRetry});

  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            EmptyState(
              title: l10n.noScrapeCandidatesTitle,
              message: l10n.noScrapeCandidatesMessage,
              icon: Icons.auto_fix_high_outlined,
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: Text(l10n.searchAgain),
            ),
          ],
        ),
      ),
    );
  }
}

class _ScrapeErrorState extends StatelessWidget {
  const _ScrapeErrorState({
    required this.message,
    required this.onRetry,
  });

  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off, size: 48),
            const SizedBox(height: 16),
            Text(
              l10n.scrapeSearchFailedTitle,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: Text(l10n.retry),
            ),
          ],
        ),
      ),
    );
  }
}

class _WorkbenchPlaceholder extends StatelessWidget {
  const _WorkbenchPlaceholder({
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48),
            const SizedBox(height: 16),
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(message, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

class _MobileLoadingPanel extends StatelessWidget {
  const _MobileLoadingPanel();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 48),
      child: Center(child: CircularProgressIndicator()),
    );
  }
}

class _CandidateListLoading extends StatelessWidget {
  const _CandidateListLoading();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 16),
      child: Center(child: CircularProgressIndicator()),
    );
  }
}

class _ScrapeWorkbenchStrings {
  const _ScrapeWorkbenchStrings._(this._isChinese);

  final bool _isChinese;

  factory _ScrapeWorkbenchStrings.of(BuildContext context) {
    return _ScrapeWorkbenchStrings._(
      Localizations.localeOf(context).languageCode == 'zh',
    );
  }

  String get currentTrack => _isChinese ? '当前曲目' : 'Current track';

  String get trackDetailsUnavailable =>
      _isChinese ? '暂时无法读取曲目信息' : 'Track details are unavailable';

  String get searchDetails => _isChinese ? '搜索条件' : 'Search details';

  String get searchDetailsHint => _isChinese
      ? '可修改标题、艺术家和专辑后重新搜索。'
      : 'Edit the title, artist, or album before searching again.';

  String get reset => _isChinese ? '重置' : 'Reset';

  String get usingSavedTrackMetadata => _isChinese
      ? '正在使用曲目已保存的元数据搜索。'
      : 'Searching with the track’s saved metadata.';

  String get activeSearch => _isChinese ? '当前搜索条件' : 'Active search';

  String get candidates => _isChinese ? '候选列表' : 'Candidates';

  String get candidateDetails => _isChinese ? '候选详情' : 'Candidate details';

  String get searching => _isChinese ? '正在搜索候选结果' : 'Searching candidates';

  String get searchingDetails => _isChinese
      ? '正在从元数据来源获取匹配结果。'
      : 'Looking for matches from metadata providers.';

  String get source => _isChinese ? '来源链接' : 'Source link';

  String get selectAll => _isChinese ? '全选' : 'Select all';

  String get clearSelection => _isChinese ? '清空选择' : 'Clear selection';
}

List<ScrapeFieldDifference> _candidateDifferences(
  ScrapeCandidate candidate,
  Track? track,
) {
  final differences = <ScrapeField, ScrapeFieldDifference>{
    for (final difference in candidate.differences)
      difference.field: difference,
  };
  for (final entry in candidate.metadata.entries) {
    if (differences.containsKey(entry.key)) {
      continue;
    }
    final current = _currentValue(track, entry.key);
    differences[entry.key] = ScrapeFieldDifference(
      field: entry.key,
      current: current,
      candidate: entry.value,
      changed: current?.toString() != entry.value?.toString(),
    );
  }

  return [
    for (final field in ScrapeField.values)
      if (differences[field] case final difference?) difference,
  ];
}

Object? _currentValue(Track? track, ScrapeField field) {
  if (track == null) {
    return null;
  }
  return switch (field) {
    ScrapeField.title => track.title,
    ScrapeField.artist => track.artist,
    ScrapeField.album => track.album,
    ScrapeField.genre => track.genres.isEmpty ? null : track.genres.join(', '),
    _ => null,
  };
}

String _displayValue(Object? value, AppLocalizations l10n) {
  if (value == null || value.toString().trim().isEmpty) {
    return l10n.scrapeNoValue;
  }
  return value.toString();
}

String _fieldLabel(ScrapeField field, AppLocalizations l10n) {
  return switch (field) {
    ScrapeField.title => l10n.scrapeFieldTitle,
    ScrapeField.artist => l10n.scrapeFieldArtist,
    ScrapeField.album => l10n.scrapeFieldAlbum,
    ScrapeField.albumArtist => l10n.scrapeFieldAlbumArtist,
    ScrapeField.year => l10n.scrapeFieldYear,
    ScrapeField.trackNumber => l10n.scrapeFieldTrackNumber,
    ScrapeField.discNumber => l10n.scrapeFieldDiscNumber,
    ScrapeField.genre => l10n.scrapeFieldGenre,
    ScrapeField.artworkUrl => l10n.scrapeFieldArtwork,
    ScrapeField.lyrics => l10n.scrapeFieldLyrics,
  };
}
