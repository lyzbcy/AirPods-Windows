# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.5.0] - 2026-08-19

### Added
- **Star Pudding pet popup** (user request, the "moe" upgrade): clicking the tray icon now pops out the 星星布丁 girl from the bottom-right corner — waiting pose + "连接中…" while connecting, jumping + hearts + "连上啦！💕" on success, waving "已断开 💤 拜拜~" on disconnect, deflated "没连上 QAQ" on failure. Transparent always-on-top no-activate WebView2 window with spring pop-in/fade-out.
- Assets pipeline: `webui/build_pet.ps1` inlines the pet spritesheet (cropped 6-row atlas from `~/.codex/pets/xingxing-pudding`, 52KB webp) into `webui/pet_built.html`; frame durations follow the hatch-pet spec.
- `/testpet` CLI mode: cycles all five popup states for QA/screenshots.
- petready handshake so the first state is never lost to page load.


## [1.4.0] - 2026-08-19

### Added
- **Three-state tray icons with curated sticker faces** (Mac parity, user request): disconnected = 可爱 face on cream base, connected = 心动 face on green ring, connecting = 加油 face + 6-frame rotating-arc spinner. Regenerate via `assets/make_tray_icons.ps1`. Supersedes the v-unreleased two-frame blink on Windows (same intent, richer states).
- **Independent tray watchdog (2s)**: tray state no longer depends on the web UI's `statuspoll` — hidden WebView2 windows get throttled timers, which previously stalled icon updates.
- Centralized busy-state: `DoAction` now wraps every path (tray left-click, menu, UI buttons) in `SetTrayLoading(true/false)`.


## [Unreleased]

### Added
- **Connecting busy-state (both platforms)**: headset connect takes a few seconds and users re-clicked because nothing seemed to happen. Mac now shows a braille spinner in the menu bar ("连接中…"), ignores clicks mid-operation, and runs Bluetooth work off the main thread so the UI never freezes (it used to block up to 8s). Windows blinks the tray icon between on/off states with an "操作进行中…" tooltip during `DoAction` (covers both tray clicks and UI buttons). Note: Windows tray left-click toggle already exists since v1.3.1 (`A_TrayMenu.Default` + `Click := 1`); if it doesn't work on the Windows machine, the running exe is stale — rebuild with `compile_autohotkey.ps1` after `git pull`.
- **Dev/test launchers**: double-clickable `mac/AirPodsBuddyMac/run.command` (auto incremental build + launch, keeps window open on failure) and `run.bat` (root, detached-start of `dist/AirPodsBuddy.exe` respecting pitfall B1). These are for daily development; unified packaging (.app/DMG + Windows installer) comes at release time per roadmap.

### Fixed (macOS)
- **Left-click toggle stuck on "connect"** (real-device bug): the toggle branched on `Watchdog.armed` instead of the headset's actual connection state, so with the watchdog pref off the icon stayed 💤 forever and left-click could never disconnect (user's log showed 6 consecutive `toggle → connected`). Toggle and icon now treat `armed || isConnected` as connected.
- **Mac first successful build**: `swift build -c release` passes on a real Mac (arm64). Two scaffold bugs fixed: `CFString("")` is not constructible in Swift (→ `var name: CFString = "" as CFString`), and `Watchdog.tick()` was `private` while `StatusBarController` calls it on startup (→ `internal`). Smoke test passed: app boots, writes to `~/Library/Logs/AirPodsBuddyMac.log`, zero popups. Real-AirPods field testing (connect / anti-hijack / output lock) still pending — see `doc/06`. Also added `mac/AirPodsBuddyMac/.build/` to `.gitignore`.

## [1.3.1] - 2026-08-19

### Fixed
- **Window dragging (take 2)**: the `WM_NCLBUTTONDOWN` bridge was blocked by WebView2's mouse capture; replaced with a manual drag loop (`GetCursorPos` + `SetWindowPos` while LButton held) which works regardless of capture.

### Added
- **Tray left-click toggle**: single left-click on the tray icon now toggles connect/disconnect (menu moved to right-click only) — one step instead of two.
- **Tray status icons**: disconnected = original pudding icon, connected = green-ring pudding (`assets/star_pudding_on.ico`, generated via `make_ico.ps1`); icon and tooltip update on state change.
- **macOS variant started**: `mac/AirPodsBuddyMac` Swift menu-bar app scaffold — left-click toggle, emoji state icons, and an anti-hijack watchdog (reconnects the AirPods and re-locks CoreAudio default output every 2s; only a user-initiated disconnect stops it). Reuses upstream's IOBluetooth core. See `mac/README.md` (not yet compiled — no Mac on the dev machine).

