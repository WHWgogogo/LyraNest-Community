import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_zh.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
      : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
    delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('zh')
  ];

  /// Application title.
  ///
  /// In en, this message translates to:
  /// **'LyraNest Community'**
  String get appTitle;

  /// No description provided for @tracksTitle.
  ///
  /// In en, this message translates to:
  /// **'Tracks'**
  String get tracksTitle;

  /// No description provided for @lyricsTitle.
  ///
  /// In en, this message translates to:
  /// **'Lyrics'**
  String get lyricsTitle;

  /// No description provided for @playerTitle.
  ///
  /// In en, this message translates to:
  /// **'Player'**
  String get playerTitle;

  /// No description provided for @settingsTitle.
  ///
  /// In en, this message translates to:
  /// **'Server settings'**
  String get settingsTitle;

  /// No description provided for @serverSettingsTooltip.
  ///
  /// In en, this message translates to:
  /// **'Server settings'**
  String get serverSettingsTooltip;

  /// No description provided for @loading.
  ///
  /// In en, this message translates to:
  /// **'Loading...'**
  String get loading;

  /// No description provided for @requestFailedTitle.
  ///
  /// In en, this message translates to:
  /// **'Request failed'**
  String get requestFailedTitle;

  /// No description provided for @networkRequestFailed.
  ///
  /// In en, this message translates to:
  /// **'Network request failed'**
  String get networkRequestFailed;

  /// Network error with an HTTP status code.
  ///
  /// In en, this message translates to:
  /// **'{message} (HTTP {statusCode})'**
  String networkErrorWithStatusCode(String message, int statusCode);

  /// Label for the total number of tracks.
  ///
  /// In en, this message translates to:
  /// **'Total tracks: {count}'**
  String totalTrackCount(int count);

  /// No description provided for @noTracksTitle.
  ///
  /// In en, this message translates to:
  /// **'No tracks'**
  String get noTracksTitle;

  /// No description provided for @noTracksMessage.
  ///
  /// In en, this message translates to:
  /// **'The server returned an empty track list.'**
  String get noTracksMessage;

  /// No description provided for @lyricsTooltip.
  ///
  /// In en, this message translates to:
  /// **'Lyrics'**
  String get lyricsTooltip;

  /// No description provided for @unknownArtist.
  ///
  /// In en, this message translates to:
  /// **'Unknown artist'**
  String get unknownArtist;

  /// No description provided for @untitledTrack.
  ///
  /// In en, this message translates to:
  /// **'Untitled track'**
  String get untitledTrack;

  /// No description provided for @noLyricsTitle.
  ///
  /// In en, this message translates to:
  /// **'No lyrics'**
  String get noLyricsTitle;

  /// No description provided for @noLyricsMessage.
  ///
  /// In en, this message translates to:
  /// **'The server returned empty lyrics content.'**
  String get noLyricsMessage;

  /// No description provided for @nothingPlayingTitle.
  ///
  /// In en, this message translates to:
  /// **'Nothing playing'**
  String get nothingPlayingTitle;

  /// No description provided for @nothingPlayingMessage.
  ///
  /// In en, this message translates to:
  /// **'Select a song from the track list first.'**
  String get nothingPlayingMessage;

  /// No description provided for @noTrackSelected.
  ///
  /// In en, this message translates to:
  /// **'No track selected'**
  String get noTrackSelected;

  /// No description provided for @selectMusicFromTracks.
  ///
  /// In en, this message translates to:
  /// **'Select music from the track list'**
  String get selectMusicFromTracks;

  /// No description provided for @play.
  ///
  /// In en, this message translates to:
  /// **'Play'**
  String get play;

  /// No description provided for @pause.
  ///
  /// In en, this message translates to:
  /// **'Pause'**
  String get pause;

  /// No description provided for @viewLyrics.
  ///
  /// In en, this message translates to:
  /// **'View lyrics'**
  String get viewLyrics;

  /// No description provided for @serverUrlLabel.
  ///
  /// In en, this message translates to:
  /// **'Server URL'**
  String get serverUrlLabel;

  /// No description provided for @serverUrlExample.
  ///
  /// In en, this message translates to:
  /// **'Example: http://127.0.0.1:8080'**
  String get serverUrlExample;

  /// No description provided for @save.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get save;

  /// No description provided for @connecting.
  ///
  /// In en, this message translates to:
  /// **'Connecting...'**
  String get connecting;

  /// No description provided for @serverConnectionSucceeded.
  ///
  /// In en, this message translates to:
  /// **'Connection successful'**
  String get serverConnectionSucceeded;

  /// Server connection error with localized details.
  ///
  /// In en, this message translates to:
  /// **'Could not connect to server: {message}'**
  String serverConnectionFailed(String message);

  /// No description provided for @serverConnectionFailedGeneric.
  ///
  /// In en, this message translates to:
  /// **'Could not connect to the server. Check the address and network, then try again.'**
  String get serverConnectionFailedGeneric;

  /// No description provided for @invalidServerUrl.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid HTTP or HTTPS server address.'**
  String get invalidServerUrl;

  /// No description provided for @serverHealthCheckInvalidResponse.
  ///
  /// In en, this message translates to:
  /// **'The health check returned an invalid response.'**
  String get serverHealthCheckInvalidResponse;

  /// Health check error when the server status is not ok.
  ///
  /// In en, this message translates to:
  /// **'The health check returned status \"{status}\" instead of \"ok\".'**
  String serverHealthCheckUnexpectedStatus(String status);

  /// Server settings loading error.
  ///
  /// In en, this message translates to:
  /// **'Could not load server settings: {message}'**
  String serverSettingsLoadFailed(String message);

  /// No description provided for @desktopLyricsTitle.
  ///
  /// In en, this message translates to:
  /// **'Desktop lyrics'**
  String get desktopLyricsTitle;

  /// No description provided for @desktopLyricsWindowsDescription.
  ///
  /// In en, this message translates to:
  /// **'Native Windows transparent lyrics overlay is available.'**
  String get desktopLyricsWindowsDescription;

  /// No description provided for @desktopLyricsAndroidDescription.
  ///
  /// In en, this message translates to:
  /// **'Android system lyrics overlay is available after permission is granted.'**
  String get desktopLyricsAndroidDescription;

  /// No description provided for @desktopLyricsUnsupportedDescription.
  ///
  /// In en, this message translates to:
  /// **'Lyrics overlay capabilities are not defined for this platform.'**
  String get desktopLyricsUnsupportedDescription;

  /// No description provided for @windowsLyricsOverlayNotImplemented.
  ///
  /// In en, this message translates to:
  /// **'Windows lyrics overlay is unavailable.'**
  String get windowsLyricsOverlayNotImplemented;

  /// No description provided for @androidLyricsOverlayNotImplemented.
  ///
  /// In en, this message translates to:
  /// **'Android lyrics overlay is unavailable.'**
  String get androidLyricsOverlayNotImplemented;

  /// No description provided for @unsupportedLyricsOverlayNotImplemented.
  ///
  /// In en, this message translates to:
  /// **'Lyrics overlay is unavailable on this platform.'**
  String get unsupportedLyricsOverlayNotImplemented;

  /// No description provided for @desktopLyricsDescription.
  ///
  /// In en, this message translates to:
  /// **'Show the current lyric line in a system overlay while music plays.'**
  String get desktopLyricsDescription;

  /// No description provided for @desktopLyricsLoading.
  ///
  /// In en, this message translates to:
  /// **'Loading lyrics for desktop display...'**
  String get desktopLyricsLoading;

  /// No description provided for @desktopLyricsNoLyrics.
  ///
  /// In en, this message translates to:
  /// **'No lyrics are available for this track.'**
  String get desktopLyricsNoLyrics;

  /// No description provided for @desktopLyricsUntimedLyrics.
  ///
  /// In en, this message translates to:
  /// **'Showing untimed lyrics in the desktop overlay.'**
  String get desktopLyricsUntimedLyrics;

  /// No description provided for @desktopLyricsLyricsLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not load lyrics; playback continues.'**
  String get desktopLyricsLyricsLoadFailed;

  /// No description provided for @desktopLyricsPermissionRequired.
  ///
  /// In en, this message translates to:
  /// **'Grant the required permission to show desktop lyrics.'**
  String get desktopLyricsPermissionRequired;

  /// No description provided for @desktopLyricsRequestPermission.
  ///
  /// In en, this message translates to:
  /// **'Grant permission'**
  String get desktopLyricsRequestPermission;

  /// Desktop lyrics capability loading error.
  ///
  /// In en, this message translates to:
  /// **'Could not load desktop lyrics capabilities: {message}'**
  String desktopLyricsCapabilityUnavailable(String message);

  /// No description provided for @desktopLyricsSystemOverlay.
  ///
  /// In en, this message translates to:
  /// **'System overlay'**
  String get desktopLyricsSystemOverlay;

  /// No description provided for @desktopLyricsTransparentWindow.
  ///
  /// In en, this message translates to:
  /// **'Transparent window'**
  String get desktopLyricsTransparentWindow;

  /// No description provided for @desktopLyricsClickThrough.
  ///
  /// In en, this message translates to:
  /// **'Click-through'**
  String get desktopLyricsClickThrough;

  /// No description provided for @desktopLyricsLockPosition.
  ///
  /// In en, this message translates to:
  /// **'Lock position'**
  String get desktopLyricsLockPosition;

  /// No description provided for @desktopLyricsRuntimePermission.
  ///
  /// In en, this message translates to:
  /// **'Runtime permission'**
  String get desktopLyricsRuntimePermission;

  /// No description provided for @capabilitySupported.
  ///
  /// In en, this message translates to:
  /// **'Supported'**
  String get capabilitySupported;

  /// No description provided for @capabilityNotSupported.
  ///
  /// In en, this message translates to:
  /// **'Not supported'**
  String get capabilityNotSupported;

  /// No description provided for @capabilityRequired.
  ///
  /// In en, this message translates to:
  /// **'Required'**
  String get capabilityRequired;

  /// No description provided for @capabilityNotRequired.
  ///
  /// In en, this message translates to:
  /// **'Not required'**
  String get capabilityNotRequired;

  /// No description provided for @managementTitle.
  ///
  /// In en, this message translates to:
  /// **'Music management'**
  String get managementTitle;

  /// No description provided for @managementTooltip.
  ///
  /// In en, this message translates to:
  /// **'Manage music library'**
  String get managementTooltip;

  /// No description provided for @managementDescription.
  ///
  /// In en, this message translates to:
  /// **'Review the server library status, rescan its music directory, and refresh the track list.'**
  String get managementDescription;

  /// No description provided for @libraryStatusTitle.
  ///
  /// In en, this message translates to:
  /// **'Library status'**
  String get libraryStatusTitle;

  /// No description provided for @libraryDirectoryLabel.
  ///
  /// In en, this message translates to:
  /// **'Music directory'**
  String get libraryDirectoryLabel;

  /// No description provided for @libraryDirectoryNotConfigured.
  ///
  /// In en, this message translates to:
  /// **'Not configured'**
  String get libraryDirectoryNotConfigured;

  /// No description provided for @libraryTrackCountLabel.
  ///
  /// In en, this message translates to:
  /// **'Track count'**
  String get libraryTrackCountLabel;

  /// No description provided for @libraryScannerStatusLabel.
  ///
  /// In en, this message translates to:
  /// **'Scanner status'**
  String get libraryScannerStatusLabel;

  /// No description provided for @libraryScanning.
  ///
  /// In en, this message translates to:
  /// **'Scanning'**
  String get libraryScanning;

  /// No description provided for @libraryIdle.
  ///
  /// In en, this message translates to:
  /// **'Idle'**
  String get libraryIdle;

  /// No description provided for @lastScanLabel.
  ///
  /// In en, this message translates to:
  /// **'Last scan'**
  String get lastScanLabel;

  /// No description provided for @neverScanned.
  ///
  /// In en, this message translates to:
  /// **'No completed scan yet'**
  String get neverScanned;

  /// No description provided for @lastScanErrorTitle.
  ///
  /// In en, this message translates to:
  /// **'Last scan error'**
  String get lastScanErrorTitle;

  /// No description provided for @refresh.
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get refresh;

  /// No description provided for @rescanLibrary.
  ///
  /// In en, this message translates to:
  /// **'Rescan music library'**
  String get rescanLibrary;

  /// No description provided for @scanLibraryDescription.
  ///
  /// In en, this message translates to:
  /// **'Scan the configured server directory for added, updated, or removed audio files.'**
  String get scanLibraryDescription;

  /// No description provided for @scanNow.
  ///
  /// In en, this message translates to:
  /// **'Start scan'**
  String get scanNow;

  /// No description provided for @scanningLibrary.
  ///
  /// In en, this message translates to:
  /// **'Scanning library...'**
  String get scanningLibrary;

  /// Successful library scan message.
  ///
  /// In en, this message translates to:
  /// **'Library scan completed with {count} tracks.'**
  String scanCompleted(int count);

  /// No description provided for @scanRequestFailedTitle.
  ///
  /// In en, this message translates to:
  /// **'Scan request failed'**
  String get scanRequestFailedTitle;

  /// Library scan error with details.
  ///
  /// In en, this message translates to:
  /// **'Could not scan the library: {message}'**
  String scanFailed(String message);

  /// No description provided for @libraryStatusLoadFailedTitle.
  ///
  /// In en, this message translates to:
  /// **'Could not read library status'**
  String get libraryStatusLoadFailedTitle;

  /// Library status error with details.
  ///
  /// In en, this message translates to:
  /// **'Could not load library status: {message}'**
  String libraryStatusFailed(String message);

  /// No description provided for @libraryStatusEndpointUnavailable.
  ///
  /// In en, this message translates to:
  /// **'This server does not provide the library status endpoint yet.'**
  String get libraryStatusEndpointUnavailable;

  /// No description provided for @libraryScanEndpointUnavailable.
  ///
  /// In en, this message translates to:
  /// **'This server does not provide the library scan endpoint yet.'**
  String get libraryScanEndpointUnavailable;

  /// No description provided for @libraryScanAlreadyInProgress.
  ///
  /// In en, this message translates to:
  /// **'The server is already scanning the music library. Refresh the status and try again later.'**
  String get libraryScanAlreadyInProgress;

  /// No description provided for @scanResultTitle.
  ///
  /// In en, this message translates to:
  /// **'Latest scan result'**
  String get scanResultTitle;

  /// No description provided for @scanResultTotalTracks.
  ///
  /// In en, this message translates to:
  /// **'Total tracks'**
  String get scanResultTotalTracks;

  /// No description provided for @scanResultReturnedTracks.
  ///
  /// In en, this message translates to:
  /// **'Returned tracks'**
  String get scanResultReturnedTracks;

  /// No description provided for @scanResultTime.
  ///
  /// In en, this message translates to:
  /// **'Completed at'**
  String get scanResultTime;

  /// No description provided for @scrapeTitle.
  ///
  /// In en, this message translates to:
  /// **'Match metadata'**
  String get scrapeTitle;

  /// No description provided for @scrapeTooltip.
  ///
  /// In en, this message translates to:
  /// **'Match metadata'**
  String get scrapeTooltip;

  /// Metadata provider label.
  ///
  /// In en, this message translates to:
  /// **'Provider: {provider}'**
  String scrapeProvider(String provider);

  /// Metadata candidate confidence.
  ///
  /// In en, this message translates to:
  /// **'{percent}% confidence'**
  String scrapeConfidence(int percent);

  /// Number of metadata candidates.
  ///
  /// In en, this message translates to:
  /// **'{count} candidates'**
  String scrapeCandidatesCount(int count);

  /// No description provided for @scrapeReviewDifferences.
  ///
  /// In en, this message translates to:
  /// **'Review the field differences and choose what to apply.'**
  String get scrapeReviewDifferences;

  /// No description provided for @scrapeCurrentValue.
  ///
  /// In en, this message translates to:
  /// **'Current'**
  String get scrapeCurrentValue;

  /// No description provided for @scrapeCandidateValue.
  ///
  /// In en, this message translates to:
  /// **'Candidate'**
  String get scrapeCandidateValue;

  /// No description provided for @scrapeNoValue.
  ///
  /// In en, this message translates to:
  /// **'Not set'**
  String get scrapeNoValue;

  /// No description provided for @scrapeNoDifferences.
  ///
  /// In en, this message translates to:
  /// **'This candidate does not contain applicable fields.'**
  String get scrapeNoDifferences;

  /// Number of selected metadata fields.
  ///
  /// In en, this message translates to:
  /// **'{count} fields selected'**
  String scrapeFieldsSelected(int count);

  /// No description provided for @applyCandidate.
  ///
  /// In en, this message translates to:
  /// **'Apply selected fields'**
  String get applyCandidate;

  /// No description provided for @applyingCandidate.
  ///
  /// In en, this message translates to:
  /// **'Applying...'**
  String get applyingCandidate;

  /// Successful metadata application message.
  ///
  /// In en, this message translates to:
  /// **'Applied {count} fields from {provider}.'**
  String scrapeApplySucceeded(String provider, int count);

  /// Metadata apply error with details.
  ///
  /// In en, this message translates to:
  /// **'Could not apply metadata: {message}'**
  String scrapeApplyFailed(String message);

  /// No description provided for @scrapeSelectAtLeastOneField.
  ///
  /// In en, this message translates to:
  /// **'Select at least one field to apply.'**
  String get scrapeSelectAtLeastOneField;

  /// No description provided for @scrapeSearchFailedTitle.
  ///
  /// In en, this message translates to:
  /// **'Could not load metadata candidates'**
  String get scrapeSearchFailedTitle;

  /// No description provided for @scrapeEndpointUnavailable.
  ///
  /// In en, this message translates to:
  /// **'This server does not provide the metadata scraping endpoints yet.'**
  String get scrapeEndpointUnavailable;

  /// No description provided for @retry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get retry;

  /// No description provided for @searchAgain.
  ///
  /// In en, this message translates to:
  /// **'Search again'**
  String get searchAgain;

  /// No description provided for @noScrapeCandidatesTitle.
  ///
  /// In en, this message translates to:
  /// **'No suitable candidates'**
  String get noScrapeCandidatesTitle;

  /// No description provided for @noScrapeCandidatesMessage.
  ///
  /// In en, this message translates to:
  /// **'Improve the file name or embedded tags, then search again.'**
  String get noScrapeCandidatesMessage;

  /// No description provided for @scrapeFieldTitle.
  ///
  /// In en, this message translates to:
  /// **'Title'**
  String get scrapeFieldTitle;

  /// No description provided for @scrapeFieldArtist.
  ///
  /// In en, this message translates to:
  /// **'Artist'**
  String get scrapeFieldArtist;

  /// No description provided for @scrapeFieldAlbum.
  ///
  /// In en, this message translates to:
  /// **'Album'**
  String get scrapeFieldAlbum;

  /// No description provided for @scrapeFieldAlbumArtist.
  ///
  /// In en, this message translates to:
  /// **'Album artist'**
  String get scrapeFieldAlbumArtist;

  /// No description provided for @scrapeFieldYear.
  ///
  /// In en, this message translates to:
  /// **'Year'**
  String get scrapeFieldYear;

  /// No description provided for @scrapeFieldTrackNumber.
  ///
  /// In en, this message translates to:
  /// **'Track number'**
  String get scrapeFieldTrackNumber;

  /// No description provided for @scrapeFieldDiscNumber.
  ///
  /// In en, this message translates to:
  /// **'Disc number'**
  String get scrapeFieldDiscNumber;

  /// No description provided for @scrapeFieldGenre.
  ///
  /// In en, this message translates to:
  /// **'Genre'**
  String get scrapeFieldGenre;

  /// No description provided for @scrapeFieldArtwork.
  ///
  /// In en, this message translates to:
  /// **'Artwork'**
  String get scrapeFieldArtwork;

  /// No description provided for @scrapeFieldLyrics.
  ///
  /// In en, this message translates to:
  /// **'Lyrics'**
  String get scrapeFieldLyrics;

  /// No description provided for @all.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get all;

  /// No description provided for @allTracks.
  ///
  /// In en, this message translates to:
  /// **'All tracks'**
  String get allTracks;

  /// No description provided for @downloadedTracks.
  ///
  /// In en, this message translates to:
  /// **'Downloaded'**
  String get downloadedTracks;

  /// No description provided for @albums.
  ///
  /// In en, this message translates to:
  /// **'Albums'**
  String get albums;

  /// No description provided for @artists.
  ///
  /// In en, this message translates to:
  /// **'Artists'**
  String get artists;

  /// No description provided for @playlists.
  ///
  /// In en, this message translates to:
  /// **'Playlists'**
  String get playlists;

  /// No description provided for @searchTracksArtistsAlbums.
  ///
  /// In en, this message translates to:
  /// **'Search tracks, artists, or albums'**
  String get searchTracksArtistsAlbums;

  /// No description provided for @library.
  ///
  /// In en, this message translates to:
  /// **'Library'**
  String get library;

  /// No description provided for @favorites.
  ///
  /// In en, this message translates to:
  /// **'Favorites'**
  String get favorites;

  /// No description provided for @sortTracks.
  ///
  /// In en, this message translates to:
  /// **'Sort'**
  String get sortTracks;

  /// No description provided for @sortByTitle.
  ///
  /// In en, this message translates to:
  /// **'Song title'**
  String get sortByTitle;

  /// No description provided for @sortByArtist.
  ///
  /// In en, this message translates to:
  /// **'Artist'**
  String get sortByArtist;

  /// No description provided for @sortByAlbum.
  ///
  /// In en, this message translates to:
  /// **'Album'**
  String get sortByAlbum;

  /// No description provided for @sortAscending.
  ///
  /// In en, this message translates to:
  /// **'Ascending'**
  String get sortAscending;

  /// No description provided for @sortDescending.
  ///
  /// In en, this message translates to:
  /// **'Descending'**
  String get sortDescending;

  /// No description provided for @selectedTracks.
  ///
  /// In en, this message translates to:
  /// **'{count} selected'**
  String selectedTracks(int count);

  /// No description provided for @selectionSummary.
  ///
  /// In en, this message translates to:
  /// **'{total} tracks · {selected} selected'**
  String selectionSummary(int total, int selected);

  /// No description provided for @exitSelection.
  ///
  /// In en, this message translates to:
  /// **'Exit selection'**
  String get exitSelection;

  /// No description provided for @selectAll.
  ///
  /// In en, this message translates to:
  /// **'Select all'**
  String get selectAll;

  /// No description provided for @downloadSelectedTracks.
  ///
  /// In en, this message translates to:
  /// **'Download selected tracks'**
  String get downloadSelectedTracks;

  /// No description provided for @download.
  ///
  /// In en, this message translates to:
  /// **'Download'**
  String get download;

  /// No description provided for @noDownloadedTracks.
  ///
  /// In en, this message translates to:
  /// **'No downloaded tracks'**
  String get noDownloadedTracks;

  /// No description provided for @noDownloadedTracksMessage.
  ///
  /// In en, this message translates to:
  /// **'Downloaded songs will appear here.'**
  String get noDownloadedTracksMessage;

  /// No description provided for @deleteDownloadedTrack.
  ///
  /// In en, this message translates to:
  /// **'Delete local download'**
  String get deleteDownloadedTrack;

  /// No description provided for @deleteDownloadedTrackTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete local download?'**
  String get deleteDownloadedTrackTitle;

  /// No description provided for @deleteDownloadedTrackPrompt.
  ///
  /// In en, this message translates to:
  /// **'Delete the local download for \"{title}\"? You can download it again later.'**
  String deleteDownloadedTrackPrompt(String title);

  /// No description provided for @deleteDownloadedTrackFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not delete the local download.'**
  String get deleteDownloadedTrackFailed;

  /// No description provided for @moreOptions.
  ///
  /// In en, this message translates to:
  /// **'More options'**
  String get moreOptions;

  /// No description provided for @playNow.
  ///
  /// In en, this message translates to:
  /// **'Play now'**
  String get playNow;

  /// No description provided for @playNext.
  ///
  /// In en, this message translates to:
  /// **'Play next'**
  String get playNext;

  /// No description provided for @addToQueue.
  ///
  /// In en, this message translates to:
  /// **'Add to queue'**
  String get addToQueue;

  /// No description provided for @queue.
  ///
  /// In en, this message translates to:
  /// **'Queue'**
  String get queue;

  /// No description provided for @showQueue.
  ///
  /// In en, this message translates to:
  /// **'Show queue'**
  String get showQueue;

  /// No description provided for @hideQueue.
  ///
  /// In en, this message translates to:
  /// **'Hide queue'**
  String get hideQueue;

  /// No description provided for @clearQueue.
  ///
  /// In en, this message translates to:
  /// **'Clear queue'**
  String get clearQueue;

  /// No description provided for @removeFromQueue.
  ///
  /// In en, this message translates to:
  /// **'Remove from queue'**
  String get removeFromQueue;

  /// No description provided for @emptyQueueMessage.
  ///
  /// In en, this message translates to:
  /// **'Your queue is waiting for a track.'**
  String get emptyQueueMessage;

  /// No description provided for @yourLibrary.
  ///
  /// In en, this message translates to:
  /// **'Your library'**
  String get yourLibrary;

  /// No description provided for @favoritesFirst.
  ///
  /// In en, this message translates to:
  /// **'Favorites appear first'**
  String get favoritesFirst;

  /// No description provided for @addToPlaylist.
  ///
  /// In en, this message translates to:
  /// **'Add to playlist'**
  String get addToPlaylist;

  /// No description provided for @viewAlbum.
  ///
  /// In en, this message translates to:
  /// **'View album'**
  String get viewAlbum;

  /// No description provided for @viewArtist.
  ///
  /// In en, this message translates to:
  /// **'View artist'**
  String get viewArtist;

  /// No description provided for @songInformation.
  ///
  /// In en, this message translates to:
  /// **'Song information'**
  String get songInformation;

  /// No description provided for @addFavorite.
  ///
  /// In en, this message translates to:
  /// **'Add to favorites'**
  String get addFavorite;

  /// No description provided for @removeFavorite.
  ///
  /// In en, this message translates to:
  /// **'Remove from favorites'**
  String get removeFavorite;

  /// No description provided for @newPlaylist.
  ///
  /// In en, this message translates to:
  /// **'New playlist'**
  String get newPlaylist;

  /// No description provided for @playlistName.
  ///
  /// In en, this message translates to:
  /// **'Playlist name'**
  String get playlistName;

  /// No description provided for @create.
  ///
  /// In en, this message translates to:
  /// **'Create'**
  String get create;

  /// No description provided for @noPlaylists.
  ///
  /// In en, this message translates to:
  /// **'No playlists yet.'**
  String get noPlaylists;

  /// No description provided for @noPlaylistTracks.
  ///
  /// In en, this message translates to:
  /// **'No playable tracks in this playlist.'**
  String get noPlaylistTracks;

  /// No description provided for @noAlbums.
  ///
  /// In en, this message translates to:
  /// **'No albums available yet.'**
  String get noAlbums;

  /// No description provided for @noArtists.
  ///
  /// In en, this message translates to:
  /// **'No artists available yet.'**
  String get noArtists;

  /// No description provided for @noTracksInAlbum.
  ///
  /// In en, this message translates to:
  /// **'No playable tracks in this album.'**
  String get noTracksInAlbum;

  /// No description provided for @noTracksByArtist.
  ///
  /// In en, this message translates to:
  /// **'No playable tracks for this artist.'**
  String get noTracksByArtist;

  /// No description provided for @noMatchingTracks.
  ///
  /// In en, this message translates to:
  /// **'No matching tracks'**
  String get noMatchingTracks;

  /// No description provided for @noFavorites.
  ///
  /// In en, this message translates to:
  /// **'No favorites yet'**
  String get noFavorites;

  /// No description provided for @noFavoritesMessage.
  ///
  /// In en, this message translates to:
  /// **'Tracks you favorite will appear here.'**
  String get noFavoritesMessage;

  /// No description provided for @tryAnotherSearch.
  ///
  /// In en, this message translates to:
  /// **'Try another search or turn off the favorites filter.'**
  String get tryAnotherSearch;

  /// No description provided for @playPlaylist.
  ///
  /// In en, this message translates to:
  /// **'Play playlist'**
  String get playPlaylist;

  /// No description provided for @playAlbum.
  ///
  /// In en, this message translates to:
  /// **'Play album'**
  String get playAlbum;

  /// No description provided for @playArtist.
  ///
  /// In en, this message translates to:
  /// **'Play artist'**
  String get playArtist;

  /// No description provided for @removeFromPlaylist.
  ///
  /// In en, this message translates to:
  /// **'Remove from playlist'**
  String get removeFromPlaylist;

  /// No description provided for @deletePlaylist.
  ///
  /// In en, this message translates to:
  /// **'Delete playlist'**
  String get deletePlaylist;

  /// No description provided for @deletePlaylistPrompt.
  ///
  /// In en, this message translates to:
  /// **'Delete this playlist? Your songs will not be deleted.'**
  String get deletePlaylistPrompt;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @delete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get delete;

  /// No description provided for @unknownAlbum.
  ///
  /// In en, this message translates to:
  /// **'Unknown album'**
  String get unknownAlbum;

  /// No description provided for @trackInfoTitle.
  ///
  /// In en, this message translates to:
  /// **'Title'**
  String get trackInfoTitle;

  /// No description provided for @trackInfoArtist.
  ///
  /// In en, this message translates to:
  /// **'Artist'**
  String get trackInfoArtist;

  /// No description provided for @trackInfoAlbum.
  ///
  /// In en, this message translates to:
  /// **'Album'**
  String get trackInfoAlbum;

  /// No description provided for @trackInfoGenre.
  ///
  /// In en, this message translates to:
  /// **'Genre'**
  String get trackInfoGenre;

  /// No description provided for @trackInfoDuration.
  ///
  /// In en, this message translates to:
  /// **'Duration'**
  String get trackInfoDuration;

  /// No description provided for @trackInfoIdentifier.
  ///
  /// In en, this message translates to:
  /// **'Track ID'**
  String get trackInfoIdentifier;

  /// No description provided for @queuedNext.
  ///
  /// In en, this message translates to:
  /// **'Will play next.'**
  String get queuedNext;

  /// No description provided for @addedToQueue.
  ///
  /// In en, this message translates to:
  /// **'Added to the queue.'**
  String get addedToQueue;

  /// No description provided for @alreadyPlaying.
  ///
  /// In en, this message translates to:
  /// **'This track is already playing.'**
  String get alreadyPlaying;

  /// No description provided for @alreadyInQueue.
  ///
  /// In en, this message translates to:
  /// **'This track is already in the queue.'**
  String get alreadyInQueue;

  /// No description provided for @playlistUpdateFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not update the playlist or favorites.'**
  String get playlistUpdateFailed;

  /// No description provided for @trackAddedToPlaylist.
  ///
  /// In en, this message translates to:
  /// **'Added to playlist.'**
  String get trackAddedToPlaylist;

  /// No description provided for @trackAlreadyInPlaylist.
  ///
  /// In en, this message translates to:
  /// **'This track is already in that playlist.'**
  String get trackAlreadyInPlaylist;

  /// No description provided for @batchOperationCompleted.
  ///
  /// In en, this message translates to:
  /// **'Completed: {succeeded}/{total}'**
  String batchOperationCompleted(int succeeded, int total);

  /// No description provided for @batchDownloadQueued.
  ///
  /// In en, this message translates to:
  /// **'Added to download queue: {succeeded}/{total}'**
  String batchDownloadQueued(int succeeded, int total);

  /// No description provided for @batchSkipped.
  ///
  /// In en, this message translates to:
  /// **', skipped {count}'**
  String batchSkipped(int count);

  /// No description provided for @batchFailed.
  ///
  /// In en, this message translates to:
  /// **', failed {count}'**
  String batchFailed(int count);

  /// Number of tracks.
  ///
  /// In en, this message translates to:
  /// **'{count} {count, plural, =1{track} other{tracks}}'**
  String trackCount(int count);

  /// Number of albums.
  ///
  /// In en, this message translates to:
  /// **'{count} {count, plural, =1{album} other{albums}}'**
  String albumCount(int count);

  /// Queue item count and reorder hint.
  ///
  /// In en, this message translates to:
  /// **'{count} {count, plural, =1{track} other{tracks}} · drag to reorder'**
  String queueSummary(int count);

  /// No description provided for @nowPlaying.
  ///
  /// In en, this message translates to:
  /// **'Now playing'**
  String get nowPlaying;

  /// No description provided for @yourSpace.
  ///
  /// In en, this message translates to:
  /// **'Your space'**
  String get yourSpace;

  /// No description provided for @collections.
  ///
  /// In en, this message translates to:
  /// **'Collections'**
  String get collections;

  /// No description provided for @previous.
  ///
  /// In en, this message translates to:
  /// **'Previous'**
  String get previous;

  /// No description provided for @next.
  ///
  /// In en, this message translates to:
  /// **'Next'**
  String get next;

  /// No description provided for @yourCollection.
  ///
  /// In en, this message translates to:
  /// **'Your collection'**
  String get yourCollection;

  /// Number of favorite tracks.
  ///
  /// In en, this message translates to:
  /// **'{count} saved {count, plural, =1{track} other{tracks}}'**
  String favoriteTracksCount(int count);

  /// No description provided for @favoriteCollectionEmptyMessage.
  ///
  /// In en, this message translates to:
  /// **'Favorite a track to build your collection.'**
  String get favoriteCollectionEmptyMessage;

  /// No description provided for @playCollection.
  ///
  /// In en, this message translates to:
  /// **'Play collection'**
  String get playCollection;

  /// No description provided for @playbackModeSequential.
  ///
  /// In en, this message translates to:
  /// **'Sequential playback'**
  String get playbackModeSequential;

  /// No description provided for @playbackModeRepeatAll.
  ///
  /// In en, this message translates to:
  /// **'Repeat queue'**
  String get playbackModeRepeatAll;

  /// No description provided for @playbackModeRepeatOne.
  ///
  /// In en, this message translates to:
  /// **'Repeat current track'**
  String get playbackModeRepeatOne;

  /// No description provided for @playbackModeShuffle.
  ///
  /// In en, this message translates to:
  /// **'Shuffle playback'**
  String get playbackModeShuffle;

  /// No description provided for @sleepTimerTitle.
  ///
  /// In en, this message translates to:
  /// **'Sleep timer'**
  String get sleepTimerTitle;

  /// No description provided for @sleepTimerTooltip.
  ///
  /// In en, this message translates to:
  /// **'Sleep timer'**
  String get sleepTimerTooltip;

  /// No description provided for @sleepTimerActiveTooltip.
  ///
  /// In en, this message translates to:
  /// **'Sleep timer active'**
  String get sleepTimerActiveTooltip;

  /// Remaining time before the sleep timer takes effect.
  ///
  /// In en, this message translates to:
  /// **'{time} remaining'**
  String sleepTimerRemaining(String time);

  /// No description provided for @sleepTimerDuration.
  ///
  /// In en, this message translates to:
  /// **'Duration'**
  String get sleepTimerDuration;

  /// No description provided for @sleepTimerEndTime.
  ///
  /// In en, this message translates to:
  /// **'End time'**
  String get sleepTimerEndTime;

  /// No description provided for @sleepTimerDurationMinutes.
  ///
  /// In en, this message translates to:
  /// **'Duration in minutes'**
  String get sleepTimerDurationMinutes;

  /// No description provided for @sleepTimerMinutes.
  ///
  /// In en, this message translates to:
  /// **'minutes'**
  String get sleepTimerMinutes;

  /// No description provided for @sleepTimerWhenFinished.
  ///
  /// In en, this message translates to:
  /// **'When the timer ends'**
  String get sleepTimerWhenFinished;

  /// No description provided for @sleepTimerPauseImmediately.
  ///
  /// In en, this message translates to:
  /// **'Pause immediately'**
  String get sleepTimerPauseImmediately;

  /// No description provided for @sleepTimerPauseAfterCurrentTrack.
  ///
  /// In en, this message translates to:
  /// **'Pause after the current song'**
  String get sleepTimerPauseAfterCurrentTrack;

  /// No description provided for @sleepTimerStart.
  ///
  /// In en, this message translates to:
  /// **'Start timer'**
  String get sleepTimerStart;

  /// No description provided for @sleepTimerCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel timer'**
  String get sleepTimerCancel;

  /// No description provided for @sleepTimerInvalidDuration.
  ///
  /// In en, this message translates to:
  /// **'Enter a duration greater than zero.'**
  String get sleepTimerInvalidDuration;

  /// No description provided for @sleepTimerSelectEndTime.
  ///
  /// In en, this message translates to:
  /// **'Select an end time.'**
  String get sleepTimerSelectEndTime;

  /// No description provided for @sleepTimerWaitingForCurrentTrack.
  ///
  /// In en, this message translates to:
  /// **'Waiting for the current song to finish'**
  String get sleepTimerWaitingForCurrentTrack;

  /// No description provided for @navigationTracks.
  ///
  /// In en, this message translates to:
  /// **'Tracks'**
  String get navigationTracks;

  /// No description provided for @navigationDiscover.
  ///
  /// In en, this message translates to:
  /// **'Discover'**
  String get navigationDiscover;

  /// No description provided for @navigationReport.
  ///
  /// In en, this message translates to:
  /// **'Listening report'**
  String get navigationReport;

  /// No description provided for @discoverTitle.
  ///
  /// In en, this message translates to:
  /// **'Discover'**
  String get discoverTitle;

  /// No description provided for @discoverSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Fresh picks shaped around your music library.'**
  String get discoverSubtitle;

  /// No description provided for @discoverSearchHint.
  ///
  /// In en, this message translates to:
  /// **'Search tracks, artists, or albums'**
  String get discoverSearchHint;

  /// No description provided for @guessYouLike.
  ///
  /// In en, this message translates to:
  /// **'Made for you'**
  String get guessYouLike;

  /// No description provided for @viewAll.
  ///
  /// In en, this message translates to:
  /// **'View all'**
  String get viewAll;

  /// No description provided for @discoverFallbackMessage.
  ///
  /// In en, this message translates to:
  /// **'Showing picks from your music library while discovery refreshes.'**
  String get discoverFallbackMessage;

  /// No description provided for @dailyRecommendations.
  ///
  /// In en, this message translates to:
  /// **'Daily 30'**
  String get dailyRecommendations;

  /// No description provided for @dailyRecommendationsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Thirty songs to soundtrack today.'**
  String get dailyRecommendationsSubtitle;

  /// No description provided for @listeningRanking.
  ///
  /// In en, this message translates to:
  /// **'Listening ranking'**
  String get listeningRanking;

  /// No description provided for @categoryPlaylists.
  ///
  /// In en, this message translates to:
  /// **'Category playlists'**
  String get categoryPlaylists;

  /// No description provided for @recentListeningRecommendations.
  ///
  /// In en, this message translates to:
  /// **'Based on recent listening'**
  String get recentListeningRecommendations;

  /// No description provided for @moreRecommendedSongs.
  ///
  /// In en, this message translates to:
  /// **'More songs for you'**
  String get moreRecommendedSongs;

  /// No description provided for @noRecommendations.
  ///
  /// In en, this message translates to:
  /// **'Your music library will appear here once songs are available.'**
  String get noRecommendations;

  /// No description provided for @noListeningRanking.
  ///
  /// In en, this message translates to:
  /// **'Start listening to build your ranking.'**
  String get noListeningRanking;

  /// No description provided for @reportTitle.
  ///
  /// In en, this message translates to:
  /// **'Listening report'**
  String get reportTitle;

  /// No description provided for @reportSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Your {year} in sound'**
  String reportSubtitle(int year);

  /// No description provided for @totalListeningTime.
  ///
  /// In en, this message translates to:
  /// **'Total listening time'**
  String get totalListeningTime;

  /// No description provided for @listeningDuration.
  ///
  /// In en, this message translates to:
  /// **'{hours} h {minutes} min'**
  String listeningDuration(int hours, int minutes);

  /// No description provided for @listeningTimes.
  ///
  /// In en, this message translates to:
  /// **'Plays'**
  String get listeningTimes;

  /// No description provided for @listeningDays.
  ///
  /// In en, this message translates to:
  /// **'Listening days'**
  String get listeningDays;

  /// No description provided for @songsListened.
  ///
  /// In en, this message translates to:
  /// **'Songs'**
  String get songsListened;

  /// No description provided for @albumsListened.
  ///
  /// In en, this message translates to:
  /// **'Albums'**
  String get albumsListened;

  /// No description provided for @listeningHeatmap.
  ///
  /// In en, this message translates to:
  /// **'Listening heatmap'**
  String get listeningHeatmap;

  /// No description provided for @reportNoDataTitle.
  ///
  /// In en, this message translates to:
  /// **'Your report is waiting'**
  String get reportNoDataTitle;

  /// No description provided for @reportNoDataMessage.
  ///
  /// In en, this message translates to:
  /// **'Play music to start building your listening story.'**
  String get reportNoDataMessage;

  /// No description provided for @popularTracks.
  ///
  /// In en, this message translates to:
  /// **'Popular tracks'**
  String get popularTracks;

  /// No description provided for @listeningPlayCount.
  ///
  /// In en, this message translates to:
  /// **'{count} plays'**
  String listeningPlayCount(int count);

  /// No description provided for @offlineDownloadsTooltip.
  ///
  /// In en, this message translates to:
  /// **'Download management'**
  String get offlineDownloadsTooltip;

  /// No description provided for @loginTitle.
  ///
  /// In en, this message translates to:
  /// **'Log in to LyraNest'**
  String get loginTitle;

  /// No description provided for @createAdminTitle.
  ///
  /// In en, this message translates to:
  /// **'Create an administrator account'**
  String get createAdminTitle;

  /// No description provided for @loginDescription.
  ///
  /// In en, this message translates to:
  /// **'Connect to your music server and enter your library.'**
  String get loginDescription;

  /// No description provided for @createAdminDescription.
  ///
  /// In en, this message translates to:
  /// **'Your server is not initialized. Register the first administrator account.'**
  String get createAdminDescription;

  /// No description provided for @authStatusCheckFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not check server initialization status: {message}'**
  String authStatusCheckFailed(String message);

  /// No description provided for @serverAddressLabel.
  ///
  /// In en, this message translates to:
  /// **'Server address'**
  String get serverAddressLabel;

  /// No description provided for @internalServerAddressLabel.
  ///
  /// In en, this message translates to:
  /// **'Local network address'**
  String get internalServerAddressLabel;

  /// No description provided for @internalServerAddressHelper.
  ///
  /// In en, this message translates to:
  /// **'Example: http://192.168.0.107:8080'**
  String get internalServerAddressHelper;

  /// No description provided for @externalServerAddressLabel.
  ///
  /// In en, this message translates to:
  /// **'Public internet address (optional)'**
  String get externalServerAddressLabel;

  /// No description provided for @externalServerAddressHelper.
  ///
  /// In en, this message translates to:
  /// **'Example: https://music.example.com'**
  String get externalServerAddressHelper;

  /// No description provided for @serverAddressAutoSelectionHint.
  ///
  /// In en, this message translates to:
  /// **'LyraNest quickly probes both addresses and uses the one reachable on the current network.'**
  String get serverAddressAutoSelectionHint;

  /// No description provided for @usernameLabel.
  ///
  /// In en, this message translates to:
  /// **'Username'**
  String get usernameLabel;

  /// No description provided for @passwordLabel.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get passwordLabel;

  /// No description provided for @showPassword.
  ///
  /// In en, this message translates to:
  /// **'Show password'**
  String get showPassword;

  /// No description provided for @hidePassword.
  ///
  /// In en, this message translates to:
  /// **'Hide password'**
  String get hidePassword;

  /// No description provided for @login.
  ///
  /// In en, this message translates to:
  /// **'Log in'**
  String get login;

  /// No description provided for @registerAdministrator.
  ///
  /// In en, this message translates to:
  /// **'Register administrator'**
  String get registerAdministrator;

  /// No description provided for @loginConnectionHint.
  ///
  /// In en, this message translates to:
  /// **'Before submitting, LyraNest verifies the server connection and initialization status.'**
  String get loginConnectionHint;

  /// No description provided for @appInfoTitle.
  ///
  /// In en, this message translates to:
  /// **'App'**
  String get appInfoTitle;

  /// No description provided for @aboutTitle.
  ///
  /// In en, this message translates to:
  /// **'About LyraNest Community'**
  String get aboutTitle;

  /// No description provided for @aboutSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Version, acknowledgements, and app information'**
  String get aboutSubtitle;

  /// No description provided for @aboutDescription.
  ///
  /// In en, this message translates to:
  /// **'Your personal music space.'**
  String get aboutDescription;

  /// No description provided for @checkForUpdates.
  ///
  /// In en, this message translates to:
  /// **'Check for updates'**
  String get checkForUpdates;

  /// No description provided for @checkForUpdatesDescription.
  ///
  /// In en, this message translates to:
  /// **'Query the latest official LyraNest release on GitHub.'**
  String get checkForUpdatesDescription;

  /// No description provided for @alreadyLatestVersion.
  ///
  /// In en, this message translates to:
  /// **'You are already using the latest version.'**
  String get alreadyLatestVersion;

  /// No description provided for @updateAvailable.
  ///
  /// In en, this message translates to:
  /// **'Update available'**
  String get updateAvailable;

  /// No description provided for @updateAvailableDescription.
  ///
  /// In en, this message translates to:
  /// **'LyraNest {version} is available.'**
  String updateAvailableDescription(String version);

  /// No description provided for @updateCheckFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not check for updates. Try again later.'**
  String get updateCheckFailed;

  /// No description provided for @openDownloadPage.
  ///
  /// In en, this message translates to:
  /// **'Open download page'**
  String get openDownloadPage;

  /// No description provided for @projectAddress.
  ///
  /// In en, this message translates to:
  /// **'Project address'**
  String get projectAddress;

  /// No description provided for @authorHomepage.
  ///
  /// In en, this message translates to:
  /// **'Author homepage'**
  String get authorHomepage;

  /// No description provided for @contactAuthor.
  ///
  /// In en, this message translates to:
  /// **'Contact author'**
  String get contactAuthor;

  /// No description provided for @couldNotOpenLink.
  ///
  /// In en, this message translates to:
  /// **'Could not open the link.'**
  String get couldNotOpenLink;

  /// No description provided for @appVersion.
  ///
  /// In en, this message translates to:
  /// **'Version {version}'**
  String appVersion(String version);

  /// No description provided for @supportAuthorTitle.
  ///
  /// In en, this message translates to:
  /// **'Support the author'**
  String get supportAuthorTitle;

  /// No description provided for @supportAuthorDescription.
  ///
  /// In en, this message translates to:
  /// **'If LyraNest is helpful to you, scan the code below to show your support.'**
  String get supportAuthorDescription;

  /// No description provided for @supportAuthorHint.
  ///
  /// In en, this message translates to:
  /// **'Thank you for supporting LyraNest.'**
  String get supportAuthorHint;

  /// No description provided for @exitApplicationTitle.
  ///
  /// In en, this message translates to:
  /// **'Exit LyraNest?'**
  String get exitApplicationTitle;

  /// No description provided for @exitApplicationMessage.
  ///
  /// In en, this message translates to:
  /// **'Keep playing in the background or exit the app?'**
  String get exitApplicationMessage;

  /// No description provided for @keepPlayingInBackground.
  ///
  /// In en, this message translates to:
  /// **'Keep playing'**
  String get keepPlayingInBackground;

  /// No description provided for @exitApplication.
  ///
  /// In en, this message translates to:
  /// **'Exit app'**
  String get exitApplication;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'zh'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'zh':
      return AppLocalizationsZh();
  }

  throw FlutterError(
      'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
      'an issue with the localizations generation tool. Please file an issue '
      'on GitHub with a reproducible sample app and the gen-l10n configuration '
      'that was used.');
}
