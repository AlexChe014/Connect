package org.jitsi.jitsi_meet_flutter_sdk

import android.app.Activity
import android.app.Application
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.media.AudioDeviceCallback
import android.media.AudioDeviceInfo
import android.media.AudioManager
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.view.View
import android.view.WindowManager
import androidx.localbroadcastmanager.content.LocalBroadcastManager
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory
import org.jitsi.meet.sdk.BroadcastEvent
import org.jitsi.meet.sdk.ConnectAudioRoutes
import org.jitsi.meet.sdk.JitsiMeetActivityDelegate
import org.jitsi.meet.sdk.JitsiMeetOngoingConferenceService
import org.jitsi.meet.sdk.JitsiMeetView

/** Connect fork: creates the embedded conference for `JitsiMeetConferenceView`. */
class JitsiMeetConferenceViewFactory(
    private val activityProvider: () -> Activity?
) : PlatformViewFactory(StandardMessageCodec.INSTANCE) {
    override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
        val activity = activityProvider()
            ?: throw IllegalStateException("Jitsi conference view needs an attached activity")
        @Suppress("UNCHECKED_CAST")
        return JitsiMeetConferencePlatformView(activity, args as? Map<String, Any?> ?: emptyMap())
    }
}

/**
 * Joins on creation, leaves on dispose. Does what JitsiMeetActivity does for
 * its own view: forwards the activity lifecycle to React Native, relays SDK
 * broadcasts as events, runs the ongoing-call service and keeps the screen
 * on (and over the lock screen when the call was answered there).
 *
 * The host activity must be a FragmentActivity implementing
 * JitsiMeetActivityInterface.
 */
