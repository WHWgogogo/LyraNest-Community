import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:player/features/discover/data/discovery_api.dart';
import 'package:player/features/discover/domain/discovery_data.dart';
import 'package:player/features/reports/data/listening_report_api.dart';
import 'package:player/features/reports/domain/listening_report.dart';

void main() {
  test('parses discovery sections and nested playlist tracks', () {
    final discovery = DiscoveryData.fromJson({
      'data': {
        'guess_you_like': [
          {'id': 'guess-1', 'title': 'Guess'},
        ],
        'daily_recommendations': [
          {'id': 'daily-1', 'title': 'Daily'},
        ],
        'recent_listening_recommendations': [
          {'id': 'recent-1', 'title': 'Recent'},
        ],
        'more_recommendations': [
          {'id': 'more-1', 'title': 'More'},
        ],
        'category_playlists': [
          {
            'id': 'focus',
            'name': 'Focus',
            'cover_url': '/covers/focus.jpg',
            'tracks': [
              {'id': 'focus-1', 'title': 'Focus track'},
            ],
          },
        ],
      },
    });

    expect(discovery.guessYouLike.single.id, 'guess-1');
    expect(discovery.dailyRecommendations.single.title, 'Daily');
    expect(discovery.recentRecommendations.single.id, 'recent-1');
    expect(discovery.moreRecommendations.single.id, 'more-1');
    expect(discovery.categoryPlaylists.single.coverUrl, '/covers/focus.jpg');
    expect(discovery.categoryPlaylists.single.tracks.single.id, 'focus-1');
  });

  test('keeps all 30 daily recommendations from the API', () {
    final discovery = DiscoveryData.fromJson({
      'daily': List.generate(
        30,
        (index) => {
          'id': 'daily-$index',
          'title': 'Daily $index',
        },
      ),
    });

    expect(discovery.dailyRecommendations, hasLength(30));
  });

  test('parses listening report totals, heatmap, and ranked tracks', () {
    final report = ListeningReport.fromJson(
      {
        'data': {
          'year': '2026',
          'total_duration_seconds': '3720',
          'total_plays': 18,
          'days_listened': '7',
          'unique_tracks': 11,
          'unique_albums': 4,
          'daily_activity': {
            '2026-01-02': 3,
            '2026-01-03': '5',
          },
          'hot_tracks': [
            {
              'track': {
                'id': 'top-1',
                'title': 'Top song',
                'artist': 'Artist',
              },
              'plays': '9',
              'listening_seconds': 900,
            },
          ],
        },
      },
      year: 2025,
    );

    expect(report.year, 2026);
    expect(report.totalListeningSeconds, 3720);
    expect(report.playCount, 18);
    expect(report.activeDays, 7);
    expect(report.songCount, 11);
    expect(report.albumCount, 4);
    expect(report.heatmap, hasLength(2));
    expect(report.topTracks.single.track.id, 'top-1');
    expect(report.topTracks.single.playCount, 9);
    expect(report.topTracks.single.listeningSeconds, 900);
  });

  test('calls discovery and report endpoints with the expected query',
      () async {
    final adapter = _RecordingAdapter((options) {
      if (options.path == '/api/v1/discovery') {
        return {
          'guess_you_like': [
            {'id': 'track-1', 'title': 'Song'},
          ],
        };
      }
      return {
        'year': 2026,
        'top_tracks': [
          {
            'track': {'id': 'track-1', 'title': 'Song'},
            'play_count': 1,
          },
        ],
      };
    });
    final dio = Dio()..httpClientAdapter = adapter;

    final discovery = await DiscoveryApi(dio).fetchDiscovery();
    final report = await ListeningReportApi(dio).fetchReport(year: 2026);

    expect(discovery.guessYouLike.single.id, 'track-1');
    expect(report.topTracks.single.track.id, 'track-1');
    expect(adapter.requests[0].path, '/api/v1/discovery');
    expect(adapter.requests[1].path, '/api/v1/listening/report');
    expect(adapter.requests[1].queryParameters, {'year': 2026});
  });

  test('end-to-end parses server httpapi response fixtures', () async {
    final discoveryResponse = jsonDecode(
      await File(
        'test/fixtures/httpapi_discovery_response.json',
      ).readAsString(),
    );
    final reportResponse = jsonDecode(
      await File(
        'test/fixtures/httpapi_listening_report_response.json',
      ).readAsString(),
    );
    final adapter = _RecordingAdapter((options) {
      return options.path == '/api/v1/discovery'
          ? discoveryResponse
          : reportResponse;
    });
    final dio = Dio()..httpClientAdapter = adapter;

    final discovery = await DiscoveryApi(dio).fetchDiscovery();
    final report = await ListeningReportApi(dio).fetchReport(year: 2026);

    expect(discovery.guessYouLike.single.id, 'track-1');
    expect(discovery.guessYouLike.single.durationSeconds, 3);
    expect(discovery.dailyRecommendations.single.id, 'track-2');
    expect(discovery.recentRecommendations.single.id, 'track-3');
    expect(discovery.moreRecommendations.single.id, 'track-1');
    expect(discovery.categoryPlaylists.single.title, 'Rock');
    expect(discovery.categoryPlaylists.single.tracks, hasLength(2));

    expect(report.totalListeningSeconds, 3);
    expect(report.playCount, 3);
    expect(report.activeDays, 1);
    expect(report.songCount, 2);
    expect(report.albumCount, 2);
    expect(report.heatmap.single.date, DateTime.utc(2026, 7, 20));
    expect(report.topTracks.first.listeningSeconds, 3);
    expect(report.topTracks.last.listeningSeconds, 0);
  });
}

class _RecordingAdapter implements HttpClientAdapter {
  _RecordingAdapter(this._response);

  final Object Function(RequestOptions options) _response;
  final List<RequestOptions> requests = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return ResponseBody.fromString(
      jsonEncode(_response(options)),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
