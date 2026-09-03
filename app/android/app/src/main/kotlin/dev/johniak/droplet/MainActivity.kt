package dev.johniak.droplet

import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private lateinit var launcher: LauncherChannel

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        launcher = LauncherChannel(this)
        launcher.attach(MethodChannel(flutterEngine.dartExecutor.binaryMessenger, LauncherChannel.NAME))
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (::launcher.isInitialized && launcher.onActivityResult(requestCode, resultCode, data)) return
        super.onActivityResult(requestCode, resultCode, data)
    }
}
