import Testing
import Foundation
@testable import Ember

@Suite("Device capability gating")
struct DeviceCapabilityTests {

    @Test("Machine identifier is non-empty")
    func machineIdentifierIsPopulated() {
        let id = DeviceCapability.machineIdentifier
        #expect(!id.isEmpty)
    }

    @Test("Simulator and modern hardware both pass the gate")
    func meetsMinimumSpec() {
        // On simulator the gate is forced true. On a real A17 Pro+ device
        // running the test, the prefix list should match. Either way, the
        // app should not refuse to launch under the test runner.
        #expect(DeviceCapability.meetsMinimumSpec)
    }
}
