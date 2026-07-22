package com.harmonymusic.player

import org.junit.Assert.assertEquals
import org.junit.Test

class DesktopLyricsOverlayWidthCalculatorTest {
    @Test
    fun `single line uses measured lyric width plus padding`() {
        assertEquals(
            181,
            calculateWidth(
                text = "current lyric",
                measuredWidths = mapOf("current lyric" to 140.2f),
            ),
        )
    }

    @Test
    fun `two lines use the wider measured lyric`() {
        assertEquals(
            261,
            calculateWidth(
                text = "short\nconsiderably wider",
                measuredWidths = mapOf(
                    "short" to 64f,
                    "considerably wider" to 220.1f,
                ),
            ),
        )
    }

    @Test
    fun `short lyrics keep a usable minimum width`() {
        assertEquals(
            160,
            calculateWidth(
                text = "hi",
                measuredWidths = mapOf("hi" to 18f),
            ),
        )
    }

    @Test
    fun `long lyrics stay inside the screen safe maximum`() {
        assertEquals(
            328,
            calculateWidth(
                text = "very long lyric",
                measuredWidths = mapOf("very long lyric" to 600f),
                maximumWidth = 328,
            ),
        )
    }

    @Test
    fun `invalid measured widths cannot escape width bounds`() {
        assertEquals(
            160,
            calculateWidth(
                text = "invalid",
                measuredWidths = mapOf("invalid" to Float.NaN),
            ),
        )
    }

    private fun calculateWidth(
        text: String,
        measuredWidths: Map<String, Float>,
        maximumWidth: Int = 720,
    ): Int {
        return DesktopLyricsOverlayWidthCalculator.calculate(
            text = text,
            measureLine = { line -> measuredWidths.getValue(line) },
            horizontalPadding = 40,
            minimumWidth = 160,
            maximumWidth = maximumWidth,
        )
    }
}
