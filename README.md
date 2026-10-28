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

## Changing the invitation (no app update needed)
The app reads [preset.json](preset.json) from this repo every time it opens. Nothing to set up on the phone.

1. **Image:** on github.com open this repo → **Add file → Upload files** → drop the card (e.g. `card.jpg`) → **Commit changes**.
2. **Message:** open [preset.json](preset.json) → pencil icon (Edit) → change the text → **Commit changes**.
   - `{name}` becomes the contact's name. Put the link inside the message. `
` is a new line.
   - `"image"`: `"https://raw.githubusercontent.com/apzscorpion/simple-whatsapp-inviter-accessibility/main/card.jpg"`,
     or `""` for no image.
3. Close and reopen the app on the phone (GitHub can take up to 5 minutes to show the new version).

Advanced: long-press the "Send Invitation" title for Settings (country code, PIN, or a different preset link).

## Install
Download the APK from [Releases](../../releases) and open it on the phone (allow "Install unknown apps").

## Build / release
```
flutter test
flutter build apk --release
git tag v1.0.0 && git push origin v1.0.0   # GitHub Actions builds the APK and attaches it to a Release
```
