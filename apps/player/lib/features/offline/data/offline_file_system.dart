import 'dart:async';
import 'dart:io';

abstract interface class OfflineFileWriter {
  Future<void> write(List<int> bytes);

  Future<void> close();
}

class OfflineFileInfo {
  const OfflineFileInfo({
    required this.path,
    required this.bytes,
    required this.modifiedAt,
  });

  final String path;
  final int bytes;
  final DateTime modifiedAt;
}

abstract interface class OfflineFileSystem {
  Future<void> createDirectory(String path);

  Future<bool> fileExists(String path);

  Future<int> fileLength(String path);

  Stream<List<int>> openRead(String path);

  Future<OfflineFileWriter> openWrite(String path, {required bool append});

  Future<String> readString(String path);

  Future<void> writeString(String path, String contents);

  Future<void> deleteFile(String path);

  Future<void> rename(String sourcePath, String destinationPath);

  Future<List<OfflineFileInfo>> listFiles(String directoryPath);
}

class DartOfflineFileSystem implements OfflineFileSystem {
  const DartOfflineFileSystem();

  @override
  Future<void> createDirectory(String path) async {
    await Directory(path).create(recursive: true);
  }

  @override
  Future<void> deleteFile(String path) async {
    final file = File(path);
    if (await file.exists()) {
      await file.delete();
    }
  }

  @override
  Future<bool> fileExists(String path) => File(path).exists();

  @override
  Future<int> fileLength(String path) => File(path).length();

  @override
  Future<List<OfflineFileInfo>> listFiles(String directoryPath) async {
    final directory = Directory(directoryPath);
    if (!await directory.exists()) {
      return const [];
    }

    final result = <OfflineFileInfo>[];
    await for (final entity
        in directory.list(recursive: true, followLinks: false)) {
      if (entity is! File) {
        continue;
      }
      final stat = await entity.stat();
      result.add(
        OfflineFileInfo(
          path: entity.path,
          bytes: stat.size,
          modifiedAt: stat.modified,
        ),
      );
    }
    return result;
  }

  @override
  Stream<List<int>> openRead(String path) => File(path).openRead();

  @override
  Future<OfflineFileWriter> openWrite(
    String path, {
    required bool append,
  }) async {
    await File(path).parent.create(recursive: true);
    final file = await File(path).open(
      mode: append ? FileMode.append : FileMode.write,
    );
    return _DartOfflineFileWriter(file);
  }

  @override
  Future<String> readString(String path) => File(path).readAsString();

  @override
  Future<void> rename(String sourcePath, String destinationPath) async {
    final destination = File(destinationPath);
    await destination.parent.create(recursive: true);
    if (await destination.exists()) {
      await destination.delete();
    }
    await File(sourcePath).rename(destinationPath);
  }

  @override
  Future<void> writeString(String path, String contents) async {
    await File(path).parent.create(recursive: true);
    await File(path).writeAsString(contents, flush: true);
  }
}

class _DartOfflineFileWriter implements OfflineFileWriter {
  _DartOfflineFileWriter(this._file);

  final RandomAccessFile _file;

  @override
  Future<void> close() => _file.close();

  @override
  Future<void> write(List<int> bytes) => _file.writeFrom(bytes);
}
