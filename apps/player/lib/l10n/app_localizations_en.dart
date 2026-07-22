// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'LyraNest Community';

  @override
  String get tracksTitle => 'Tracks';

  @override
  String get lyricsTitle => 'Lyrics';

  @override
  String get playerTitle => 'Player';

  @override
  String get settingsTitle => 'Server settings';

  @override
  String get serverSettingsTooltip => 'Server settings';

  @override
  String get loading => 'Loading...';

  @override
  String get requestFailedTitle => 'Request failed';

  @override
  String get networkRequestFailed => 'Network request failed';

  @override
  String networkErrorWithStatusCode(String message, int statusCode) {
    return '$message (HTTP $statusCode)';
  }

  @override
  String totalTrackCount(int count) {
    return 'Total tracks: $count';
  }

  @override
  String get noTracksTitle => 'No tracks';

  @override
  String get noTracksMessage => 'The server returned an empty track list.';

  @override
  String get lyricsTooltip => 'Lyrics';

  @override
  String get unknownArtist => 'Unknown artist';

  @override
  String get untitledTrack => 'Untitled track';

  @override
  String get noLyricsTitle => 'No lyrics';

  @override
  String get noLyricsMessage => 'The server returned empty lyrics content.';

  @override
  String get nothingPlayingTitle => 'Nothing playing';

  @override
  String get nothingPlayingMessage =>
      'Select a song from the track list first.';

  @override
  String get noTrackSelected => 'No track selected';

  @override
  String get selectMusicFromTracks => 'Select music from the track list';

  @override
  String get play => 'Play';

  @override
  String get pause => 'Pause';

  @override
  String get viewLyrics => 'View lyrics';

  @override
  String get serverUrlLabel => 'Server URL';

  @override
  String get serverUrlExample => 'Example: http://127.0.0.1:8080';

  @override
  String get save => 'Save';

  @override
  String get connecting => 'Connecting...';

  @override
  String get serverConnectionSucceeded => 'Connection successful';

  @override
  String serverConnectionFailed(String message) {
    return 'Could not connect to server: $message';
  }

  @override
  String get serverConnectionFailedGeneric =>
      'Could not connect to the server. Check the address and network, then try again.';

  @override
  String get invalidServerUrl => 'Enter a valid HTTP or HTTPS server address.';

  @override
  String get serverHealthCheckInvalidResponse =>
      'The health check returned an invalid response.';

  @override
  String serverHealthCheckUnexpectedStatus(String status) {
    return 'The health check returned status \"$status\" instead of \"ok\".';
  }

  @override
  String serverSettingsLoadFailed(String message) {
    return 'Could not load server settings: $message';
  }

  @override
  String get desktopLyricsTitle => 'Desktop lyrics';

  @override
  String get desktopLyricsWindowsDescription =>
      'Native Windows transparent lyrics overlay is available.';

  @override
  String get desktopLyricsAndroidDescription =>
      'Android system lyrics overlay is available after permission is granted.';

  @override
  String get desktopLyricsUnsupportedDescription =>
      'Lyrics overlay capabilities are not defined for this platform.';

  @override
  String get windowsLyricsOverlayNotImplemented =>
      'Windows lyrics overlay is unavailable.';

  @override
  String get androidLyricsOverlayNotImplemented =>
      'Android lyrics overlay is unavailable.';

  @override
  String get unsupportedLyricsOverlayNotImplemented =>
      'Lyrics overlay is unavailable on this platform.';

  @override
  String get desktopLyricsDescription =>
      'Show the current lyric line in a system overlay while music plays.';

  @override
  String get desktopLyricsLoading => 'Loading lyrics for desktop display...';

  @override
  String get desktopLyricsNoLyrics => 'No lyrics are available for this track.';

  @override
  String get desktopLyricsUntimedLyrics =>
      'Showing untimed lyrics in the desktop overlay.';

  @override
  String get desktopLyricsLyricsLoadFailed =>
      'Could not load lyrics; playback continues.';

  @override
  String get desktopLyricsPermissionRequired =>
      'Grant the required permission to show desktop lyrics.';

  @override
  String get desktopLyricsRequestPermission => 'Grant permission';

  @override
  String desktopLyricsCapabilityUnavailable(String message) {
    return 'Could not load desktop lyrics capabilities: $message';
  }

  @override
  String get desktopLyricsSystemOverlay => 'System overlay';

  @override
  String get desktopLyricsTransparentWindow => 'Transparent window';

  @override
  String get desktopLyricsClickThrough => 'Click-through';

  @override
  String get desktopLyricsLockPosition => 'Lock position';

  @override
  String get desktopLyricsRuntimePermission => 'Runtime permission';

  @override
  String get capabilitySupported => 'Supported';

  @override
  String get capabilityNotSupported => 'Not supported';

  @override
  String get capabilityRequired => 'Required';

  @override
  String get capabilityNotRequired => 'Not required';

  @override
  String get managementTitle => 'Music management';

  @override
  String get managementTooltip => 'Manage music library';

  @override
  String get managementDescription =>
      'Review the server library status, rescan its music directory, and refresh the track list.';

  @override
  String get libraryStatusTitle => 'Library status';

  @override
  String get libraryDirectoryLabel => 'Music directory';

  @override
  String get libraryDirectoryNotConfigured => 'Not configured';

  @override
  String get libraryTrackCountLabel => 'Track count';

  @override
  String get libraryScannerStatusLabel => 'Scanner status';

  @override
  String get libraryScanning => 'Scanning';

  @override
  String get libraryIdle => 'Idle';

  @override
  String get lastScanLabel => 'Last scan';

  @override
  String get neverScanned => 'No completed scan yet';

  @override
  String get lastScanErrorTitle => 'Last scan error';

  @override
  String get refresh => 'Refresh';

  @override
  String get rescanLibrary => 'Rescan music library';

  @override
  String get scanLibraryDescription =>
      'Scan the configured server directory for added, updated, or removed audio files.';

  @override
  String get scanNow => 'Start scan';

  @override
  String get scanningLibrary => 'Scanning library...';

  @override
  String scanCompleted(int count) {
    return 'Library scan completed with $count tracks.';
  }

  @override
  String get scanRequestFailedTitle => 'Scan request failed';

  @override
  String scanFailed(String message) {
    return 'Could not scan the library: $message';
  }

  @override
  String get libraryStatusLoadFailedTitle => 'Could not read library status';

  @override
  String libraryStatusFailed(String message) {
    return 'Could not load library status: $message';
  }

  @override
  String get libraryStatusEndpointUnavailable =>
      'This server does not provide the library status endpoint yet.';

  @override
  String get libraryScanEndpointUnavailable =>
      'This server does not provide the library scan endpoint yet.';

  @override
  String get libraryScanAlreadyInProgress =>
      'The server is already scanning the music library. Refresh the status and try again later.';

  @override
  String get scanResultTitle => 'Latest scan result';

  @override
  String get scanResultTotalTracks => 'Total tracks';

  @override
  String get scanResultReturnedTracks => 'Returned tracks';

  @override
  String get scanResultTime => 'Completed at';

  @override
  String get scrapeTitle => 'Match metadata';

  @override
  String get scrapeTooltip => 'Match metadata';

  @override
  String scrapeProvider(String provider) {
    return 'Provider: $provider';
  }

  @override
  String scrapeConfidence(int percent) {
    return '$percent% confidence';
  }

  @override
  String scrapeCandidatesCount(int count) {
    return '$count candidates';
  }

  @override
  String get scrapeReviewDifferences =>
      'Review the field differences and choose what to apply.';

  @override
  String get scrapeCurrentValue => 'Current';

  @override
  String get scrapeCandidateValue => 'Candidate';

  @override
  String get scrapeNoValue => 'Not set';

  @override
  String get scrapeNoDifferences =>
      'This candidate does not contain applicable fields.';

  @override
  String scrapeFieldsSelected(int count) {
    return '$count fields selected';
  }

  @override
  String get applyCandidate => 'Apply selected fields';

  @override
  String get applyingCandidate => 'Applying...';

  @override
  String scrapeApplySucceeded(String provider, int count) {
    return 'Applied $count fields from $provider.';
  }

  @override
  String scrapeApplyFailed(String message) {
    return 'Could not apply metadata: $message';
  }

  @override
  String get scrapeSelectAtLeastOneField =>
      'Select at least one field to apply.';

  @override
  String get scrapeSearchFailedTitle => 'Could not load metadata candidates';

  @override
  String get scrapeEndpointUnavailable =>
      'This server does not provide the metadata scraping endpoints yet.';

  @override
  String get retry => 'Retry';

  @override
  String get searchAgain => 'Search again';

  @override
  String get noScrapeCandidatesTitle => 'No suitable candidates';

  @override
  String get noScrapeCandidatesMessage =>
      'Improve the file name or embedded tags, then search again.';

  @override
  String get scrapeFieldTitle => 'Title';

  @override
  String get scrapeFieldArtist => 'Artist';

  @override
  String get scrapeFieldAlbum => 'Album';

  @override
  String get scrapeFieldAlbumArtist => 'Album artist';

  @override
  String get scrapeFieldYear => 'Year';

  @override
  String get scrapeFieldTrackNumber => 'Track number';

  @override
  String get scrapeFieldDiscNumber => 'Disc number';

  @override
  String get scrapeFieldGenre => 'Genre';

  @override
  String get scrapeFieldArtwork => 'Artwork';

  @override
  String get scrapeFieldLyrics => 'Lyrics';

  @override
  String get all => 'All';

  @override
  String get allTracks => 'All tracks';

  @override
  String get downloadedTracks => 'Downloaded';

  @override
  String get albums => 'Albums';

  @override
  String get artists => 'Artists';

  @override
  String get playlists => 'Playlists';

  @override
  String get searchTracksArtistsAlbums => 'Search tracks, artists, or albums';

  @override
  String get library => 'Library';

  @override
  String get favorites => 'Favorites';

  @override
  String get sortTracks => 'Sort';

  @override
  String get sortByTitle => 'Song title';

  @override
  String get sortByArtist => 'Artist';

  @override
  String get sortByAlbum => 'Album';

  @override
  String get sortAscending => 'Ascending';

  @override
  String get sortDescending => 'Descending';

  @override
  String selectedTracks(int count) {
    return '$count selected';
  }

  @override
  String selectionSummary(int total, int selected) {
    return '$total tracks · $selected selected';
  }

  @override
  String get exitSelection => 'Exit selection';

  @override
  String get selectAll => 'Select all';

  @override
  String get downloadSelectedTracks => 'Download selected tracks';

  @override
  String get download => 'Download';

  @override
  String get noDownloadedTracks => 'No downloaded tracks';

  @override
  String get noDownloadedTracksMessage => 'Downloaded songs will appear here.';

  @override
  String get deleteDownloadedTrack => 'Delete local download';

  @override
  String get deleteDownloadedTrackTitle => 'Delete local download?';

  @override
  String deleteDownloadedTrackPrompt(String title) {
    return 'Delete the local download for \"$title\"? You can download it again later.';
  }

  @override
  String get deleteDownloadedTrackFailed =>
      'Could not delete the local download.';

  @override
  String get moreOptions => 'More options';

  @override
  String get playNow => 'Play now';

  @override
  String get playNext => 'Play next';

  @override
  String get addToQueue => 'Add to queue';

  @override
  String get queue => 'Queue';

  @override
  String get showQueue => 'Show queue';

  @override
  String get hideQueue => 'Hide queue';

  @override
  String get clearQueue => 'Clear queue';

  @override
  String get removeFromQueue => 'Remove from queue';

  @override
  String get emptyQueueMessage => 'Your queue is waiting for a track.';

  @override
  String get yourLibrary => 'Your library';

  @override
  String get favoritesFirst => 'Favorites appear first';

  @override
  String get addToPlaylist => 'Add to playlist';

  @override
  String get viewAlbum => 'View album';

  @override
  String get viewArtist => 'View artist';

  @override
  String get songInformation => 'Song information';

  @override
  String get addFavorite => 'Add to favorites';

  @override
  String get removeFavorite => 'Remove from favorites';

  @override
  String get newPlaylist => 'New playlist';

  @override
  String get playlistName => 'Playlist name';

  @override
  String get create => 'Create';

  @override
  String get noPlaylists => 'No playlists yet.';

  @override
  String get noPlaylistTracks => 'No playable tracks in this playlist.';

  @override
  String get noAlbums => 'No albums available yet.';

  @override
  String get noArtists => 'No artists available yet.';

  @override
  String get noTracksInAlbum => 'No playable tracks in this album.';

  @override
  String get noTracksByArtist => 'No playable tracks for this artist.';

  @override
  String get noMatchingTracks => 'No matching tracks';

  @override
  String get noFavorites => 'No favorites yet';

  @override
  String get noFavoritesMessage => 'Tracks you favorite will appear here.';

  @override
  String get tryAnotherSearch =>
      'Try another search or turn off the favorites filter.';

  @override
  String get playPlaylist => 'Play playlist';

  @override
  String get playAlbum => 'Play album';

  @override
  String get playArtist => 'Play artist';

  @override
  String get removeFromPlaylist => 'Remove from playlist';

  @override
  String get deletePlaylist => 'Delete playlist';

  @override
  String get deletePlaylistPrompt =>
      'Delete this playlist? Your songs will not be deleted.';

  @override
  String get cancel => 'Cancel';

  @override
  String get delete => 'Delete';

  @override
  String get unknownAlbum => 'Unknown album';

  @override
  String get trackInfoTitle => 'Title';

  @override
  String get trackInfoArtist => 'Artist';

  @override
  String get trackInfoAlbum => 'Album';

  @override
  String get trackInfoGenre => 'Genre';

  @override
  String get trackInfoDuration => 'Duration';

  @override
  String get trackInfoIdentifier => 'Track ID';

  @override
  String get queuedNext => 'Will play next.';

  @override
  String get addedToQueue => 'Added to the queue.';

  @override
  String get alreadyPlaying => 'This track is already playing.';

  @override
  String get alreadyInQueue => 'This track is already in the queue.';

  @override
  String get playlistUpdateFailed =>
      'Could not update the playlist or favorites.';

  @override
  String get trackAddedToPlaylist => 'Added to playlist.';

  @override
  String get trackAlreadyInPlaylist =>
      'This track is already in that playlist.';

  @override
  String batchOperationCompleted(int succeeded, int total) {
    return 'Completed: $succeeded/$total';
  }

  @override
  String batchDownloadQueued(int succeeded, int total) {
    return 'Added to download queue: $succeeded/$total';
  }

  @override
  String batchSkipped(int count) {
    return ', skipped $count';
  }

  @override
  String batchFailed(int count) {
    return ', failed $count';
  }

  @override
  String trackCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'tracks',
      one: 'track',
    );
    return '$count $_temp0';
  }

  @override
  String albumCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'albums',
      one: 'album',
    );
    return '$count $_temp0';
  }

  @override
  String queueSummary(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'tracks',
      one: 'track',
    );
    return '$count $_temp0 · drag to reorder';
  }

  @override
  String get nowPlaying => 'Now playing';

  @override
  String get yourSpace => 'Your space';

  @override
  String get collections => 'Collections';

  @override
  String get previous => 'Previous';

  @override
  String get next => 'Next';

  @override
  String get yourCollection => 'Your collection';

  @override
  String favoriteTracksCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'tracks',
      one: 'track',
    );
    return '$count saved $_temp0';
  }

  @override
  String get favoriteCollectionEmptyMessage =>
      'Favorite a track to build your collection.';

  @override
  String get playCollection => 'Play collection';

  @override
  String get playbackModeSequential => 'Sequential playback';

  @override
  String get playbackModeRepeatAll => 'Repeat queue';

  @override
  String get playbackModeRepeatOne => 'Repeat current track';

  @override
  String get playbackModeShuffle => 'Shuffle playback';

  @override
  String get sleepTimerTitle => 'Sleep timer';

  @override
  String get sleepTimerTooltip => 'Sleep timer';

  @override
  String get sleepTimerActiveTooltip => 'Sleep timer active';

  @override
  String sleepTimerRemaining(String time) {
    return '$time remaining';
  }

  @override
  String get sleepTimerDuration => 'Duration';

  @override
  String get sleepTimerEndTime => 'End time';

  @override
  String get sleepTimerDurationMinutes => 'Duration in minutes';

  @override
  String get sleepTimerMinutes => 'minutes';

  @override
  String get sleepTimerWhenFinished => 'When the timer ends';

  @override
  String get sleepTimerPauseImmediately => 'Pause immediately';

  @override
  String get sleepTimerPauseAfterCurrentTrack => 'Pause after the current song';

  @override
  String get sleepTimerStart => 'Start timer';

  @override
  String get sleepTimerCancel => 'Cancel timer';

  @override
  String get sleepTimerInvalidDuration => 'Enter a duration greater than zero.';

  @override
  String get sleepTimerSelectEndTime => 'Select an end time.';

  @override
  String get sleepTimerWaitingForCurrentTrack =>
      'Waiting for the current song to finish';

  @override
  String get navigationTracks => 'Tracks';

  @override
  String get navigationDiscover => 'Discover';

  @override
  String get navigationReport => 'Listening report';

  @override
  String get discoverTitle => 'Discover';

  @override
  String get discoverSubtitle =>
      'Fresh picks shaped around your music library.';

  @override
  String get discoverSearchHint => 'Search tracks, artists, or albums';

  @override
  String get guessYouLike => 'Made for you';

  @override
  String get viewAll => 'View all';

  @override
  String get discoverFallbackMessage =>
      'Showing picks from your music library while discovery refreshes.';

  @override
  String get dailyRecommendations => 'Daily 30';

  @override
  String get dailyRecommendationsSubtitle =>
      'Thirty songs to soundtrack today.';

  @override
  String get listeningRanking => 'Listening ranking';

  @override
  String get categoryPlaylists => 'Category playlists';

  @override
  String get recentListeningRecommendations => 'Based on recent listening';

  @override
  String get moreRecommendedSongs => 'More songs for you';

  @override
  String get noRecommendations =>
      'Your music library will appear here once songs are available.';

  @override
  String get noListeningRanking => 'Start listening to build your ranking.';

  @override
  String get reportTitle => 'Listening report';

  @override
  String reportSubtitle(int year) {
    return 'Your $year in sound';
  }

  @override
  String get totalListeningTime => 'Total listening time';

  @override
  String listeningDuration(int hours, int minutes) {
    return '$hours h $minutes min';
  }

  @override
  String get listeningTimes => 'Plays';

  @override
  String get listeningDays => 'Listening days';

  @override
  String get songsListened => 'Songs';

  @override
  String get albumsListened => 'Albums';

  @override
  String get listeningHeatmap => 'Listening heatmap';

  @override
  String get reportNoDataTitle => 'Your report is waiting';

  @override
  String get reportNoDataMessage =>
      'Play music to start building your listening story.';

  @override
  String get popularTracks => 'Popular tracks';

  @override
  String listeningPlayCount(int count) {
    return '$count plays';
  }

  @override
  String get offlineDownloadsTooltip => 'Download management';

  @override
  String get loginTitle => 'Log in to LyraNest';

  @override
  String get createAdminTitle => 'Create an administrator account';

  @override
  String get loginDescription =>
      'Connect to your music server and enter your library.';

  @override
  String get createAdminDescription =>
      'Your server is not initialized. Register the first administrator account.';

  @override
  String authStatusCheckFailed(String message) {
    return 'Could not check server initialization status: $message';
  }

  @override
  String get serverAddressLabel => 'Server address';

  @override
  String get internalServerAddressLabel => 'Local network address';

  @override
  String get internalServerAddressHelper =>
      'Example: http://192.168.0.107:8080';

  @override
  String get externalServerAddressLabel => 'Public internet address (optional)';

  @override
  String get externalServerAddressHelper =>
      'Example: https://music.example.com';

  @override
  String get serverAddressAutoSelectionHint =>
      'LyraNest quickly probes both addresses and uses the one reachable on the current network.';

  @override
  String get usernameLabel => 'Username';

  @override
  String get passwordLabel => 'Password';

  @override
  String get showPassword => 'Show password';

  @override
  String get hidePassword => 'Hide password';

  @override
  String get login => 'Log in';

  @override
  String get registerAdministrator => 'Register administrator';

  @override
  String get loginConnectionHint =>
      'Before submitting, LyraNest verifies the server connection and initialization status.';

  @override
  String get appInfoTitle => 'App';

  @override
  String get aboutTitle => 'About LyraNest Community';

  @override
  String get aboutSubtitle => 'Version, acknowledgements, and app information';

  @override
  String get aboutDescription => 'Your personal music space.';

  @override
  String get checkForUpdates => 'Check for updates';

  @override
  String get checkForUpdatesDescription =>
      'Query the latest official LyraNest release on GitHub.';

  @override
  String get alreadyLatestVersion =>
      'You are already using the latest version.';

  @override
  String get updateAvailable => 'Update available';

  @override
  String updateAvailableDescription(String version) {
    return 'LyraNest $version is available.';
  }

  @override
  String get updateCheckFailed =>
      'Could not check for updates. Try again later.';

  @override
  String get openDownloadPage => 'Open download page';

  @override
  String get projectAddress => 'Project address';

  @override
  String get authorHomepage => 'Author homepage';

  @override
  String get contactAuthor => 'Contact author';

  @override
  String get couldNotOpenLink => 'Could not open the link.';

  @override
  String appVersion(String version) {
    return 'Version $version';
  }

  @override
  String get supportAuthorTitle => 'Support the author';

  @override
  String get supportAuthorDescription =>
      'If LyraNest is helpful to you, scan the code below to show your support.';

  @override
  String get supportAuthorHint => 'Thank you for supporting LyraNest.';

  @override
  String get exitApplicationTitle => 'Exit LyraNest?';

  @override
  String get exitApplicationMessage =>
      'Keep playing in the background or exit the app?';

  @override
  String get keepPlayingInBackground => 'Keep playing';

  @override
  String get exitApplication => 'Exit app';
}
