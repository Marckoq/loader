# Changelog

## 2026-09-25

### Performance
- Reduced Auto Counter enemy-model rescanning from every frame to once every 0.25 seconds while the feature is enabled.
- Removed the ability-notification per-frame GUI descendant scan and replaced it with event-driven button state tracking.
- Kept event-based attack detection unchanged so the optimization does not require a constant full model scan.

## 2026-09-25

### Stability
- Restored `PulseCore.lua` to the previously verified stable loader state after the recent main-file changes caused the interface to disappear.
- Preserved the 2.6.0 runtime version override and existing sidebar/mobile wrapper fixes from the stable state.

## 2026-09-25

### Local
- Temporarily removed the No Jump Cooldown feature and its jump input handler from the PulseCore enhancements module.

## 2026-09-25

### Stability
- Restored the last verified working main PulseCore loader so the interface loads normally again.
- Kept the experimental No Jump Cooldown and ability notification implementation isolated in `PulseCoreEnhancements.lua` instead of letting it affect the main loader.

## 2026-09-25

### Stability
- Restored the known working PulseCore loader structure after the interface disappeared.
- The enhancement module is now loaded one second after PulseCore initialization and is isolated so its errors cannot block the main interface.
- Removed the extra forced jump call that could make one jump request produce two jumps.

### Local
- No Jump Cooldown now keeps the Roblox Jumping state enabled instead of manually forcing a second jump.

## 2026-09-25

### Stability
- Restored the last confirmed working PulseCore interface loader after the experimental enhancement injection caused the interface to disappear.
- Kept the mobile scaling and tab-panel changes from the stable version.
- Kept PulseCore runtime version 2.6.0.
- The experimental No Jump Cooldown and ability notification module remains stored separately and is not loaded by the main script until its integration is stable.

## 2026-09-25

### Local
- Fixed No Jump Cooldown so the first jump uses Roblox's normal jump handling instead of forcing an extra jump.
- A jump request made while airborne is now queued and executed once after landing, preventing a single press from producing a double jump.

## 2026-09-25

### Stability
- Isolated the optional enhancement module from the main PulseCore loader so enhancement errors cannot prevent the main interface from loading.
- Added a short startup delay before loading the enhancement module.

## 2026-09-25

### Local
- Fixed No Jump Cooldown causing one jump input to trigger an extra jump.
- Grounded jump requests now rely on Roblox's normal jump handling; the enhancement only queues an additional jump when another jump is actually requested while airborne.

## 2026-09-25

### Stability
- Restored the previously working PulseCore loader after the enhancement wrapper caused the main interface to stop appearing.
- Moved the new No Jump Cooldown and ability notification logic into a separate lightweight enhancement module loaded after PulseCore initializes.
- Kept the main obfuscated payload unchanged.

## 2026-09-25

### Local
- Added a default-enabled `No Jump Cooldown` toggle for the local player.
- Added queued jump handling so a jump request made during airborne time is executed immediately when the character becomes grounded.

### Notifications
- Added persistent ability activation notifications showing the ability name, duration, and activation delay.
- Notifications use a black translucent background, gray outline, rounded corners, PulseCore title, close button, and an internal duration progress bar.
- The active notification is replaced when another ability is activated and closes when the current ability stops or ends.

## 2026-09-25

### Mobile
- Removed the mobile instability warning notification from the main PulseCore script as requested.

## 2026-09-25

### Mobile
- Changed the mobile warning notification text to English.

## 2026-09-25

### Mobile
- Added a 5-second PulseCore warning notification to the main script for mobile devices.
- The notification uses a black background with a red outline, a close button, device-responsive scaling, and a bottom progress bar that stays inside the notification bounds.

## 2026-09-25

### Mobile
- Changed the mobile interface from fullscreen to a compact square panel sized automatically for the phone viewport.
- Reduced the scale of the mobile panel contents, including buttons, fields, and text, to 90%.
- Kept the compact square layout responsive when the phone viewport changes.

## 2026-09-25

### Mobile
- Added a separate `PulseCoreMobile.lua` build that uses the same PulseCore feature set but a phone-first interface.
- Added a dedicated touch capture surface for the sidebar so tabs can be swiped vertically without relying on Roblox's native ScrollingFrame touch handling.
- Preserved normal tab activation by detecting taps separately from vertical swipes.
- Kept the mobile layout fullscreen with normal UIScale.

## 2026-09-25

### Interface
- Added manual finger-drag scrolling for the entire sidebar tab panel, including when the touch starts directly on a tab button.

## 2026-09-25

### Interface
- Fixed the sidebar tab panel scrolling hook so the entire tab panel responds to mouse-wheel input when the cursor is over it.
- Recalculated the tab panel canvas height from the actual tab content and viewport, ensuring the panel is genuinely scrollable when tabs exceed the visible area.

## 2026-09-25

### Release
- Restored the stable obfuscated payload after the version-change issue and preserved the 2.6.0 runtime version override.
- Bumped PulseCore version to 2.6.0 as requested.

## 2026-09-25

### Interface
- Made the entire sidebar tab panel itself touch-scrollable, with a visible scrollbar and elastic mobile scrolling.
- Added a dedicated vertical scroller for the sidebar tabs so they can be swiped on small touch screens.
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
