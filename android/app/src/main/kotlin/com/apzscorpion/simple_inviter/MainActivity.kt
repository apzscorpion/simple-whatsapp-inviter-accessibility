package com.apzscorpion.simple_inviter

import android.content.ActivityNotFoundException
import android.content.Intent
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "inviter").setMethodCallHandler { call, result ->
            if (call.method != "send") return@setMethodCallHandler result.notImplemented()
            val phone = call.argument<String>("phone")!!
            val text = call.argument<String>("text") ?: ""
            val image = call.argument<String>("image")
            val intent = Intent(Intent.ACTION_SEND).apply {
                // "jid" is WhatsApp's unofficial extra that opens this chat directly instead of the chat picker.
                putExtra("jid", "$phone@s.whatsapp.net")
                putExtra(Intent.EXTRA_TEXT, text)
                if (image != null && File(image).exists()) {
                    type = "image/*"
                    putExtra(Intent.EXTRA_STREAM, FileProvider.getUriForFile(this@MainActivity, "$packageName.files", File(image)))
                    addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                } else {
                    type = "text/plain"
                }
            }
            for (pkg in listOf("com.whatsapp", "com.whatsapp.w4b")) {
                try {
                    startActivity(intent.setPackage(pkg))
                    return@setMethodCallHandler result.success(true)
                } catch (_: ActivityNotFoundException) {}
            }
            result.success(false)
        }
    }
}
