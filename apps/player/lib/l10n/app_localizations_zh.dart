// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class AppLocalizationsZh extends AppLocalizations {
  AppLocalizationsZh([String locale = 'zh']) : super(locale);

  @override
  String get appTitle => '律巢社区版';

  @override
  String get tracksTitle => '曲目';

  @override
  String get lyricsTitle => '歌词';

  @override
  String get playerTitle => '播放器';

  @override
  String get settingsTitle => '服务器设置';

  @override
  String get serverSettingsTooltip => '服务器设置';

  @override
  String get loading => '加载中...';

  @override
  String get requestFailedTitle => '请求失败';

  @override
  String get networkRequestFailed => '网络请求失败';

  @override
  String networkErrorWithStatusCode(String message, int statusCode) {
    return '$message（HTTP 状态码 $statusCode）';
  }

  @override
  String totalTrackCount(int count) {
    return '总曲目数：$count';
  }

  @override
  String get noTracksTitle => '暂无曲目';

  @override
  String get noTracksMessage => '服务器返回的曲目列表为空。';

  @override
  String get lyricsTooltip => '歌词';

  @override
  String get unknownArtist => '未知艺人';

  @override
  String get untitledTrack => '未命名曲目';

  @override
  String get noLyricsTitle => '暂无歌词';

  @override
  String get noLyricsMessage => '服务器返回的歌词内容为空。';

  @override
  String get nothingPlayingTitle => '暂无播放';

  @override
  String get nothingPlayingMessage => '请先从曲目列表选择歌曲。';

  @override
  String get noTrackSelected => '未选择曲目';

  @override
  String get selectMusicFromTracks => '从曲目列表选择音乐';

  @override
  String get play => '播放';

  @override
  String get pause => '暂停';

  @override
  String get viewLyrics => '查看歌词';

  @override
  String get serverUrlLabel => '服务器 URL';

  @override
  String get serverUrlExample => '示例：http://127.0.0.1:8080';

  @override
  String get save => '保存';

  @override
  String get connecting => '正在连接...';

  @override
  String get serverConnectionSucceeded => '连接成功';

  @override
  String serverConnectionFailed(String message) {
    return '无法连接到服务器：$message';
  }

  @override
  String get serverConnectionFailedGeneric => '无法连接到服务器，请检查地址和网络后重试。';

  @override
  String get invalidServerUrl => '请输入有效的 HTTP 或 HTTPS 服务器地址。';

  @override
  String get serverHealthCheckInvalidResponse => '服务器健康检查返回了无效响应。';

  @override
  String serverHealthCheckUnexpectedStatus(String status) {
    return '服务器健康检查状态为“$status”，而不是“ok”。';
  }

  @override
  String serverSettingsLoadFailed(String message) {
    return '无法加载服务器设置：$message';
  }

  @override
  String get desktopLyricsTitle => '桌面歌词';

  @override
  String get desktopLyricsWindowsDescription => 'Windows 原生透明歌词悬浮窗已可用。';

  @override
  String get desktopLyricsAndroidDescription => '授予权限后可使用 Android 系统歌词悬浮窗。';

  @override
  String get desktopLyricsUnsupportedDescription => '当前平台未定义歌词悬浮窗能力。';

  @override
  String get windowsLyricsOverlayNotImplemented => 'Windows 歌词悬浮窗不可用。';

  @override
  String get androidLyricsOverlayNotImplemented => 'Android 歌词悬浮窗不可用。';

  @override
  String get unsupportedLyricsOverlayNotImplemented => '当前平台无法使用歌词悬浮窗。';

  @override
  String get desktopLyricsDescription => '播放时在系统悬浮窗中显示当前歌词。';

  @override
  String get desktopLyricsLoading => '正在加载桌面歌词…';

  @override
  String get desktopLyricsNoLyrics => '当前曲目暂无歌词。';

  @override
  String get desktopLyricsUntimedLyrics => '正在桌面悬浮窗中显示未带时间标签的歌词。';

  @override
  String get desktopLyricsLyricsLoadFailed => '无法加载歌词，但播放将继续。';

  @override
  String get desktopLyricsPermissionRequired => '请授予所需权限以显示桌面歌词。';

  @override
  String get desktopLyricsRequestPermission => '授予权限';

  @override
  String desktopLyricsCapabilityUnavailable(String message) {
    return '无法加载桌面歌词能力：$message';
  }

  @override
  String get desktopLyricsSystemOverlay => '系统悬浮窗';

  @override
  String get desktopLyricsTransparentWindow => '透明窗口';

  @override
  String get desktopLyricsClickThrough => '鼠标穿透';

  @override
  String get desktopLyricsLockPosition => '锁定位置';

  @override
  String get desktopLyricsRuntimePermission => '运行时权限';

  @override
  String get capabilitySupported => '支持';

  @override
  String get capabilityNotSupported => '不支持';

  @override
  String get capabilityRequired => '需要';

  @override
  String get capabilityNotRequired => '不需要';

  @override
  String get managementTitle => '音乐管理';

  @override
  String get managementTooltip => '管理音乐库';

  @override
  String get managementDescription => '查看服务器曲库状态、重新扫描音乐目录，并刷新曲目列表。';

  @override
  String get libraryStatusTitle => '曲库状态';

  @override
  String get libraryDirectoryLabel => '音乐目录';

  @override
  String get libraryDirectoryNotConfigured => '未配置';

  @override
  String get libraryTrackCountLabel => '曲目数量';

  @override
  String get libraryScannerStatusLabel => '扫描状态';

  @override
  String get libraryScanning => '扫描中';

  @override
  String get libraryIdle => '空闲';

  @override
  String get lastScanLabel => '最后扫描';

  @override
  String get neverScanned => '尚未完成扫描';

  @override
  String get lastScanErrorTitle => '最近扫描错误';

  @override
  String get refresh => '刷新';

  @override
  String get rescanLibrary => '重新扫描音乐库';

  @override
  String get scanLibraryDescription => '扫描服务器配置的音乐目录，发现新增、更新或已移除的音频文件。';

  @override
  String get scanNow => '开始扫描';

  @override
  String get scanningLibrary => '正在扫描音乐库...';

  @override
  String scanCompleted(int count) {
    return '音乐库扫描完成，共 $count 首曲目。';
  }

  @override
  String get scanRequestFailedTitle => '扫描请求失败';

  @override
  String scanFailed(String message) {
    return '无法扫描音乐库：$message';
  }

  @override
  String get libraryStatusLoadFailedTitle => '无法读取曲库状态';

  @override
  String libraryStatusFailed(String message) {
    return '无法加载曲库状态：$message';
  }

  @override
  String get libraryStatusEndpointUnavailable => '当前服务器尚未提供曲库状态接口。';

  @override
  String get libraryScanEndpointUnavailable => '当前服务器尚未提供曲库扫描接口。';

  @override
  String get libraryScanAlreadyInProgress => '服务器正在扫描音乐库，请刷新状态后稍后重试。';

  @override
  String get scanResultTitle => '本次扫描结果';

  @override
  String get scanResultTotalTracks => '曲目总数';

  @override
  String get scanResultReturnedTracks => '返回曲目';

  @override
  String get scanResultTime => '完成时间';

  @override
  String get scrapeTitle => '匹配元数据';

  @override
  String get scrapeTooltip => '刮削元数据';

  @override
  String scrapeProvider(String provider) {
    return '来源：$provider';
  }

  @override
  String scrapeConfidence(int percent) {
    return '置信度 $percent%';
  }

  @override
  String scrapeCandidatesCount(int count) {
    return '$count 个候选结果';
  }

  @override
  String get scrapeReviewDifferences => '应用前请检查字段差异，并选择需要更新的字段。';

  @override
  String get scrapeCurrentValue => '当前值';

  @override
  String get scrapeCandidateValue => '候选值';

  @override
  String get scrapeNoValue => '未设置';

  @override
  String get scrapeNoDifferences => '此候选没有可应用的字段。';

  @override
  String scrapeFieldsSelected(int count) {
    return '已选择 $count 个字段';
  }

  @override
  String get applyCandidate => '应用所选字段';

  @override
  String get applyingCandidate => '正在应用...';

  @override
  String scrapeApplySucceeded(String provider, int count) {
    return '已从 $provider 应用 $count 个字段。';
  }

  @override
  String scrapeApplyFailed(String message) {
    return '无法应用元数据：$message';
  }

  @override
  String get scrapeSelectAtLeastOneField => '请至少选择一个要应用的字段。';

  @override
  String get scrapeSearchFailedTitle => '无法获取刮削候选';

  @override
  String get scrapeEndpointUnavailable => '当前服务器尚未提供元数据刮削接口。';

  @override
  String get retry => '重试';

  @override
  String get searchAgain => '重新搜索';

  @override
  String get noScrapeCandidatesTitle => '没有找到合适候选';

  @override
  String get noScrapeCandidatesMessage => '可以完善文件名或内嵌标签后再次搜索。';

  @override
  String get scrapeFieldTitle => '标题';

  @override
  String get scrapeFieldArtist => '艺术家';

  @override
  String get scrapeFieldAlbum => '专辑';

  @override
  String get scrapeFieldAlbumArtist => '专辑艺术家';

  @override
  String get scrapeFieldYear => '年份';

  @override
  String get scrapeFieldTrackNumber => '音轨号';

  @override
  String get scrapeFieldDiscNumber => '碟片号';

  @override
  String get scrapeFieldGenre => '流派';

  @override
  String get scrapeFieldArtwork => '封面';

  @override
  String get scrapeFieldLyrics => '歌词';

  @override
  String get all => '全部';

  @override
  String get allTracks => '全部曲目';

  @override
  String get downloadedTracks => '下载';

  @override
  String get albums => '专辑';

  @override
  String get artists => '艺术家';

  @override
  String get playlists => '歌单';

  @override
  String get searchTracksArtistsAlbums => '搜索曲目、歌手或专辑';

  @override
  String get library => '媒体库';

  @override
  String get favorites => '收藏';

  @override
  String get sortTracks => '排序';

  @override
  String get sortByTitle => '歌曲名';

  @override
  String get sortByArtist => '艺术家';

  @override
  String get sortByAlbum => '专辑';

  @override
  String get sortAscending => '升序';

  @override
  String get sortDescending => '降序';

  @override
  String selectedTracks(int count) {
    return '已选 $count 首';
  }

  @override
  String selectionSummary(int total, int selected) {
    return '$total 首歌曲 · 已选 $selected 首';
  }

  @override
  String get exitSelection => '退出选择';

  @override
  String get selectAll => '全选';

  @override
  String get downloadSelectedTracks => '下载所选歌曲';

  @override
  String get download => '下载';

  @override
  String get noDownloadedTracks => '暂无已下载歌曲';

  @override
  String get noDownloadedTracksMessage => '已下载的歌曲会显示在这里。';

  @override
  String get deleteDownloadedTrack => '删除本地下载';

  @override
  String get deleteDownloadedTrackTitle => '删除本地下载？';

  @override
  String deleteDownloadedTrackPrompt(String title) {
    return '要删除“$title”的本地下载吗？之后可以重新下载。';
  }

  @override
  String get deleteDownloadedTrackFailed => '无法删除本地下载。';

  @override
  String get moreOptions => '更多操作';

  @override
  String get playNow => '现在播放';

  @override
  String get playNext => '下一首播放';

  @override
  String get addToQueue => '加入队列';

  @override
  String get queue => '播放队列';

  @override
  String get showQueue => '显示队列';

  @override
  String get hideQueue => '隐藏队列';

  @override
  String get clearQueue => '清空队列';

  @override
  String get removeFromQueue => '从队列移除';

  @override
  String get emptyQueueMessage => '播放队列还是空的。';

  @override
  String get yourLibrary => '你的媒体库';

  @override
  String get favoritesFirst => '收藏曲目优先显示';

  @override
  String get addToPlaylist => '加入歌单';

  @override
  String get viewAlbum => '查看专辑';

  @override
  String get viewArtist => '查看艺术家';

  @override
  String get songInformation => '歌曲信息';

  @override
  String get addFavorite => '收藏';

  @override
  String get removeFavorite => '取消收藏';

  @override
  String get newPlaylist => '新建歌单';

  @override
  String get playlistName => '歌单名称';

  @override
  String get create => '创建';

  @override
  String get noPlaylists => '还没有自定义歌单。';

  @override
  String get noPlaylistTracks => '这个歌单中还没有可播放的曲目。';

  @override
  String get noAlbums => '还没有带专辑信息的曲目。';

  @override
  String get noArtists => '还没有带艺术家信息的曲目。';

  @override
  String get noTracksInAlbum => '这个专辑中没有可播放的曲目。';

  @override
  String get noTracksByArtist => '这个艺术家没有可播放的曲目。';

  @override
  String get noMatchingTracks => '没有匹配的曲目';

  @override
  String get noFavorites => '暂无收藏';

  @override
  String get noFavoritesMessage => '收藏的曲目会显示在这里。';

  @override
  String get tryAnotherSearch => '试试其他关键词，或关闭收藏筛选。';

  @override
  String get playPlaylist => '播放歌单';

  @override
  String get playAlbum => '播放专辑';

  @override
  String get playArtist => '播放艺术家';

  @override
  String get removeFromPlaylist => '从歌单移除';

  @override
  String get deletePlaylist => '删除歌单';

  @override
  String get deletePlaylistPrompt => '确定要删除这个歌单吗？歌曲不会被删除。';

  @override
  String get cancel => '取消';

  @override
  String get delete => '删除';

  @override
  String get unknownAlbum => '未知专辑';

  @override
  String get trackInfoTitle => '标题';

  @override
  String get trackInfoArtist => '艺术家';

  @override
  String get trackInfoAlbum => '专辑';

  @override
  String get trackInfoGenre => '流派';

  @override
  String get trackInfoDuration => '时长';

  @override
  String get trackInfoIdentifier => '曲目 ID';

  @override
  String get queuedNext => '已设为下一首播放。';

  @override
  String get addedToQueue => '已加入播放队列。';

  @override
  String get alreadyPlaying => '这首歌正在播放。';

  @override
  String get alreadyInQueue => '这首歌已在播放队列中。';

  @override
  String get playlistUpdateFailed => '无法更新歌单或收藏。';

  @override
  String get trackAddedToPlaylist => '已添加到歌单。';

  @override
  String get trackAlreadyInPlaylist => '这首歌已在该歌单中。';

  @override
  String batchOperationCompleted(int succeeded, int total) {
    return '已完成：$succeeded/$total';
  }

  @override
  String batchDownloadQueued(int succeeded, int total) {
    return '已加入下载队列：$succeeded/$total';
  }

  @override
  String batchSkipped(int count) {
    return '，跳过 $count 首';
  }

  @override
  String batchFailed(int count) {
    return '，失败 $count 首';
  }

  @override
  String trackCount(int count) {
    return '$count 首歌曲';
  }

  @override
  String albumCount(int count) {
    return '$count 张专辑';
  }

  @override
  String queueSummary(int count) {
    return '$count 首歌曲 · 拖动可排序';
  }

  @override
  String get nowPlaying => '正在播放';

  @override
  String get yourSpace => '我的空间';

  @override
  String get collections => '收藏与歌单';

  @override
  String get previous => '上一首';

  @override
  String get next => '下一首';

  @override
  String get yourCollection => '我的收藏';

  @override
  String favoriteTracksCount(int count) {
    return '已收藏 $count 首歌曲';
  }

  @override
  String get favoriteCollectionEmptyMessage => '收藏曲目以创建你的收藏集。';

  @override
  String get playCollection => '播放收藏集';

  @override
  String get playbackModeSequential => '顺序播放';

  @override
  String get playbackModeRepeatAll => '列表循环';

  @override
  String get playbackModeRepeatOne => '单曲循环';

  @override
  String get playbackModeShuffle => '随机播放';

  @override
  String get sleepTimerTitle => '睡眠定时';

  @override
  String get sleepTimerTooltip => '睡眠定时器';

  @override
  String get sleepTimerActiveTooltip => '睡眠定时器已启用';

  @override
  String sleepTimerRemaining(String time) {
    return '剩余 $time';
  }

  @override
  String get sleepTimerDuration => '时长';

  @override
  String get sleepTimerEndTime => '结束时间';

  @override
  String get sleepTimerDurationMinutes => '时长（分钟）';

  @override
  String get sleepTimerMinutes => '分钟';

  @override
  String get sleepTimerWhenFinished => '定时结束后';

  @override
  String get sleepTimerPauseImmediately => '立即暂停';

  @override
  String get sleepTimerPauseAfterCurrentTrack => '当前歌曲播放完后暂停';

  @override
  String get sleepTimerStart => '启动定时器';

  @override
  String get sleepTimerCancel => '取消定时器';

  @override
  String get sleepTimerInvalidDuration => '请输入大于 0 的时长。';

  @override
  String get sleepTimerSelectEndTime => '请选择结束时间。';

  @override
  String get sleepTimerWaitingForCurrentTrack => '等待当前歌曲播放完毕';

  @override
  String get navigationTracks => '曲库';

  @override
  String get navigationDiscover => '发现';

  @override
  String get navigationReport => '听歌报告';

  @override
  String get discoverTitle => '发现音乐';

  @override
  String get discoverSubtitle => '从你的曲库与听歌偏好中，找到下一首喜欢的歌。';

  @override
  String get discoverSearchHint => '搜索曲目、艺人或专辑';

  @override
  String get guessYouLike => '猜你喜欢';

  @override
  String get viewAll => '查看全部';

  @override
  String get discoverFallbackMessage => '发现内容刷新中，先为你展示曲库中的歌曲。';

  @override
  String get dailyRecommendations => '每日推荐 30 首';

  @override
  String get dailyRecommendationsSubtitle => '今天的 30 首音乐陪伴。';

  @override
  String get listeningRanking => '听歌排行';

  @override
  String get categoryPlaylists => '分类歌单';

  @override
  String get recentListeningRecommendations => '最近听歌推荐';

  @override
  String get moreRecommendedSongs => '更多推荐歌曲';

  @override
  String get noRecommendations => '曲库有歌曲后，这里会为你准备推荐内容。';

  @override
  String get noListeningRanking => '开始听歌后，这里会生成你的听歌排行。';

  @override
  String get reportTitle => '听歌报告';

  @override
  String reportSubtitle(int year) {
    return '$year 年的声音回顾';
  }

  @override
  String get totalListeningTime => '总听歌时长';

  @override
  String listeningDuration(int hours, int minutes) {
    return '$hours 小时 $minutes 分钟';
  }

  @override
  String get listeningTimes => '听歌次数';

  @override
  String get listeningDays => '听歌天数';

  @override
  String get songsListened => '歌曲数';

  @override
  String get albumsListened => '专辑数';

  @override
  String get listeningHeatmap => '听歌热力图';

  @override
  String get reportNoDataTitle => '报告正在等待你';

  @override
  String get reportNoDataMessage => '开始播放音乐，逐步写下你的听歌故事。';

  @override
  String get popularTracks => '热门歌曲榜';

  @override
  String listeningPlayCount(int count) {
    return '$count 次播放';
  }

  @override
  String get offlineDownloadsTooltip => '下载管理';

  @override
  String get loginTitle => '登录律巢';

  @override
  String get createAdminTitle => '创建管理员账户';

  @override
  String get loginDescription => '连接你的音乐服务器，进入媒体库。';

  @override
  String get createAdminDescription => '服务器尚未初始化，请注册第一个管理员账户。';

  @override
  String authStatusCheckFailed(String message) {
    return '无法检查服务器初始化状态：$message';
  }

  @override
  String get serverAddressLabel => '服务器地址';

  @override
  String get internalServerAddressLabel => '内网访问地址';

  @override
  String get internalServerAddressHelper => '例如：http://192.168.0.107:8080';

  @override
  String get externalServerAddressLabel => '外网访问地址（可选）';

  @override
  String get externalServerAddressHelper => '例如：https://music.example.com';

  @override
  String get serverAddressAutoSelectionHint => '律巢会快速检测两个地址，并自动使用当前网络可访问的地址。';

  @override
  String get usernameLabel => '用户名';

  @override
  String get passwordLabel => '密码';

  @override
  String get showPassword => '显示密码';

  @override
  String get hidePassword => '隐藏密码';

  @override
  String get login => '登录';

  @override
  String get registerAdministrator => '注册管理员';

  @override
  String get loginConnectionHint => '提交前，律巢会验证服务器连接和初始化状态。';

  @override
  String get appInfoTitle => '应用';

  @override
  String get aboutTitle => '关于律巢社区版';

  @override
  String get aboutSubtitle => '版本、致谢和应用信息';

  @override
  String get aboutDescription => '你的个人音乐空间。';

  @override
  String get checkForUpdates => '检查更新';

  @override
  String get checkForUpdatesDescription => '从 GitHub 查询律巢最新正式版本。';

  @override
  String get alreadyLatestVersion => '当前已经是最新版本。';

  @override
  String get updateAvailable => '发现新版本';

  @override
  String updateAvailableDescription(String version) {
    return '律巢 $version 已发布。';
  }

  @override
  String get updateCheckFailed => '检查更新失败，请稍后重试。';

  @override
  String get openDownloadPage => '前往下载';

  @override
  String get projectAddress => '项目地址';

  @override
  String get authorHomepage => '作者主页';

  @override
  String get contactAuthor => '联系作者';

  @override
  String get couldNotOpenLink => '无法打开链接。';

  @override
  String appVersion(String version) {
    return '版本 $version';
  }

  @override
  String get supportAuthorTitle => '支持作者';

  @override
  String get supportAuthorDescription => '如果律巢对你有所帮助，欢迎扫描下方赞赏码支持作者。';

  @override
  String get supportAuthorHint => '感谢你对律巢的支持。';

  @override
  String get exitApplicationTitle => '要退出律巢吗？';

  @override
  String get exitApplicationMessage => '你可以保留后台播放，或完全退出应用。';

  @override
  String get keepPlayingInBackground => '保留后台播放';

  @override
  String get exitApplication => '退出应用';
}
