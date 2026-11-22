# Simple WhatsApp Inviter

A one-button Android app for parents: pick a person, tap **Invite**, WhatsApp opens on their chat with
the invitation card and message already filled in, tap the green **Send**.

- Lists phone contacts with their photos; "On WhatsApp" shows only people WhatsApp found in the contacts.
- Search by name, or **Type a number** for someone not saved.
- ✓ Sent mark per person (stored on the phone).
- The message and picture are built into the app, so they can't get lost on the phone.

## How WhatsApp is involved
Android apps cannot read WhatsApp's own contact list or profile pictures. Photos come from the phone's contacts.
Send is pressed by the auto-send service (below); without it the parent taps Send in WhatsApp. If WhatsApp isn't
installed, it falls back to a wa.me link (text only).

## Changing the invitation
The invitation is built into the app, so nothing is set up on the parents' phone:

- Message: [assets/invitation/message.txt](assets/invitation/message.txt) (`{name}` becomes the person's name; WhatsApp marks like `*bold*` work).
- Picture (optional): put it at `assets/invitation/card.jpg`.

Then release a new version (below) and install it.

## Automatic sending (one-time setup on each phone)
With this on, tapping Invite sends by itself: WhatsApp flashes for a second, the app presses Send, and you're back
on the list with the person marked ✓ Sent.

1. Tap **Turn on** in the yellow box (or Settings → Accessibility → Installed apps).
2. Choose **WhatsApp Inviter auto-send** → switch it on → Allow.
3. Android 13+ may grey it out as a "restricted setting" (apps not from the Play Store). Then: Settings → Apps →
   WhatsApp Inviter → ⋮ (top right) → **Allow restricted settings**, and repeat step 2.

It only acts within 30 seconds after an Invite tap, and never sooner than 0.4 seconds, so it can't send into a chat that was already open.
If it can't send, it leaves WhatsApp open for a normal tap and the app says why.

## Install
Download `whatsapp-inviter-vX.Y.Z.apk` from [Releases](../../releases) and open it on the phone (allow "Install unknown apps").
Only if the phone says the app isn't compatible, use the `-old-phones` file instead.

## Build / release
```
flutter test
flutter build apk --release
git tag v1.0.0 && git push origin v1.0.0   # GitHub Actions builds the APK and attaches it to a Release
```
