package com.harmonymusic.player

internal enum class SystemMediaControlSlot {
    PLAYBACK_MODE,
    PREVIOUS,
    PLAY_PAUSE,
    NEXT,
}

internal data class SystemMediaControlSlotPlan(
    val slots: List<SystemMediaControlSlot>,
    val customActionOrder: List<String>,
    val advertisePreviousAction: Boolean,
    val advertiseNextAction: Boolean,
    val previousActionEnabled: Boolean,
    val nextActionEnabled: Boolean,
)

internal object SystemMediaControlSlotPlanner {
    private val FIXED_SLOT_ORDER = listOf(
        SystemMediaControlSlot.PLAYBACK_MODE,
        SystemMediaControlSlot.PREVIOUS,
        SystemMediaControlSlot.PLAY_PAUSE,
        SystemMediaControlSlot.NEXT,
    )

    fun create(
        canSkipPrevious: Boolean,
        canSkipNext: Boolean,
    ): SystemMediaControlSlotPlan {
        return SystemMediaControlSlotPlan(
            slots = FIXED_SLOT_ORDER,
            customActionOrder = listOf(
                SystemMediaSessionManager.ACTION_CYCLE_PLAYBACK_MODE,
            ),
            advertisePreviousAction = true,
            advertiseNextAction = true,
            previousActionEnabled = canSkipPrevious,
            nextActionEnabled = canSkipNext,
        )
    }
}
