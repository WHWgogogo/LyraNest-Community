package com.harmonymusic.player

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

class SystemMediaActionReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val action = when (intent.action) {
            Intent.ACTION_MEDIA_BUTTON -> SystemMediaSessionManager.actionForMediaButton(intent)
            SystemMediaSessionManager.ACTION_PREVIOUS ->
                SystemMediaSessionManager.ACTION_PREVIOUS
            SystemMediaSessionManager.ACTION_PLAY ->
                SystemMediaSessionManager.ACTION_PLAY
            SystemMediaSessionManager.ACTION_PAUSE ->
                SystemMediaSessionManager.ACTION_PAUSE
            SystemMediaSessionManager.ACTION_NEXT ->
                SystemMediaSessionManager.ACTION_NEXT
            SystemMediaSessionManager.ACTION_CYCLE_PLAYBACK_MODE ->
                SystemMediaSessionManager.ACTION_CYCLE_PLAYBACK_MODE
            else -> null
        }
        action?.let(SystemMediaSessionManager::dispatchFromReceiver)
    }
}
