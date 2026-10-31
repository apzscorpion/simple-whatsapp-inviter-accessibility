package com.apzscorpion.simple_inviter

import android.content.ActivityNotFoundException
import android.content.ComponentName
import android.content.Intent
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private val main = Handler(Looper.getMainLooper())
    private var pending: MethodChannel.Result? = null

    private fun finish(outcome: String) {
        pending?.success(outcome)
        pending = null
    }

    private fun autoSendOn(): Boolean {
        val me = ComponentName(this, SendService::class.java).flattenToString()
        val on = Settings.Secure.getString(contentResolver, Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES) ?: ""
        return on.split(':').any { it.equals(me, ignoreCase = true) }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "inviter").setMethodCallHandler { call, result ->
            when (call.method) {
                "autoSendOn" -> result.success(autoSendOn())
                "openAutoSendSettings" -> {
                    startActivity(Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS))
                    result.success(null)
                }
                "send" -> send(call.argument<String>("phone")!!, call.argument<String>("text") ?: "", call.argument<String>("image"), result)
                else -> result.notImplemented()
            }
        }
    }

    /** Result: "sent" (pressed Send for them), "opened" (they must tap Send), "missing" (no WhatsApp). */
    private fun send(phone: String, text: String, image: String?, result: MethodChannel.Result) {
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
        val auto = autoSendOn()
        main.removeCallbacksAndMessages(null) // an earlier invite's timers must not end this one
        finish("opened") // an earlier send still waiting
        if (auto) {
            pending = result
            SendService.onSent = {
                main.postDelayed({
                    // Back to the list once WhatsApp has taken the message. Started from the accessibility
                    // service because Android 10+ blocks a background activity from bringing itself forward.
                    val back = Intent(this, MainActivity::class.java)
                        .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_REORDER_TO_FRONT)
                    (SendService.instance ?: this).startActivity(back)
                    finish("sent")
                }, 1200)
            }
            SendService.arm()
        }
        for (pkg in SendService.PACKAGES) {
            try {
                startActivity(intent.setPackage(pkg))
                if (auto) {
                    // Poll as well as react to events: a warm WhatsApp can settle with no events after the 1 s guard,
                    // and an old phone can take many seconds to show the chat.
                    val started = SystemClock.elapsedRealtime()
                    val poll = object : Runnable {
                        override fun run() {
                            if (pending == null) return
                            if (SystemClock.elapsedRealtime() - started > SendService.TIMEOUT_MS) return finish("opened")
                            SendService.instance?.tryClick()
                            main.postDelayed(this, 300)
                        }
                    }
                    main.postDelayed(poll, 1000)
                } else {
                    result.success("opened")
                }
                return
            } catch (_: ActivityNotFoundException) {}
        }
        SendService.armedAt = 0
        if (auto) finish("missing") else result.success("missing")
    }
}
