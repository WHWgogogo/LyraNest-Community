import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:player/core/network/api_error.dart';
import 'package:player/features/desktop_lyrics/domain/overlay_capability.dart';
import 'package:player/features/tracks/domain/track.dart';
import 'package:player/features/tracks/presentation/library_ui.dart';
import 'package:player/l10n/l10n.dart';

void main() {
  group('AppLocalizations', () {
    test('loads English and Simplified Chinese resources', () async {
      final english = await AppLocalizations.delegate.load(const Locale('en'));
      final chinese = await AppLocalizations.delegate.load(const Locale('zh'));

      expect(english.appTitle, 'LyraNest');
      expect(chinese.appTitle, '律巢');
      expect(english.totalTrackCount(12), 'Total tracks: 12');
      expect(chinese.totalTrackCount(12), '总曲目数：12');
      expect(chinese.managementTitle, '音乐管理');
      expect(chinese.scrapeConfidence(92), '置信度 92%');
      expect(chinese.nowPlaying, '正在播放');
      expect(chinese.favorites, '收藏');
      expect(chinese.library, '媒体库');
      expect(chinese.queue, '播放队列');
      expect(chinese.playbackModeShuffle, '随机播放');
    });

    testWidgets('falls back to English for unsupported locales',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('fr'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) => Text(context.l10n.appTitle),
          ),
        ),
      );

      expect(find.text('LyraNest'), findsOneWidget);
    });

    testWidgets('uses Chinese player and library labels in widgets',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) => Column(
              children: [
                Text(context.l10n.nowPlaying),
                Text(MediaLibraryStrings.of(context).queueSummary(2)),
              ],
            ),
          ),
        ),
      );

      expect(find.text('正在播放'), findsOneWidget);
      expect(find.text('2 首歌曲 · 拖动可排序'), findsOneWidget);
    });

    test('localizes parameterized and helper messages', () async {
      final chinese = await AppLocalizations.delegate.load(const Locale('zh'));
      const networkError = ApiError(
        ApiError.networkRequestFailedMessage,
        statusCode: 503,
      );
      const track = Track(id: 'track-1', title: Track.untitledTitle);
      const capability = LyricsOverlayCapability(
        platform: LyricsOverlayPlatform.windows,
        supportsSystemOverlay: true,
        supportsTransparentWindow: true,
        supportsClickThrough: true,
        supportsLockPosition: true,
        requiresRuntimePermission: false,
        notes: '',
      );

      expect(
        networkError.localizedMessage(chinese),
        '网络请求失败（HTTP 状态码 503）',
      );
      expect(track.localizedTitle(chinese), '未命名曲目');
      expect(
        capability.localizedNotes(chinese),
        'Windows 原生透明歌词悬浮窗已可用。',
      );
    });
  });
}
