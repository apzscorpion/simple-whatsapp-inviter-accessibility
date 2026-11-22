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
        // On a rebind the old copy can be destroyed after the new one connected; don't drop the new one.
        if (instance === this) instance = null
        super.onDestroy()
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        tryClick()
    }

    override fun onInterrupt() {}

    fun tryClick() {
        val now = SystemClock.elapsedRealtime()
        // Not before 0.4 s: until then the screen may still be a chat that was already open (the text check guards too).
        if (now < armedAt + 400 || now > armedAt + TIMEOUT_MS) return
        // Every WhatsApp window, not just the active one: a keyboard or popup can hold focus.
        val roots = windows.mapNotNull { it.root }.ifEmpty { listOfNotNull(rootInActiveWindow) }
            .filter { it.packageName?.toString() in PACKAGES }
        if (roots.isEmpty()) return run { reason = "whatsapp" }
        // Is our invitation waiting in a typing box (message box or picture caption)? Editable only: once sent,
        // the same text shows up as a chat bubble, which must not count. null = no text to look for.
        val waiting = if (expect.isEmpty()) null
            else roots.any { r -> r.findAccessibilityNodeInfosByText(expect).any { it.isEditable } }
        val button = roots.firstNotNullOfOrNull { findSend(it) }
        if (lastClick > 0) {
            // After our tap: sent once the text left the typing box. Not "Send button gone", because
            // WhatsApp can keep that button on screen (as the microphone) after sending.
            if (waiting?.not() ?: (button == null)) {
                armedAt = 0
                onSent?.invoke()
                return
            }
        }
        // Only the screen holding our invitation: never press Send on some other chat's draft.
        if (waiting == false) return run { reason = "text" }
        if (button == null) return run { reason = "button" }
        // A tap on a stale view can report success yet do nothing, so tap again if the text is still waiting.
        // 2.5 s apart: an old phone can keep the picture screen up for a while after a tap that worked.
        if (lastClick > 0 && now - lastClick < 2500) return
        reason = "tap"
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
        const val TIMEOUT_MS = 30000L // old phones can take long to open a chat with a picture
        @Volatile var armedAt = 0L
        @Volatile var lastClick = 0L
        @Volatile var expect = "" // a piece of the invitation text that must be on screen

        fun arm(expectText: String) {
            armedAt = SystemClock.elapsedRealtime()
            lastClick = 0
            expect = expectText
            reason = "whatsapp"
        }
        /** Why the last try didn't send: whatsapp (screen not seen), text, button, tap. */
        @Volatile var reason = "whatsapp"
        @Volatile var instance: SendService? = null
        var onSent: (() -> Unit)? = null
    }
}
