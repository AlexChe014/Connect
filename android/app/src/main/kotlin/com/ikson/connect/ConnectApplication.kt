package com.ikson.connect

import android.app.Application
import android.content.Intent
import android.os.Bundle
import android.util.Log
import com.hiennv.flutter_callkit_incoming.CallkitConstants
import com.hiennv.flutter_callkit_incoming.CallkitEventCallback
import com.hiennv.flutter_callkit_incoming.FlutterCallkitIncomingPlugin

/**
 * Когда приложение полностью убито, Accept входящего звонка обрабатывает
 * headless-движок flutter_callkit_incoming (CallkitBackgroundExecutor) —
 * у него нет привязанной Activity. jitsi_meet_flutter_sdk на Android входит
 * в конференцию через `WrapperJitsiMeetActivity.launch(activity!!, ...)` —
 * без Activity это падает NPE, и звонок тихо завершается, а приложение не
 * выходит на передний план (аналог requestSceneSessionActivation в
 * AppDelegate.swift на iOS, но для случая полностью убитого процесса).
 *
 * Поднимаем MainActivity сами через нативный колбэк плагина, который
 * вызывается синхронно из CallkitIncomingBroadcastReceiver независимо от
 * состояния Dart/Flutter. Дальше recoverPendingAcceptedCalls()
 * (IncomingCallService, main.dart) подхватит принятый звонок уже в движке с
 * реальной Activity и войдёт в Jitsi там.
 */
class ConnectApplication : Application() {
    // registerEventCallback хранит только WeakReference — держим сильную
    // ссылку, иначе колбэк могут собрать до следующего звонка.
    private val callAcceptForegroundCallback = object : CallkitEventCallback {
        override fun onCallEvent(event: CallkitEventCallback.CallEvent, callData: Bundle) {
            if (event != CallkitEventCallback.CallEvent.ACCEPT) return

            val callId = callData.getString(CallkitConstants.EXTRA_CALLKIT_ID, "")
            Log.d(TAG, "CallKit ACCEPT (id=$callId): bringing MainActivity to front")

            val intent = Intent(this@ConnectApplication, MainActivity::class.java).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_REORDER_TO_FRONT)
            }
            try {
                startActivity(intent)
            } catch (e: Exception) {
                Log.e(TAG, "Failed to bring MainActivity to front on call accept", e)
            }
        }
    }

    override fun onCreate() {
        super.onCreate()
        FlutterCallkitIncomingPlugin.registerEventCallback(callAcceptForegroundCallback)
    }

    companion object {
        private const val TAG = "ConnectApplication"
    }
}
