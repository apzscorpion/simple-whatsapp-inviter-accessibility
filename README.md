# Simple WhatsApp Inviter

A one-button Android app for parents: pick a person, tap **Invite**, WhatsApp opens on their chat with
the invitation card and message already filled in, tap the green **Send**.

- Lists phone contacts with their photos; "On WhatsApp" shows only people WhatsApp found in the contacts.
- Search by name, or **Type a number** for someone not saved.
- ✓ Sent mark per person (stored on the phone).
- The message, link and image are set remotely by you, not on the parents' phone.

## How WhatsApp is involved
Android apps cannot read WhatsApp's own contact list or profile pictures, and cannot press Send. Photos come
from the phone's contacts; the parent presses Send in WhatsApp. If WhatsApp isn't installed, it falls back
to a wa.me link (text only).

## Changing the invitation (inside the app, no app update)
**Long-press the "Send Invitation" title** (or tap Invite before anything is set) to open the Invitation screen:
type the message (`{name}` becomes the person's name, paste your link in it), **Choose picture**, **Save**.

- **Only this phone:** that's it.
- **Every phone, from your own phone:** once, open **Advanced** and paste a GitHub key. From then on Save also
  updates [preset.json](preset.json) here, and every phone picks it up the next time the app opens.
  Make the key at github.com → Settings → Developer settings → Fine-grained tokens → Generate:
  Repository access "Only select repositories" → this repo; Permissions → **Contents: Read and write**.
  Put the key only on your phone, not your parents'.
- A change made on the parents' phone stays until the shared invitation changes again.

You can also edit [preset.json](preset.json) on github.com directly.

## Install
Download the APK from [Releases](../../releases) and open it on the phone (allow "Install unknown apps").

## Build / release
```
flutter test
flutter build apk --release
git tag v1.0.0 && git push origin v1.0.0   # GitHub Actions builds the APK and attaches it to a Release
```
