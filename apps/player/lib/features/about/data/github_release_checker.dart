import 'package:dio/dio.dart';

const currentLyraNestVersion = '1.0.1';
const _lyraNestRepository = 'WHWgogogo/LyraNest-Community';
final lyraNestRepositoryUri = Uri.parse(
  'https://github.com/$_lyraNestRepository',
);
final lyraNestLatestReleaseUri = Uri.parse(
  'https://github.com/$_lyraNestRepository/releases/latest',
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
  final dio = Dio();
  try {
    final response = await dio.get<Map<String, dynamic>>(
      'https://api.github.com/repos/$_lyraNestRepository/releases/latest',
      options: _githubRequestOptions,
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
  } on DioException catch (error) {
    if (error.response?.statusCode != 404) {
      rethrow;
    }
  }

  final tagsResponse = await dio.get<List<dynamic>>(
    'https://api.github.com/repos/$_lyraNestRepository/tags?per_page=1',
    options: _githubRequestOptions,
  );
  final tags = tagsResponse.data;
  final latestTag = tags == null || tags.isEmpty ? null : tags.first;
  final tagName = latestTag is Map<String, dynamic>
      ? latestTag['name'] as String?
      : null;
  if (tagName == null || tagName.trim().isEmpty) {
    throw const FormatException('The latest tag has no name.');
  }
  return LyraNestRelease(
    version: normalizeVersion(tagName),
    releaseUri: Uri.parse('https://github.com/$_lyraNestRepository/tree/$tagName'),
  );
}

final _githubRequestOptions = Options(
  headers: {
    'Accept': 'application/vnd.github+json',
    'X-GitHub-Api-Version': '2022-11-28',
  },
  receiveTimeout: Duration(seconds: 12),
  sendTimeout: Duration(seconds: 12),
);

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