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

## Setting the invitation (remote)
1. Create a **secret gist** at https://gist.github.com with a file `preset.json` shaped like
   [preset.example.json](preset.example.json). `{name}` becomes the contact's name. Put the link inside the message.
   `image` is a direct link to a JPG/PNG (leave it `""` for no image).
2. Click **Raw**, copy the URL and remove the commit hash part, so it looks like
   `https://gist.githubusercontent.com/<you>/<id>/raw/preset.json` (always the latest version).
3. On the parents' phone: **long-press the "Send Invitation" title** → Settings → paste the link, set a PIN → Save.

The app re-downloads the preset each time it opens (GitHub may cache it for ~5 minutes) and keeps the last copy for offline use.

## Install
Download the APK from [Releases](../../releases) and open it on the phone (allow "Install unknown apps").

## Build / release
```
flutter test
flutter build apk --release
git tag v1.0.0 && git push origin v1.0.0   # GitHub Actions builds the APK and attaches it to a Release
```
