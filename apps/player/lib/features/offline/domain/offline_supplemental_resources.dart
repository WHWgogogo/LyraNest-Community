import 'dart:convert';

class OfflineCachedLyrics {
  const OfflineCachedLyrics({
    this.path,
    this.encoding,
    required this.content,
  });

  final String? path;
  final String? encoding;
  final String content;

  factory OfflineCachedLyrics.fromJson(Map<String, Object?> json) {
    return OfflineCachedLyrics(
      path: json['path'] as String?,
      encoding: json['encoding'] as String?,
      content: json['content'] as String? ?? '',
    );
  }

  Map<String, Object?> toJson() => {
        'content': content,
        'encoding': encoding,
        'path': path,
      };

  String encode() => jsonEncode(toJson());

  static OfflineCachedLyrics? tryDecode(String value) {
    try {
      final decoded = jsonDecode(value);
      if (decoded is! Map<Object?, Object?>) {
        return null;
      }
      return OfflineCachedLyrics.fromJson(decoded.cast<String, Object?>());
    } on FormatException {
      return null;
    }
  }
}

class OfflineSupplementalResources {
  const OfflineSupplementalResources({
    this.lyricsFileName,
    this.artworkFileName,
    this.artworkContentType,
  });

  final String? lyricsFileName;
  final String? artworkFileName;
  final String? artworkContentType;

  bool get hasLyrics => lyricsFileName != null;
  bool get hasArtwork => artworkFileName != null;

  OfflineSupplementalResources copyWith({
    String? lyricsFileName,
    String? artworkFileName,
    String? artworkContentType,
    bool clearLyrics = false,
    bool clearArtwork = false,
  }) {
    return OfflineSupplementalResources(
      lyricsFileName:
          clearLyrics ? null : lyricsFileName ?? this.lyricsFileName,
      artworkFileName:
          clearArtwork ? null : artworkFileName ?? this.artworkFileName,
      artworkContentType:
          clearArtwork ? null : artworkContentType ?? this.artworkContentType,
    );
  }

  factory OfflineSupplementalResources.fromJson(Map<String, Object?> json) {
    return OfflineSupplementalResources(
      lyricsFileName: json['lyricsFileName'] as String?,
      artworkFileName: json['artworkFileName'] as String?,
      artworkContentType: json['artworkContentType'] as String?,
    );
  }

  Map<String, Object?> toJson() => {
        'artworkContentType': artworkContentType,
        'artworkFileName': artworkFileName,
        'lyricsFileName': lyricsFileName,
      };
}
