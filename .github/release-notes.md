## Install

1. Download **StayPrivate-__VERSION__.dmg** below, open it and drag **Stay Private** onto **Applications**.
2. **First launch:** the app is not notarized by Apple, so macOS blocks it once. On macOS 15 or later open **System Settings → Privacy & Security** and click **Open Anyway**. On macOS 13 or 14 right-click the app and choose **Open**. Or run: `xattr -dr com.apple.quarantine "/Applications/Stay Private.app"`
3. Install the WireGuard tools once: `brew install wireguard-tools`
4. Click the keyhole icon in the menu bar → **Install helper…** (asks for your Mac password once).
5. Get a free WireGuard config (the menu has a **How to get a config** guide), then **Import config…** → **Connect**.

Full guides: [README](https://github.com/Puvistyne-tech/stay-private-vpn#readme)

**Requires** macOS 13 or later, Apple Silicon or Intel.

**Check your download:** `shasum -a 256 -c StayPrivate-__VERSION__.dmg.sha256` (run in the folder that holds both files).

## What's changed
