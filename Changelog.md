# Changelog

## 2026-09-25

### Interface
- Identified and corrected touch-device scaling logic so phones no longer fall back to the reduced layout after startup.
- Prevented the built-in device scaler from reverting the phone interface to a reduced UIScale.
- Fixed phone fullscreen sizing so the interface content uses normal scale instead of a reduced mobile UIScale.
- Phone controls, switches, input fields, and text now keep their intended size while the main panel fills the screen.

## 2026-09-25

### Interface
- Fixed mobile full-screen scaling so the main interface no longer alternates between small and large sizes.
- The mobile layout now follows the built-in device scale instead of fighting it.

## 2026-09-25

### Interface
- Made the PulseCore interface use nearly the entire screen on phones.
- Kept desktop and larger touch-device layout behavior unchanged.

## 2026-09-22

### Interface
- Made script icon preparation synchronous so the PNG is available before the header icon is created.
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
