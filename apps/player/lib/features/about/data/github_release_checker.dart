import 'package:dio/dio.dart';

const currentLyraNestVersion = '1.0.0';
final lyraNestRepositoryUri = Uri.parse(
  'https://github.com/WHWgogogo/LyraNest-Community',
);
final lyraNestLatestReleaseUri = Uri.parse(
  'https://github.com/WHWgogogo/LyraNest-Community-Community/releases/latest',
);
final lyraNestAuthorUri = Uri.parse('https://github.com/WHWgogogo');
final lyraNestContactUri = Uri(
  scheme: 'mailto',
  path: 'whw1377236334@163.com',
);

class LyraNestRelease {
  const LyraNestRelease({
    required this.version,
    required this.releaseUri,
  });

  final String version;
  final Uri releaseUri;

  bool get isNewerThanCurrent =>
      compareVersions(version, currentLyraNestVersion) > 0;
}

Future<LyraNestRelease> checkLatestLyraNestRelease() async {
  final response = await Dio().get<Map<String, dynamic>>(
    'https://api.github.com/repos/WHWgogogo/LyraNest-Community-Community/releases/latest',
    options: Options(
      headers: const {
        'Accept': 'application/vnd.github+json',
        'X-GitHub-Api-Version': '2022-11-28',
      },
      receiveTimeout: const Duration(seconds: 12),
      sendTimeout: const Duration(seconds: 12),
    ),
  );
  final data = response.data;
  final tagName = data?['tag_name'] as String?;
  if (tagName == null || tagName.trim().isEmpty) {
    throw const FormatException('The latest release has no tag name.');
  }
  final htmlUrl = data?['html_url'] as String?;
  return LyraNestRelease(
    version: normalizeVersion(tagName),
    releaseUri: htmlUrl == null ? lyraNestLatestReleaseUri : Uri.parse(htmlUrl),
  );
}

String normalizeVersion(String version) {
  final normalized = version.trim();
  return normalized.startsWith('v') || normalized.startsWith('V')
      ? normalized.substring(1)
      : normalized;
}

int compareVersions(String left, String right) {
  final leftParts = _numericVersionParts(left);
  final rightParts = _numericVersionParts(right);
  final length = leftParts.length > rightParts.length
      ? leftParts.length
      : rightParts.length;
  for (var index = 0; index < length; index++) {
    final leftPart = index < leftParts.length ? leftParts[index] : 0;
    final rightPart = index < rightParts.length ? rightParts[index] : 0;
    if (leftPart != rightPart) {
      return leftPart.compareTo(rightPart);
    }
  }
  return 0;
}

List<int> _numericVersionParts(String version) {
  return normalizeVersion(version)
      .split('+')
      .first
      .split(RegExp(r'[.+-]'))
      .takeWhile((part) => RegExp(r'^\d+$').hasMatch(part))
      .map(int.parse)
      .toList(growable: false);
}
