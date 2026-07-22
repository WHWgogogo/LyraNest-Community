import 'package:flutter_test/flutter_test.dart';
import 'package:player/features/about/data/github_release_checker.dart';

void main() {
  test('uses the LyraNest Community release endpoint', () {
    expect(
      lyraNestLatestReleaseUri.toString(),
      'https://github.com/WHWgogogo/LyraNest-Community/releases/latest',
    );
  });

  test('normalizes and compares GitHub release versions', () {
    expect(normalizeVersion('v0.1.8'), '0.1.8');
    expect(compareVersions('0.1.9', '0.1.8'), greaterThan(0));
    expect(compareVersions('0.1.8', '0.1.8'), 0);
    expect(compareVersions('0.1.7', '0.1.8'), lessThan(0));
    expect(compareVersions('0.1.8+4', '0.1.8'), 0);
  });
}