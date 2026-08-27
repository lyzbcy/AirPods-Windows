# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.9.0] - 2026-08-27

### Added (adopted from the personal component library: 共享/tools/软件开发)
- **Update UX completion** (自适应更新检测 spec): proxy tip for CN users in the update dialog; failure path now shows a one-click "打开发布页" fallback button (new `openrelease` bridge).
- **Star-ask component** (不打扰用户的求好评 spec): after the 10th successful connect (and every 50 after), a gentle card asks for a GitHub star; dismissed = 15-day cooldown, tracked in `app_settings.ini` (`stardone`/`openrepo` bridges).


## [1.8.4] - 2026-08-25

### Fixed (WebView2 Runtime 缺失自愈——0x80070002 不再劝退新手)
- **根因**：WebView2 控件**不复用**用户已装的 Edge 浏览器（只认 WebView2 Runtime 或 Edge Beta/Dev/Canary 通道）。精简系统/服务器镜像/被"优化工具"清理过的机器上 Runtime 常缺失 → 启动即 0x80070002"找不到文件"报错退出。旧提示"请安装微软 Edge"是误导——装了也没用（2026-08-25 在一台装着 Edge 151 的机器上实证：Edge 在、Runtime 无、照样报错）。
- **自愈流程**：启动时用官方 API `GetAvailableCoreWebView2BrowserVersionString` 探测 → 缺失则询问并自动下载微软官方 Evergreen Bootstrapper（约 2MB）`/silent /install` 静默安装后自动继续 → 断网/用户拒绝/UAC 被拒时**降级直接借用本机 Edge 目录**当运行时（同一套内核）→ 全失败才弹手动指引（一键打开官方下载页，文案明确说"装 Edge 浏览器是没用的"）。宠物窗口（PetEnsure）同样吃到降级目录。
- **顺手排掉的隐形炸弹**：AHK v2 `DllCall` 输出参数必须传 VarRef（`"ptr*", &info`）；传值（`info := 0`）**不报错但指针永远不回填**——若未测试直接发布，探针会在**有**运行时的机器上误报缺失、每次开机弹修复窗（函数级测试实证：hr=0 成功但指针为空）。已记入 doc/05 C 节。

### Changed
- 构建工具链（便携 AutoHotkey v2 + Ahk2Exe，均在 `tools/`，gitignore）在本副本就位，Ahk2Exe 编译参数与 doc/02 §7 一致（`/silent /compress 0`）。

## [1.8.2] - 2026-08-19

### Fixed (pet popup, all four user reports; subagent with empirical verification)
- **Missing frames**: the spritesheet crop kept only column 0 (192px) of the 8-column atlas — every frame beyond the first rendered blank. Re-cropped full width (1536x1248) and corrected `background-size`; all 35 used frames verified non-empty per alpha count.
- **True transparency, no background**: the white came from the AHK Gui surface + the white card (WebView2 `DefaultBackgroundColor=0x00000000` actually works in HWND mode). White card removed; sprite now floats on the desktop like the original Codex pet, with a small dark translucent status bubble. Full-window magenta color-key was tested and rejected (DirectComposition bypasses LWA_COLORKEY).
- **Size halved**: window 300x420 -> 200x260 logical, sprite 192x208 -> 120x130.
- Latent bug: `/testpet` ran before pet globals were initialized (UnsetError swallowed by OnError broke the ready handshake) — guarded with IsSet().

## [1.8.3] - 2026-08-24

### Changed
- **Repository renamed**: `BluetoothDeviceConnector` → `AirPods-Windows` (a name people can actually find). `UPDATE_API` / `RELEASE_PAGE` now point at the new repo directly instead of relying on GitHub redirects.
- All download/source links updated (README, landing `index.html`, product page `airpods-buddy.html`; download buttons now deep-link the zip asset).
- **First release since v1.1.2**: ships every fix from v1.2.0–v1.8.2. Most importantly for existing users, this kills the boot-time error dialog — *"This value of type String has no property named Result"* roughly 3.5 s after every launch — caused by the leftover `[vp2]` diagnostic probe in v1.1.2 (removed in v1.2.0). Existing installs auto-update; the popup never meant the app was broken.

