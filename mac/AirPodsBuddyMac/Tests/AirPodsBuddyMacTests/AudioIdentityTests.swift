import XCTest
import CoreAudio
@testable import AirPodsBuddyMac

final class AudioIdentityTests: XCTestCase {
    private let bluetooth = kAudioDeviceTransportTypeBluetooth
    private let builtIn = kAudioDeviceTransportTypeBuiltIn

    func testAddressWinsOverSameName() {
        let rows = [
            AudioOutputCandidate(id: 1, uid: "AA-BB-CC-DD-EE-FF:output", name: "AirPods", transport: bluetooth),
            AudioOutputCandidate(id: 2, uid: "11-22-33-44-55-66:output", name: "AirPods", transport: bluetooth),
        ]
        XCTAssertEqual(AudioRouter.chooseOutput(rows, address: "11:22:33:44:55:66", name: "AirPods"), 2)
    }

    func testAmbiguousNameFailsClosed() {
        let rows = [
            AudioOutputCandidate(id: 1, uid: "opaque-1", name: "AirPods", transport: bluetooth),
            AudioOutputCandidate(id: 2, uid: "opaque-2", name: "AirPods", transport: bluetooth),
        ]
        XCTAssertNil(AudioRouter.chooseOutput(rows, address: "AA:BB:CC:DD:EE:FF", name: "AirPods"))
    }

    func testSingleNameWithoutAddressStillFailsClosed() {
        let rows = [AudioOutputCandidate(id: 1, uid: "opaque",
            name: "AirPods", transport: bluetooth)]
        XCTAssertNil(AudioRouter.chooseOutput(rows, address: "AA:BB:CC:DD:EE:FF", name: "AirPods"))
    }

    func testNonBluetoothAndFuzzyNameRejected() {
        let rows = [
            AudioOutputCandidate(id: 1, uid: "opaque", name: "AirPods Pro", transport: builtIn),
            AudioOutputCandidate(id: 2, uid: "opaque2", name: "Other AirPods", transport: bluetooth),
        ]
        XCTAssertNil(AudioRouter.chooseOutput(rows, address: "AA:BB:CC:DD:EE:FF", name: "AirPods Pro"))
    }

    func testBoundedBackoff() {
        XCTAssertEqual(RetryPolicy.delay(afterAttempt: 1), 2)
        XCTAssertEqual(RetryPolicy.delay(afterAttempt: 2), 4)
        XCTAssertEqual(RetryPolicy.delay(afterAttempt: 3), 60)
    }
}
