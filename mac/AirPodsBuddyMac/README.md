# AirPodsBuddyMac

Menu-bar host for macOS 13+. Run `swift test` and `swift build -c release` on a Mac with Xcode Command Line Tools. The Windows workspace cannot compile this target.

The selected Bluetooth headset is stored by its hardware address (`targetDeviceAddress`), not its display name. A legacy name preference migrates only when exactly one paired audio-class device has that name. CoreAudio routing requires a Bluetooth output whose UID embeds the selected address. A display-name match alone fails closed; hardware validation must establish whether the target macOS exposes a suitable UID.

IOBluetooth and CoreAudio calls run on a serial worker. The menu icon reflects sampled connection state, not watchdog intent. Explicit connect or device selection performs one connection transaction and arms the watchdog only when the preference is enabled. A second click during a pending transaction requests disconnection and invalidates callbacks. The watchdog attempts reconnect with 2 s and 4 s spacing, then cools down for 60 s; user disconnection cancels the current generation.

Mac acceptance still requires physical hardware: connect/disconnect, target switch between two paired headsets, same-name ambiguity, iPhone handoff, output drift, five reconnect cycles, and user-audible playback. A build or unit-test pass is not physical acceptance.