## [1.3.0] - 2026-08-19

### Added
- **Window dragging**: grab the top bar / header to move the borderless window (JS bridge → `WM_NCLBUTTONDOWN`).
- **Device priority system**: reorder devices with ▲▼ per card (persisted to `device_priority.txt`); "one-click connect" (tray & hero orb) now follows this user-defined order; Apple devices (AirPods/Beats) sort ahead of others by default, others get an "其他" tag.
- **Hero orb**: big circular 3D connect button showing the current priority target; tap to connect/disconnect.
- Rounder, more minimal UI: circular 3D action buttons, pill cards (radius 22), squarer window (460×600), Esc closes modals.
- **Proper app icon**: `star_pudding.ico` embedded at compile time — tray/taskbar now show the pudding avatar instead of the default "H".

### Fixed
- `TypeError: Expected a Number but got a String` in device sorting — AHK v2 `<` is numeric-only; use `StrCompare` for name ordering.
- Device JSON was silently truncated (multi-line juxtaposition doesn't continue statements in v2) — single-line concatenation.

## [1.2.0] - 2026-08-19

### Fixed
- **White screen on launch**: WebView2 controller created on a hidden window starts with `IsVisible=false`, suspending rendering while page JS keeps running. Now `SyncWebView()` re-fills bounds and forces visibility on every show/resize.
- **AHK error dialog popups**: a diagnostic timer accessed `.Result` on a Promise-resolved string, causing unhandled rejection dialogs. Diagnostics removed in favor of the new logging system.
- **Device list never rendered**: `Reply()` injected bare JSON so the frontend `JSON.parse()`d already-parsed objects ("[object Object]" errors every 4s). All non-literal payloads are now wrapped with `JsonStr()`.
- **App exited on window close** instead of staying in tray: added `Persistent`.

### Added
- Logging system: daily files under `<exe dir>\logs\`, 7-day retention, three-level write fallback (UTF-8 → CP0 → OutputDebugString) so logging can never crash the app.
- Global `OnError` trap: uncaught errors are logged silently instead of popping dialogs on the user's face.
- Frontend forwards `window.onerror` / `unhandledrejection` to the AHK log (`[JS-ERROR]` entries).
- WebView2 creation retries 3× (works around transient AV interference `0x800704C7`).
- `doc/` knowledge base (progressive disclosure) for humans and AI assistants.

### Changed
- Replaced v1-only `EnvSub` with `DateAdd` (v2 has no EnvSub — undefined function calls fail script load silently).

## [1.1.0.1-beta.2] - 2026-07-12

### Fixed
- Include the `ws` runtime dependency in CI-built plugin bundles. Beta 1 could not start on either Windows or macOS and left the Property Inspector on “Detecting devices…”.

### Added
- Experimental macOS 13+ support for the Stream Deck plugin through a native universal Swift helper.
- macOS CI build, parser tests, and an installable beta artifact for hardware testing.

### Changed
- The Stream Deck runtime now selects the Windows or macOS Bluetooth helper automatically.
- System feedback sounds and Bluetooth setup text are platform-aware.

## [1.0.5.0] - 2026-05-31

### Fixed
- **Speaker-only devices now connect** (e.g. Amazon Echo Dot, Bluetooth speakers). Connecting no longer aborts when a device lacks the Handsfree (HFP) profile; each audio profile is toggled independently and the action succeeds if at least one connects.
- **Device names with special characters** no longer break the command — the helper executable is now invoked with an argument array instead of a shell string.
- **Button no longer gets stuck on "Connecting"** when the helper returns unexpected output.
- Standalone script: added a retry cap that previously allowed an infinite loop on unsupported devices.

### Added
- **Device picker** in the Property Inspector — choose a paired device from a dropdown instead of typing its exact name.
- **Live connection state** — the key reflects the device's real connection status when it appears (survives Stream Deck restarts).

### Changed
- Disabled Node debug mode in the published manifest.
- Slimmed the packaged plugin to the runtime dependency only.

## [1.0.4.0] - 2025-12-17

### Fixed
- Resolved disconnect issues and multiple-instance errors for the Marketplace submission.

## [1.0.1] - 2025-12-06

### Changed
- **Compiled AutoHotkey script to standalone executable** - Plugin now uses `BluetoothConnector.exe` instead of runtime + script
- **Improved startup performance** - No script parsing overhead
- **Simplified package structure** - Single executable instead of two files

### Removed
- AutoHotkey64.exe runtime (no longer needed)
- bluetooth_connector.ahk script file (compiled into .exe)

## [1.0.0] - 2025-12-06

### Added

#### Stream Deck Plugin
- **Initial Stream Deck plugin release** - Connect/disconnect Bluetooth devices with a single button press
- **Visual state indicators** - Button shows different states with colored overlays:
  - Disconnected (default icon)
  - Connecting (orange dot)
  - Connected (green dot)
  - Error (red dot)
- **Toggle functionality** - Press once to connect, press again to disconnect
- **Audio notifications** - Windows system sounds for success and error states
- **Visual notifications** - Temporary text display on button ("Connected!", "Disconnected!", "Error!")
- **Multi-device support** - Add multiple plugin instances for different Bluetooth devices
- **Configurable device name** - Set target device in Property Inspector
- **AutoHotkey v2 migration** - Migrated script from v1 to v2 for better performance

#### Core Features
- Bluetooth device connection via Windows Bluetooth API
- Support for audio devices (Handsfree and AudioSink profiles)
- CLI support for automation and integration

### Technical Details
- Built with TypeScript and Node.js
- Uses Stream Deck SDK v2
- AutoHotkey v2 for Windows Bluetooth control
- WebSocket communication between Stream Deck and plugin
- State management for connection tracking

### Package Contents
- Stream Deck plugin with all icons
- AutoHotkey runtime and script
- Property Inspector for configuration
- Complete documentation

---

## [Unreleased]

### Added
- The standalone AutoHotkey script now supports configurable `connect` and `disconnect` actions plus `a2dp` and `a2dp-hfp` audio profiles through editable defaults or command-line arguments.

### Changed
- Stereo-only standalone connections explicitly disable Hands-Free before enabling A2DP, while combined mode preserves the previous stereo-plus-microphone behavior.
- The standalone script now uses the same bounded retry and speaker-only compatibility rules as the Windows helper bundled with the Stream Deck plugin.

### Planned Features
- Configurable connection timeout
- Custom sound notifications
- Auto-reconnect on connection loss
- Connection history and logging

## [1.1.0.5] - 2026-08-06

### Added
- After a successful Windows connection, the plugin now selects and verifies the matching default playback endpoint. With the combined A2DP + HFP profile, it also attempts to select and verify the device's microphone when Windows exposes one.

### Fixed
- Switching Bluetooth targets no longer leaves Windows audio routed to the previously active device.
- Migrating a key from the implicit legacy default device now preserves that device as the pending handoff target, so it is disconnected before the newly selected device connects.

## [1.1.0.4] - 2026-08-06

### Added
- Changing the device assigned to a Stream Deck key now creates an exclusive handoff: the next press disconnects that key's previous audio target before connecting the newly selected one.

### Fixed
- Rapid Property Inspector changes no longer race plugin-side handoff updates or restore an older device selection.
- Connect/disconnect operations no longer report success when one exposed Bluetooth audio service failed to reach the requested state.
- macOS helper failures now preserve `stderr` details for accurate not-found handling and diagnostics.
- Delayed visual-feedback timers can no longer overwrite a newer action or settings state.

## [1.1.0.3] - 2026-08-06

### Fixed
- A2DP-only connections no longer show an error when Windows reports `ERROR_NOT_FOUND` for an already unavailable Hands-Free profile.

## [1.1.0.2] - 2026-08-06

### Added
- Stream Deck keys can now select **Stereo only (A2DP)** or **Stereo + microphone (A2DP + HFP)** on Windows.

### Changed
- Stereo-only connections explicitly disable Hands-Free before enabling A2DP, while existing keys without the new setting retain their combined-profile behavior.
- Stereo-only keys reconcile A2DP on their first press when Windows reports only a device-wide Bluetooth connection.
- Updated the bundled `ws` runtime dependency to 8.21.2.

### Fixed
- Manual helper launches without an attached console now return cleanly instead of showing an AutoHotkey invalid-handle dialog.
