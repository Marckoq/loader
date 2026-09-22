# Changelog

## 2026-09-22

### Interface
- Added the repository image `images (1).png` as the PulseCore header icon.
- Added an orange `BETA` badge with a white outline next to the version.
- The icon is stored locally under `Real\\workspace\\PulseCore\\assets\\images (1).png` and loaded through the executor asset API.

## 2026-09-22

### ESP
- Moved the separate ESP INFO panel to the left side of the screen.
- Added distance display in studs.
- Added role-colored tracers.
- Added Survivor HP and status display.
- Added a separate ability/cooldown information panel that remains visible when the main PulseCore interface is minimized.
- Reduced ESP cooldown scanning to a low-frequency cached update to avoid gameplay lag.
- Replaced internal animation-marker labels with readable ability names, including Blaze: `Sol Flame` and `Burning Javelin`.
- Dead character models are excluded from ESP.

### Interface
- Removed the Cool Button and its local-video playback code.
