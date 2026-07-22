import 'dart:convert';
import 'dart:typed_data';

/// Remote and locally-verified metadata associated with one media object.
class OfflineMediaMetadata {
  const OfflineMediaMetadata({
    this.eTag,
    this.digest,
    this.mediaVersion,
    this.sha256,
    this.contentType,
  });

  final String? eTag;
  final String? digest;
  final String? mediaVersion;

  /// The SHA-256 calculated after the completed local file was written.
  final String? sha256;
  final String? contentType;

  /// Uses the server's strongest available representation of a SHA-256.
  ///
  /// LyraNest serves all three values for streams. Supporting each independently
  /// keeps the client compatible with proxies that strip one or two headers.
  String? get expectedSha256 {
    return _normalizedHex(mediaVersion) ??
        _normalizedHex(_unquote(eTag)) ??
        _sha256FromDigest(digest);
  }

  factory OfflineMediaMetadata.fromHeaders(Map<String, String> headers) {
    String? header(String name) {
      for (final entry in headers.entries) {
        if (entry.key.toLowerCase() == name) {
          final value = entry.value.trim();
          return value.isEmpty ? null : value;
        }
      }
      return null;
    }

    return OfflineMediaMetadata(
      eTag: header('etag'),
      digest: header('digest'),
      mediaVersion: header('x-media-version'),
      contentType: header('content-type'),
    );
  }

  factory OfflineMediaMetadata.fromJson(Map<String, Object?> json) {
    return OfflineMediaMetadata(
      eTag: json['eTag'] as String?,
      digest: json['digest'] as String?,
      mediaVersion: json['mediaVersion'] as String?,
      sha256: json['sha256'] as String?,
      contentType: json['contentType'] as String?,
    );
  }

  OfflineMediaMetadata mergeFallback(OfflineMediaMetadata fallback) {
    return OfflineMediaMetadata(
      eTag: eTag ?? fallback.eTag,
      digest: digest ?? fallback.digest,
      mediaVersion: mediaVersion ?? fallback.mediaVersion,
      sha256: sha256 ?? fallback.sha256,
      contentType: contentType ?? fallback.contentType,
    );
  }

  OfflineMediaMetadata copyWith({
    String? eTag,
    String? digest,
    String? mediaVersion,
    String? sha256,
    String? contentType,
  }) {
    return OfflineMediaMetadata(
      eTag: eTag ?? this.eTag,
      digest: digest ?? this.digest,
      mediaVersion: mediaVersion ?? this.mediaVersion,
      sha256: sha256 ?? this.sha256,
      contentType: contentType ?? this.contentType,
    );
  }

  Map<String, Object?> toJson() => {
        'contentType': contentType,
        'digest': digest,
        'eTag': eTag,
        'mediaVersion': mediaVersion,
        'sha256': sha256,
      };
}

String? _normalizedHex(String? value) {
  final normalized = value?.trim().toLowerCase();
  if (normalized == null || !RegExp(r'^[a-f0-9]{64}$').hasMatch(normalized)) {
    return null;
  }
  return normalized;
}

String? _unquote(String? value) {
  if (value == null) {
    return null;
  }
  final trimmed = value.trim();
  if (trimmed.length >= 2 && trimmed.startsWith('"') && trimmed.endsWith('"')) {
    return trimmed.substring(1, trimmed.length - 1);
  }
  return trimmed;
}

String? _sha256FromDigest(String? headerValue) {
  if (headerValue == null) {
    return null;
  }

  final match = RegExp(
    r'(?:^|,)\s*sha-256\s*=\s*"?([^",\s]+)"?',
    caseSensitive: false,
  ).firstMatch(headerValue);
  if (match == null) {
    return null;
  }

  try {
    final bytes = base64.decode(base64.normalize(match.group(1)!));
    if (bytes.length != 32) {
      return null;
    }
    return _hex(Uint8List.fromList(bytes));
  } on FormatException {
    return null;
  }
}

String _hex(Uint8List bytes) {
  final buffer = StringBuffer();
  for (final byte in bytes) {
    buffer.write(byte.toRadixString(16).padLeft(2, '0'));
  }
  return buffer.toString();
}
