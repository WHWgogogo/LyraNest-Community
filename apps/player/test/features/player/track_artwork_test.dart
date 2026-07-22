import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:player/features/player/presentation/track_artwork.dart';

void main() {
  test('creates a file image provider for cached local artwork', () async {
    final artwork = File('assets/branding/logo.png').absolute;
    expect(await artwork.exists(), isTrue);

    final image = trackArtworkImageProvider(Uri.file(artwork.path).toString());

    expect(image, isA<FileImage>());
    expect(
      (image as FileImage).file.absolute.path.replaceAll('/', r'\'),
      artwork.absolute.path.replaceAll('/', r'\'),
    );
  });
}
