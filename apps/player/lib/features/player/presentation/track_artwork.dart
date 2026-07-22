import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../offline/application/offline_providers.dart';

class TrackArtwork extends ConsumerWidget {
  const TrackArtwork({
    required this.artworkUrl,
    required this.identity,
    required this.title,
    this.borderRadius = 28,
    this.elevated = false,
    this.showPlaybackPulse = false,
    this.isPlaying = false,
    super.key,
  });

  final String artworkUrl;
  final String identity;
  final String title;
  final double borderRadius;
  final bool elevated;
  final bool showPlaybackPulse;
  final bool isPlaying;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accent = _accentFor(identity);
    final localArtwork = ref.watch(offlineCachedArtworkUriProvider(identity));
    final image = localArtwork.when(
      data: (uri) => _imageFor(uri?.toString() ?? artworkUrl),
      loading: () => _ArtworkFallback(
        accent: accent,
        initial: _initialFor(title),
      ),
      error: (error, stackTrace) => _imageFor(artworkUrl),
    );

    return TweenAnimationBuilder<double>(
      duration: const Duration(milliseconds: 380),
      curve: Curves.easeOutCubic,
      tween: Tween(begin: .965, end: showPlaybackPulse && isPlaying ? 1 : .98),
      builder: (context, scale, child) {
        return Transform.scale(scale: scale, child: child);
      },
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(borderRadius),
          boxShadow: elevated
              ? [
                  BoxShadow(
                    color: accent.withValues(alpha: .34),
                    blurRadius: 48,
                    spreadRadius: -4,
                    offset: const Offset(0, 22),
                  ),
                  const BoxShadow(
                    color: Color(0x72000000),
                    blurRadius: 28,
                    spreadRadius: -12,
                    offset: Offset(0, 18),
                  ),
                ]
              : null,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(borderRadius),
          child: image,
        ),
      ),
    );
  }

  Widget _imageFor(String url) {
    final imageProvider = trackArtworkImageProvider(url);
    if (imageProvider is FileImage) {
      return Image(
        image: imageProvider,
        fit: BoxFit.cover,
        filterQuality: FilterQuality.high,
        errorBuilder: (context, error, stackTrace) {
          return _ArtworkFallback(
            accent: _accentFor(identity),
            initial: _initialFor(title),
          );
        },
      );
    }
    return Image.network(
      url,
      fit: BoxFit.cover,
      filterQuality: FilterQuality.high,
      loadingBuilder: (context, child, loadingProgress) {
        if (loadingProgress == null) {
          return child;
        }
        return Stack(
          fit: StackFit.expand,
          children: [
            _ArtworkFallback(
              accent: _accentFor(identity),
              initial: _initialFor(title),
            ),
            const Center(
              child: SizedBox.square(
                dimension: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          ],
        );
      },
      errorBuilder: (context, error, stackTrace) {
        return _ArtworkFallback(
          accent: _accentFor(identity),
          initial: _initialFor(title),
        );
      },
    );
  }
}

ImageProvider<Object> trackArtworkImageProvider(String url) {
  final uri = Uri.tryParse(url);
  if (uri?.scheme == 'file') {
    return FileImage(File(uri!.toFilePath()));
  }
  return NetworkImage(url);
}

class _ArtworkFallback extends StatelessWidget {
  const _ArtworkFallback({
    required this.accent,
    required this.initial,
  });

  final Color accent;
  final String initial;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                accent,
                const Color(0xFF312458),
                const Color(0xFF10131F),
              ],
            ),
          ),
        ),
        Positioned(
          top: -40,
          right: -28,
          child: Container(
            width: 176,
            height: 176,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withValues(alpha: .16),
            ),
          ),
        ),
        Positioned(
          left: -46,
          bottom: -62,
          child: Container(
            width: 190,
            height: 190,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: Colors.white.withValues(alpha: .2),
                width: 22,
              ),
            ),
          ),
        ),
        const Center(
          child: Icon(
            Icons.album_rounded,
            size: 74,
            color: Color(0xAAFFFFFF),
          ),
        ),
        Positioned(
          left: 22,
          bottom: 18,
          child: Text(
            initial,
            style: Theme.of(context).textTheme.displaySmall?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                ),
          ),
        ),
      ],
    );
  }
}

String buildArtworkUrl(String serverBaseUrl, String trackId) {
  return Uri.parse(serverBaseUrl)
      .resolve('/api/v1/tracks/${Uri.encodeComponent(trackId)}/artwork')
      .toString();
}

Color _accentFor(String identity) {
  final hue = identity.runes.fold<int>(0, (total, rune) => total + rune) % 360;
  return HSVColor.fromAHSV(1, hue.toDouble(), .72, .96).toColor();
}

String _initialFor(String title) {
  final trimmed = title.trim();
  return trimmed.isEmpty ? '♪' : trimmed.substring(0, 1).toUpperCase();
}
