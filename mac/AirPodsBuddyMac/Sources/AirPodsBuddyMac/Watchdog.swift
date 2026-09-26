import Foundation

struct PairedAudioTarget {
    let address: String
    let name: String
}

enum RetryPolicy {
    static func delay(afterAttempt attempt: Int) -> TimeInterval {
        attempt >= 3 ? 60 : pow(2, Double(attempt))
    }
}

// Mutable state is main-thread confined. IOBluetooth/CoreAudio are confined to
// one serial worker; a timer never waits on openConnection's 8-second deadline.
final class Watchdog {
    static let shared = Watchdog()
    private let worker = DispatchQueue(label: "AirPodsBuddyMac.device", qos: .userInitiated)
    private var timer: Timer?
    private var epoch = 0
    private var working = false
    private var retries = 0
    private var nextRetry = Date.distantPast
    private var routeFailures = 0
    private var nextRouteRetry = Date.distantPast
    private var initialRestorePending = true
    private(set) var armed = false
    private(set) var actualConnected = false
    private(set) var targetAddress: String
    private(set) var candidates: [PairedAudioTarget] = []
    var onStateChange: (() -> Void)?

    private init() {
        targetAddress = Preferences.targetDeviceAddress ?? ""
        startMonitor()
        refreshCandidates()
    }

    var targetName: String {
        candidates.first { $0.address.caseInsensitiveCompare(targetAddress) == .orderedSame }?.name
            ?? targetAddress
    }

    func refreshCandidates() {
        precondition(Thread.isMainThread)
        let oldName = Preferences.targetDeviceName
        worker.async { [weak self] in
            let targets = BluetoothService.sortedAudioCandidates().compactMap { device -> PairedAudioTarget? in
                guard let address = device.addressString else { return nil }
                return PairedAudioTarget(address: address, name: device.nameOrAddress ?? address)
            }
            DispatchQueue.main.async {
                guard let self else { return }
                self.candidates = targets
                if self.targetAddress.isEmpty {
                    if let oldName {
                        let matches = targets.filter { $0.name.caseInsensitiveCompare(oldName) == .orderedSame }
                        if matches.count == 1 { self.targetAddress = matches[0].address }
                        else if matches.count > 1 { Log.error("legacy target name ambiguous; select device again") }
                    } else {
                        self.targetAddress = targets.first?.address ?? ""
                    }
                    if !self.targetAddress.isEmpty { Preferences.targetDeviceAddress = self.targetAddress }
                }
                self.onStateChange?()
                self.tick()
            }
        }
    }

