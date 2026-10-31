package com.apzscorpion.simple_inviter

import android.accessibilityservice.AccessibilityService
import android.os.SystemClock
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo

/** Presses WhatsApp's Send button once, right after this app opened a chat to send an invitation. */
class SendService : AccessibilityService() {
    override fun onServiceConnected() {
        instance = this
    }

    override fun onDestroy() {
        instance = null
        super.onDestroy()
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        tryClick()
    }

    override fun onInterrupt() {}

    fun tryClick() {
        val now = SystemClock.elapsedRealtime()
        // Not before 1 s: until then the screen may still be a chat that was already open.
        if (now < armedAt + 1000 || now > armedAt + TIMEOUT_MS) return
        // Every WhatsApp window, not just the active one: a keyboard or popup can hold focus.
        val roots = windows.mapNotNull { it.root }.ifEmpty { listOfNotNull(rootInActiveWindow) }
            .filter { it.packageName?.toString() in PACKAGES }
        if (roots.isEmpty()) return
        val button = roots.firstNotNullOfOrNull { findSend(it) }
        if (button == null) {
            // Send button gone after our tap: WhatsApp took the message.
            if (lastClick > 0) {
                armedAt = 0
                onSent?.invoke()
            }
            return
        }
        // A tap on a stale view can report success yet do nothing, so tap again if Send is still there.
        if (now - lastClick < 800) return
        if (button.performAction(AccessibilityNodeInfo.ACTION_CLICK)) lastClick = now
    }

    private fun findSend(root: AccessibilityNodeInfo): AccessibilityNodeInfo? {
        val byId = PACKAGES.flatMap { root.findAccessibilityNodeInfosByViewId("$it:id/send") }
        // English fallback in case WhatsApp renames the view id.
        val byLabel = root.findAccessibilityNodeInfosByText("Send").filter { it.contentDescription?.toString() == "Send" }
        var node = (byId + byLabel).firstOrNull { it.isVisibleToUser } ?: return null
        while (!node.isClickable) node = node.parent ?: return null
        return node
    }

    companion object {
        val PACKAGES = listOf("com.whatsapp", "com.whatsapp.w4b")
        const val TIMEOUT_MS = 15000L
        @Volatile var armedAt = 0L
        @Volatile var lastClick = 0L

        fun arm() {
            armedAt = SystemClock.elapsedRealtime()
            lastClick = 0
        }
        @Volatile var instance: SendService? = null
        var onSent: (() -> Unit)? = null
    }
}