class JitsiMeetConferencePlatformView(
    private val activity: Activity,
    arguments: Map<String, Any?>
) : PlatformView {
    companion object {
        const val VIEW_TYPE = "jitsi_meet_flutter_sdk/conference_view"

        var active: JitsiMeetConferencePlatformView? = null
            private set
    }

    private val eventStreamHandler = JitsiMeetEventStreamHandler.instance
    private val handler = Handler(Looper.getMainLooper())
    private val audioManager = activity.getSystemService(Context.AUDIO_SERVICE) as AudioManager
    private var jitsiView: JitsiMeetView? = JitsiMeetView(activity)
    private var disposed = false

    private val broadcastReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            onBroadcastReceived(intent)
        }
    }

    private val audioDeviceCallback = object : AudioDeviceCallback() {
        override fun onAudioDevicesAdded(addedDevices: Array<out AudioDeviceInfo>?) {
            notifyAudioRouteSoon()
        }

        override fun onAudioDevicesRemoved(removedDevices: Array<out AudioDeviceInfo>?) {
            notifyAudioRouteSoon()
        }
    }

    private val lifecycleCallbacks = object : Application.ActivityLifecycleCallbacks {
        override fun onActivityResumed(a: Activity) {
            if (a === activity) JitsiMeetActivityDelegate.onHostResume(activity)
        }

        override fun onActivityStopped(a: Activity) {
            if (a === activity) JitsiMeetActivityDelegate.onHostPause(activity)
        }

        override fun onActivityDestroyed(a: Activity) {
            if (a === activity) JitsiMeetActivityDelegate.onHostDestroy(activity)
        }

        override fun onActivityCreated(a: Activity, savedInstanceState: Bundle?) {}
        override fun onActivityStarted(a: Activity) {}
        override fun onActivityPaused(a: Activity) {}
        override fun onActivitySaveInstanceState(a: Activity, outState: Bundle) {}
    }

    init {
        active?.dispose()
        active = this

        JitsiMeetActivityDelegate.onHostResume(activity)
        activity.application.registerActivityLifecycleCallbacks(lifecycleCallbacks)

        val filter = IntentFilter()
        for (type in BroadcastEvent.Type.values()) {
            filter.addAction(type.action)
        }
        LocalBroadcastManager.getInstance(activity).registerReceiver(broadcastReceiver, filter)
        audioManager.registerAudioDeviceCallback(audioDeviceCallback, handler)

        setCallWindowFlags(true)
        jitsiView?.join(JitsiMeetPlugin.buildOptions(arguments))
    }

    override fun getView(): View? = jitsiView

    override fun dispose() {
        if (disposed) return
        disposed = true
        if (active === this) active = null

        handler.removeCallbacksAndMessages(null)
        LocalBroadcastManager.getInstance(activity).unregisterReceiver(broadcastReceiver)
        audioManager.unregisterAudioDeviceCallback(audioDeviceCallback)
        activity.application.unregisterActivityLifecycleCallbacks(lifecycleCallbacks)
        JitsiMeetOngoingConferenceService.abort(activity)
        setCallWindowFlags(false)

        jitsiView?.abort()
        jitsiView?.dispose()
        jitsiView = null
    }

    /** Route state settles on Jitsi's audio thread — read it a bit later. */
    fun notifyAudioRouteSoon() {
        handler.postDelayed({
            if (!disposed) eventStreamHandler.emit("audioRouteChanged", ConnectAudioRoutes.state())
        }, 300)
    }

    private fun setCallWindowFlags(enabled: Boolean) {
        val window = activity.window
        if (enabled) {
            window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        } else {
            window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        }
        // A call answered on the lock screen stays visible over it.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            activity.setShowWhenLocked(enabled)
            activity.setTurnScreenOn(enabled)
        } else {
            @Suppress("DEPRECATION")
            val flags = WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON
            if (enabled) window.addFlags(flags) else window.clearFlags(flags)
        }
    }

    private fun onBroadcastReceived(intent: Intent) {
        val event = BroadcastEvent(intent)
        val data = event.data
        when (event.type) {
            BroadcastEvent.Type.CONFERENCE_JOINED -> {
                eventStreamHandler.conferenceJoined(data)
                // Foreground service: keeps the microphone alive in the
                // background and shows the ongoing-call notification.
                JitsiMeetOngoingConferenceService.launch(activity, HashMap(data))
                notifyAudioRouteSoon()
            }
            BroadcastEvent.Type.CONFERENCE_TERMINATED -> {
                JitsiMeetOngoingConferenceService.abort(activity)
                eventStreamHandler.conferenceTerminated(data)
            }
            BroadcastEvent.Type.CONFERENCE_WILL_JOIN -> eventStreamHandler.conferenceWillJoin(data)
            BroadcastEvent.Type.PARTICIPANT_JOINED -> eventStreamHandler.participantJoined(data)
            BroadcastEvent.Type.PARTICIPANT_LEFT -> eventStreamHandler.participantLeft(data)
            BroadcastEvent.Type.AUDIO_MUTED_CHANGED -> eventStreamHandler.audioMutedChanged(data)
            BroadcastEvent.Type.VIDEO_MUTED_CHANGED -> {
                eventStreamHandler.videoMutedChanged(data)
                // Jitsi moves audio between earpiece and speaker with video.
                notifyAudioRouteSoon()
            }
            BroadcastEvent.Type.ENDPOINT_TEXT_MESSAGE_RECEIVED ->
                eventStreamHandler.endpointTextMessageReceived(data)
            BroadcastEvent.Type.SCREEN_SHARE_TOGGLED -> eventStreamHandler.screenShareToggled(data)
            BroadcastEvent.Type.CHAT_MESSAGE_RECEIVED -> eventStreamHandler.chatMessageReceived(data)
            BroadcastEvent.Type.CHAT_TOGGLED -> eventStreamHandler.chatToggled(data)
            BroadcastEvent.Type.PARTICIPANTS_INFO_RETRIEVED ->
                eventStreamHandler.participantsInfoRetrieved(data)
            BroadcastEvent.Type.READY_TO_CLOSE -> {
                JitsiMeetOngoingConferenceService.abort(activity)
                eventStreamHandler.readyToClose()
            }
            BroadcastEvent.Type.CUSTOM_BUTTON_PRESSED -> eventStreamHandler.customButtonPressed(data)
            else -> {}
        }
    }
}