    private func startMonitor() {
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.tick() }
        tick()
    }

    func restorePreference() {
        precondition(Thread.isMainThread)
        tick()
    }

    func setWatchdogEnabled(_ enabled: Bool) {
        precondition(Thread.isMainThread)
        armed = enabled && actualConnected && !targetAddress.isEmpty
        retries = 0
        nextRetry = .distantPast
        routeFailures = 0
        nextRouteRetry = .distantPast
        onStateChange?()
        tick()
    }

    func connect(address: String, completion: @escaping (Bool) -> Void) {
        precondition(Thread.isMainThread)
        guard !address.isEmpty else { completion(false); return }
        let old = targetAddress
        let shouldDisconnectOld = old != address && actualConnected
        epoch += 1
        let request = epoch
        armed = false
        working = true
        targetAddress = address
        Preferences.targetDeviceAddress = address
        retries = 0
        nextRetry = .distantPast
        routeFailures = 0
        nextRouteRetry = .distantPast
        onStateChange?()
        worker.async { [weak self] in
            if shouldDisconnectOld && !BluetoothService.disconnect(address: old) {
                DispatchQueue.main.async {
                    guard let self, self.epoch == request else { return }
                    self.working = false
                    self.targetAddress = old
                    Preferences.targetDeviceAddress = old
                    self.onStateChange?()
                    completion(false)
                }
                return
            }
            let connected = BluetoothService.connect(address: address)
            let name = BluetoothService.device(address: address)?.nameOrAddress ?? ""
            let routed = connected && self?.route(address: address, name: name) == true
            DispatchQueue.main.async {
                guard let self, self.epoch == request else { return }
                self.working = false
                self.actualConnected = connected
                self.armed = connected && Preferences.watchdogEnabled
                self.onStateChange?()
                completion(connected && routed)
            }
        }
    }

    func disconnect(completion: @escaping (Bool) -> Void) {
        precondition(Thread.isMainThread)
        let address = targetAddress
        epoch += 1
        let request = epoch
        armed = false
        retries = 0
        nextRetry = .distantPast
        routeFailures = 0
        nextRouteRetry = .distantPast
        working = true
        onStateChange?()
        worker.async { [weak self] in
            let ok = BluetoothService.disconnect(address: address)
            let stillConnected = BluetoothService.isConnected(address: address)
            DispatchQueue.main.async {
                guard let self, self.epoch == request else { return }
                self.working = false
                self.actualConnected = stillConnected
                self.onStateChange?()
                completion(ok)
            }
        }
    }

    // Main-thread timer only dispatches. At most three attempts per burst,
    // exponential 2/4/8-second spacing, then a 60-second cooldown.
    func tick() {
        precondition(Thread.isMainThread)
        guard !working, !targetAddress.isEmpty else { return }
        let address = targetAddress
        let request = epoch
        working = true
        worker.async { [weak self] in
            let connected = BluetoothService.isConnected(address: address)
            DispatchQueue.main.async {
                guard let self, self.epoch == request else { return }
                self.actualConnected = connected
                if self.initialRestorePending {
                    self.initialRestorePending = false
                    self.armed = connected && Preferences.watchdogEnabled
                }
                self.onStateChange?()
                guard self.armed else { self.working = false; return }
                if connected {
                    self.retries = 0
                    self.nextRetry = .distantPast
                    guard Date() >= self.nextRouteRetry else {
                        self.working = false
                        return
                    }
                    self.worker.async { [weak self] in
                        let name = BluetoothService.device(address: address)?.nameOrAddress ?? ""
                        let routed = self?.route(address: address, name: name) == true
                        DispatchQueue.main.async {
                            guard let self, self.epoch == request else { return }
                            self.working = false
                            if routed {
                                self.routeFailures = 0
                                self.nextRouteRetry = .distantPast
                            } else {
                                self.routeFailures += 1
                                self.nextRouteRetry = Date().addingTimeInterval(
                                    RetryPolicy.delay(afterAttempt: self.routeFailures))
                                if self.routeFailures >= 3 { self.routeFailures = 0 }
                            }
                        }
                    }
                } else if Date() >= self.nextRetry {
                    self.retries += 1
                    let delay = RetryPolicy.delay(afterAttempt: self.retries)
                    self.nextRetry = Date().addingTimeInterval(delay)
                    if self.retries >= 3 { self.retries = 0 }
                    self.worker.async { [weak self] in
                        let ok = BluetoothService.connect(address: address)
                        if ok {
                            let name = BluetoothService.device(address: address)?.nameOrAddress ?? ""
                            _ = self?.route(address: address, name: name)
                        }
                        DispatchQueue.main.async {
                            guard let self, self.epoch == request else { return }
                            self.working = false
                            self.actualConnected = ok
                            self.onStateChange?()
                        }
                    }
                } else {
                    self.working = false
                }
            }
        }
    }

    private func route(address: String, name: String) -> Bool {
        guard let id = AudioRouter.findOutputDevice(address: address, name: name) else { return false }
        if AudioRouter.defaultOutputDeviceID() == id { return true }
        let ok = AudioRouter.setDefaultOutputDevice(id)
        if ok { Log.info("output locked to address \(address)") }
        return ok
    }
}
