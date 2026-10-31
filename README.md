# Simple WhatsApp Inviter

A one-button Android app for parents: pick a person, tap **Invite**, WhatsApp opens on their chat with
the invitation card and message already filled in, tap the green **Send**.

- Lists phone contacts with their photos; "On WhatsApp" shows only people WhatsApp found in the contacts.
- Search by name, or **Type a number** for someone not saved.
- ✓ Sent mark per person (stored on the phone).
- The message, link and image are set remotely by you, not on the parents' phone.

## How WhatsApp is involved
Android apps cannot read WhatsApp's own contact list or profile pictures. Photos come from the phone's contacts.
Send is pressed by the auto-send service (below); without it the parent taps Send in WhatsApp. If WhatsApp isn't
installed, it falls back to a wa.me link (text only).

## Changing the invitation (inside the app, no app update)
Tap the **⚙** button (top right) (or tap Invite before anything is set) to open the Invitation screen:
type the message (`{name}` becomes the person's name, paste your link in it), **Choose picture**, **Save**.

- **Only this phone:** that's it.
- **Every phone, from your own phone:** once, open **Advanced** and paste a GitHub key. From then on Save also
  updates [preset.json](preset.json) here, and every phone picks it up the next time the app opens.
  Make the key at github.com → Settings → Developer settings → Fine-grained tokens → Generate:
  Repository access "Only select repositories" → this repo; Permissions → **Contents: Read and write**.
  Put the key only on your phone, not your parents'.
- A change made on the parents' phone stays until the shared invitation changes again.

You can also edit [preset.json](preset.json) on github.com directly.

## Automatic sending (one-time setup on each phone)
With this on, tapping Invite sends by itself: WhatsApp flashes for a second, the app presses Send, and you're back
on the list with the person marked ✓ Sent.

1. Tap **Turn on** in the yellow box (or Settings → Accessibility → Installed apps).
2. Choose **WhatsApp Inviter auto-send** → switch it on → Allow.
3. Android 13+ may grey it out as a "restricted setting" (apps not from the Play Store). Then: Settings → Apps →
   WhatsApp Inviter → ⋮ (top right) → **Allow restricted settings**, and repeat step 2.

It only acts within 15 seconds after an Invite tap, and never sooner than 1 second, so it can't send into a chat that was already open.
If it can't find WhatsApp's Send button, it leaves WhatsApp open for a normal tap.

## Install
Download `whatsapp-inviter-vX.Y.Z.apk` from [Releases](../../releases) and open it on the phone (allow "Install unknown apps").
Only if the phone says the app isn't compatible, use the `-old-phones` file instead.

## Build / release
```
flutter test
flutter build apk --release
git tag v1.0.0 && git push origin v1.0.0   # GitHub Actions builds the APK and attaches it to a Release
```
