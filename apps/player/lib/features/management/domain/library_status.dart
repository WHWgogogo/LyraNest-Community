import 'package:flutter/foundation.dart';

@immutable
class LibraryStatus {
  const LibraryStatus({
    required this.directory,
    required this.trackCount,
    required this.scanning,
    required this.lastScannedAt,
    required this.lastError,
  });

  final String directory;
  final int trackCount;
  final bool scanning;
  final DateTime? lastScannedAt;
  final String? lastError;

  factory LibraryStatus.fromJson(Object? json) {
    final map = _jsonMap(json);
    final error = map['last_error'] ?? map['lastError'];
    final errorText = error is String ? error.trim() : '';

    return LibraryStatus(
      directory: _stringFromJson(map['directory']),
      trackCount: _intFromJson(
            map['track_count'] ?? map['trackCount'],
          ) ??
          0,
      scanning: _boolFromJson(map['scanning']),
      lastScannedAt: _dateTimeFromJson(
        map['last_scanned_at'] ?? map['lastScannedAt'],
      ),
      lastError: errorText.isEmpty ? null : errorText,
    );
  }
}

Map<String, dynamic> _jsonMap(Object? value) {
  if (value is! Map<dynamic, dynamic>) {
    return const {};
  }
  return value.map((key, value) => MapEntry(key.toString(), value));
}

String _stringFromJson(Object? value) {
  return value is String ? value : '';
}

int? _intFromJson(Object? value) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  if (value is String) {
    return int.tryParse(value);
  }
  return null;
}

bool _boolFromJson(Object? value) {
  if (value is bool) {
    return value;
  }
  if (value is String) {
    return value.toLowerCase() == 'true';
  }
  return false;
}

DateTime? _dateTimeFromJson(Object? value) {
  if (value is! String || value.trim().isEmpty) {
    return null;
  }
  return DateTime.tryParse(value);
}
