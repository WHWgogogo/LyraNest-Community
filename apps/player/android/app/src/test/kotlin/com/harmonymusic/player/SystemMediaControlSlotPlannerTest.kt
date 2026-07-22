package com.harmonymusic.player

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class SystemMediaControlSlotPlannerTest {
    @Test
    fun `maps playback modes to matching action icons and labels`() {
        assertEquals(
            SystemMediaActionPresentation(
                label = "\u987a\u5e8f\u64ad\u653e",
                iconResource = R.drawable.ic_system_media_repeat_rounded,
            ),
            SystemMediaSessionManager.playbackModeActionPresentation("sequential"),
        )
        assertEquals(
            SystemMediaActionPresentation(
                label = "\u5217\u8868\u5faa\u73af",
                iconResource = R.drawable.ic_system_media_repeat_rounded,
            ),
            SystemMediaSessionManager.playbackModeActionPresentation("repeatAll"),
        )
        assertEquals(
            SystemMediaActionPresentation(
                label = "\u5355\u66f2\u5faa\u73af",
                iconResource = R.drawable.ic_system_media_repeat_one_rounded,
            ),
            SystemMediaSessionManager.playbackModeActionPresentation("repeatOne"),
        )
        assertEquals(
            SystemMediaActionPresentation(
                label = "\u968f\u673a\u64ad\u653e",
                iconResource = R.drawable.ic_system_media_shuffle_rounded,
            ),
            SystemMediaSessionManager.playbackModeActionPresentation("shuffle"),
        )
    }

    @Test
    fun `reuses Flutter repeat icon for sequential and repeat queue modes`() {
        val icons = listOf(
            "sequential",
            "repeatAll",
            "repeatOne",
            "shuffle",
        ).map {
            SystemMediaSessionManager.playbackModeActionPresentation(it).iconResource
        }

        assertEquals(3, icons.toSet().size)
        assertEquals(icons[0], icons[1])
    }

    @Test
    fun `uses the Flutter desktop lyrics state to switch action resource and label`() {
        val presentations = listOf(false, true, false).map(
            SystemMediaSessionManager::desktopLyricsActionPresentation,
        )

        assertEquals(
            listOf(
                SystemMediaActionPresentation(
                    label = "\u684c\u9762\u6b4c\u8bcd",
                    iconResource = R.drawable.ic_desktop_lyrics_notification,
                ),
                SystemMediaActionPresentation(
                    label = "\u684c\u9762\u6b4c\u8bcd\uff08\u5df2\u5f00\u542f\uff09",
                    iconResource = R.drawable.ic_desktop_lyrics_notification,
                ),
                SystemMediaActionPresentation(
                    label = "\u684c\u9762\u6b4c\u8bcd",
                    iconResource = R.drawable.ic_desktop_lyrics_notification,
                ),
            ),
            presentations,
        )
    }

    @Test
    fun `uses the shared presentation mapping for media session custom actions`() {
        val update = SystemMediaUpdate(
            title = "Track",
            artist = null,
            album = null,
            artworkUrl = null,
            status = "paused",
            isLoading = false,
            positionMs = 0,
            durationMs = 0,
            canSkipPrevious = false,
            canSkipNext = false,
            playbackMode = "shuffle",
            desktopLyricsEnabled = true,
        )

        assertEquals(
            SystemMediaSessionManager.playbackModeActionPresentation("shuffle"),
            SystemMediaSessionManager.customActionPresentation(
                SystemMediaSessionManager.ACTION_CYCLE_PLAYBACK_MODE,
                update,
            ),
        )
        assertEquals(
            SystemMediaSessionManager.desktopLyricsActionPresentation(true),
            SystemMediaSessionManager.customActionPresentation(
                SystemMediaSessionManager.ACTION_TOGGLE_DESKTOP_LYRICS,
                update,
            ),
        )
    }

    @Test
    fun `keeps five fixed slots across playback modes and queue boundaries`() {
        val expectedSlots = listOf(
            SystemMediaControlSlot.PLAYBACK_MODE,
            SystemMediaControlSlot.PREVIOUS,
            SystemMediaControlSlot.PLAY_PAUSE,
            SystemMediaControlSlot.NEXT,
            SystemMediaControlSlot.DESKTOP_LYRICS,
        )
        val queueBoundaries = listOf(
            false to false,
            false to true,
            true to false,
            true to true,
        )

        listOf("sequential", "repeatAll", "repeatOne", "shuffle").forEach { playbackMode ->
            SystemMediaSessionManager.playbackModeActionPresentation(playbackMode)
            queueBoundaries.forEach { (canSkipPrevious, canSkipNext) ->
                val plan = SystemMediaControlSlotPlanner.create(
                    canSkipPrevious = canSkipPrevious,
                    canSkipNext = canSkipNext,
                )

                assertEquals(expectedSlots, plan.slots)
                assertEquals(5, plan.slots.size)
                assertEquals(
                    listOf(
                        SystemMediaSessionManager.ACTION_CYCLE_PLAYBACK_MODE,
                        SystemMediaSessionManager.ACTION_TOGGLE_DESKTOP_LYRICS,
                    ),
                    plan.customActionOrder,
                )
                assertTrue(plan.advertisePreviousAction)
                assertTrue(plan.advertiseNextAction)
                assertEquals(canSkipPrevious, plan.previousActionEnabled)
                assertEquals(canSkipNext, plan.nextActionEnabled)
            }
        }
    }

    @Test
    fun `last queue item keeps next slot while switching to repeat one`() {
        val plans = listOf("repeatAll", "repeatOne", "shuffle").map { playbackMode ->
            SystemMediaSessionManager.playbackModeActionPresentation(playbackMode)
            SystemMediaControlSlotPlanner.create(
                canSkipPrevious = true,
                canSkipNext = false,
            )
        }

        assertTrue(plans.all { it.advertiseNextAction })
        assertTrue(plans.all { !it.nextActionEnabled })
        assertTrue(plans.all { it.slots[3] == SystemMediaControlSlot.NEXT })
        assertTrue(plans.all { it.slots == plans.first().slots })
    }

    @Test
    fun `unavailable transport actions stay disabled without losing their slots`() {
        val plan = SystemMediaControlSlotPlanner.create(
            canSkipPrevious = false,
            canSkipNext = false,
        )

        assertTrue(plan.advertisePreviousAction)
        assertTrue(plan.advertiseNextAction)
        assertFalse(plan.previousActionEnabled)
        assertFalse(plan.nextActionEnabled)
        assertEquals(SystemMediaControlSlot.PREVIOUS, plan.slots[1])
        assertEquals(SystemMediaControlSlot.NEXT, plan.slots[3])
    }
}
