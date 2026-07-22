import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Android configure preserves WindowManager layout failures', () {
    final source = File(
      'android/app/src/main/kotlin/com/harmonymusic/player/'
      'DesktopLyricsOverlayService.kt',
    ).readAsStringSync();

    expect(
      source,
      contains('private fun refreshOverlayLayout(): Boolean'),
    );
    expect(
      source,
      contains('private fun resetOverlayPosition(): Boolean'),
    );
    expect(
      source,
      contains('textView.requestLayout()'),
    );
    expect(
      source,
      contains('textView.invalidate()'),
    );
    expect(
      source,
      matches(
        RegExp(
          r'private fun refreshOverlayLayout\(\): Boolean'
          r'.*?catch \(exception: RuntimeException\) \{'
          r'.*?setOverlayState\(\s*STATUS_ERROR,'
          r'.*?return false',
          dotAll: true,
        ),
      ),
    );
    expect(
      source,
      matches(
        RegExp(
          r'val configurationApplied ='
          r'\s*serviceInstance\?\.applyConfiguration'
          r'\(configuration, resetPosition\) \?: true'
          r'\s*if \(!configurationApplied\) \{'
          r'\s*return statusMap\(context, state = STATUS_ERROR\)'
          r'\s*\}'
          r'\s*setOverlayState\(STATUS_UPDATED,',
          dotAll: true,
        ),
      ),
    );
  });

  test('Android renders split lyrics with per-line alignment spans', () {
    final source = File(
      'android/app/src/main/kotlin/com/harmonymusic/player/'
      'DesktopLyricsOverlayService.kt',
    ).readAsStringSync();

    expect(
        source, contains('private const val TEXT_ALIGNMENT_SPLIT = "split"'));
    expect(
      source,
      matches(
        RegExp(
          r'TEXT_ALIGNMENT_LEFT,\s*TEXT_ALIGNMENT_SPLIT\s*'
          r'-> Gravity\.LEFT or Gravity\.CENTER_VERTICAL',
        ),
      ),
    );
    expect(
      source,
      contains('AlignmentSpan.Standard(Layout.Alignment.ALIGN_NORMAL)'),
    );
    expect(
      source,
      contains('AlignmentSpan.Standard(Layout.Alignment.ALIGN_OPPOSITE)'),
    );
    expect(
      source,
      matches(
        RegExp(
          r'private fun updateOverlayText\(text: String\) \{'
          r'.*?displayedText\(\s*text,\s*'
          r'overlayConfiguration\(this\)\.textAlignment,?\s*\)',
          dotAll: true,
        ),
      ),
    );
  });
}
