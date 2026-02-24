> If you're not sure which file to download, grab **{{DMG_FILENAME}}** — the other files are source archives you can ignore.

## Before you launch Present

Beta builds are ad-hoc signed and not yet notarized with Apple, so macOS Gatekeeper will block the app on first launch. You only need to do this once per download.

1. Move **Present.app** to your Applications folder (or wherever you'd like to keep it).
2. Open **Terminal** and run:
   ```
   xattr -cr /Applications/Present.app
   ```
   Adjust the path if you placed it somewhere else.
3. Launch Present as usual. Gatekeeper won't block it again for this copy.

This step goes away once the app is notarized ([#62](https://github.com/terriann/present/issues/62)).
