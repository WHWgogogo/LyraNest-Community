enum LyricsOverlayPlatform {
  windows,
  android,
  unsupported,
}

class LyricsOverlayCapability {
  const LyricsOverlayCapability({
    required this.platform,
    required this.supportsSystemOverlay,
    required this.supportsTransparentWindow,
    required this.supportsClickThrough,
    required this.supportsLockPosition,
    required this.requiresRuntimePermission,
    required this.notes,
  });

  final LyricsOverlayPlatform platform;
  final bool supportsSystemOverlay;
  final bool supportsTransparentWindow;
  final bool supportsClickThrough;
  final bool supportsLockPosition;
  final bool requiresRuntimePermission;
  final String notes;
}