## [1.8.1] - 2026-08-19

### Fixed
- **Tray left-click dead (finally, evidence-based)**: `A_TrayMenu.Click := 1` is v1 syntax; v2's property is `ClickCount`. Assigning the wrong name silently creates a plain property (no error), leaving the real threshold at double-click. A/B-verified via UIA-simulated real clicks (subagent). One-line fix.
- **noise_mode.ps1 rewritten** (subagent): byte-reversed MAC from AHK normalized, 12-byte payload, AAP handshake packet before the command, two marshaling crashes fixed, PSM 0x1001 + SDP fallback chain, full step-by-step diagnostics to noise_debug.log.

### Known limitation (documented honestly)
- Native noise control is **blocked by Windows itself**: user-mode Winsock L2CAP is non-functional (even bind() fails with 10050; corroborated by MagicPods shipping a kernel driver for exactly this). The menu entry now explains this and points users to MagicPods instead of a misleading generic error.


## [1.8.0] - 2026-08-19

### Changed
- **Apple-style redesign by a clean-context subagent** (per user request): cream/yellow-white palette (#FBF9F4 base, honey #D4A967 accents), macOS-grade cards (16px radius, hairline border, restrained shadows), Big Sur capsule buttons, sage-green connected state; all cutesy decorations (polka dots, clouds, stars, sticker tilt) removed; long device names now truncate with ellipsis while tags stay in a fixed right column.

### Fixed
- **Connection state always read as disconnected (the big one)**: Windows fills the BLUETOOTH_DEVICE_INFO flag fields with bit values (connected reads 32, remembered 16, authenticated 8 — verified against live connected AirPods), but the code compared , so every check failed. Now any nonzero value counts as true. This also explains the seemingly-dead tray left-click: the action fired, but the icon (same detection), the pet popup (off-screen), and the UI all reported nothing — every feedback channel was broken at once.


## [1.7.1] - 2026-08-19

### Fixed
- **Pet popup flew off-screen on 150% DPI**: mixing physical pixels (A_ScreenWidth) with logical Gui.Show coordinates multiplied the offset by the scale factor, leaving only a corner visible. Positioning now uses a pure physical chain (SPI work area -> GetWindowRect -> SetWindowPos), verified fully visible 16px from the screen corner.


## [1.7.0] - 2026-08-19

### Added
- **Native noise-control switching (off / ANC / transparency / adaptive)**: tray right-click → "🎧 降噪/通透模式" now directly switches the mode via Apple's private L2CAP service (`74ec2172-…`, command `0x0D`), implemented from scratch with PowerShell + Winsock (`tools/noise_mode.ps1`, embedded into the exe). Protocol facts from the librepods reverse-engineering docs (credited in README). Falls back to a toast explaining why if the earbuds aren't connected or don't support it. `/testnoise` CLI mode for QA.
- Note: needs the earbuds connected over Bluetooth Classic; verified plumbing end-to-end except the final write (no connected buds on the dev machine at build time).


## [1.6.0] - 2026-08-19

### Fixed
- **Tray left-click dead**: the default menu item name (with full-width parens) failed to match and the swallowed error silently disabled single-click activation; now set via a shared variable with try/catch logging.
- **Pet popup rendered blank**: the pet WebView2 was created on a hidden window — the same IsVisible=false suspension bug as the original main-window white screen (pitfall C in doc/05, now bitten twice). `PetShow` now re-fills bounds and forces `IsVisible := true`; background transparency is verified via a readback log line.

### Added
- **Kawaii restyle** (user request): blush-pink candy design — cream→blush gradient with polka dots, drifting clouds and twinkling stars, sticker cards (white borders, slight tilt), candy orb button with rotating dashed ring and gloss, pink-tinted shadows, hand-drawn squiggle section title, sticker tags. All functionality unchanged.
- **Noise-control menu entry (experimental)**: tray right-click → "🎧 降噪/通透模式…". Windows cannot switch AirPods ANC natively (Apple AAP over BLE); the entry detects installed helpers (MagicPods-Windows / librepods-windows) and launches them, otherwise points to the recommended project.


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
