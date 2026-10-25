package com.ikson.connect

import android.content.Intent
import android.os.Build
import android.os.Bundle
import androidx.core.splashscreen.SplashScreen.Companion.installSplashScreen
import com.facebook.react.modules.core.PermissionListener
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import org.jitsi.meet.sdk.JitsiMeetActivityDelegate
import org.jitsi.meet.sdk.JitsiMeetActivityInterface

/**
 * Экран конференции Jitsi встроен во Flutter (platform view), поэтому
 * MainActivity делает то же, что JitsiMeetActivity для своего вида:
 * FragmentActivity (нужна react-native-screens внутри Jitsi) и
 * JitsiMeetActivityInterface (без него JitsiMeetView не создаётся).
 * Жизненный цикл в React Native передаёт сам плагин.
 */
class MainActivity : FlutterFragmentActivity(), JitsiMeetActivityInterface {
    override fun onCreate(savedInstanceState: Bundle?) {
        installSplashScreen()
        super.onCreate(savedInstanceState)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Замок приложения: Android снимает превью для «Недавних» раньше,
        // чем Flutter успевает закрыть экран заставкой, — прячем его
        // системно. FLAG_SECURE не берём: он запретил бы и скриншоты.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "connect/app_lock")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "setRecentsHidden" -> {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                            setRecentsScreenshotEnabled(call.arguments != true)
                        }
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    override fun requestPermissions(
        permissions: Array<String>,
        requestCode: Int,
        listener: PermissionListener?,
    ) {
        JitsiMeetActivityDelegate.requestPermissions(this, permissions, requestCode, listener)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        JitsiMeetActivityDelegate.onRequestPermissionsResult(requestCode, permissions, grantResults)
    }

    // Демонстрация экрана: разрешение MediaProjection приходит сюда.
    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        JitsiMeetActivityDelegate.onActivityResult(this, requestCode, resultCode, data)
    }
}
