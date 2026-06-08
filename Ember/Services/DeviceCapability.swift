import Foundation

enum DeviceCapability {
    /// True iff this device meets the PRD's hard minimum (A17 Pro / iPhone 15 Pro).
    /// We detect via the kernel machine identifier — Apple Intelligence requires
    /// at least 8GB RAM and the Neural Engine on A17 Pro+, and these strings are
    /// stable per device model.
    static var meetsMinimumSpec: Bool {
        #if targetEnvironment(simulator)
        // Allow simulator for development. Real-device gating is what matters.
        return true
        #else
        return Self.isSupportedModel(machineIdentifier)
        #endif
    }

    /// Raw `hw.machine` identifier, e.g. "iPhone16,1".
    static var machineIdentifier: String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let mirror = Mirror(reflecting: systemInfo.machine)
        let id = mirror.children.reduce(into: "") { result, element in
            if let value = element.value as? Int8, value != 0 {
                result.append(Character(UnicodeScalar(UInt8(value))))
            }
        }
        return id
    }

    // MARK: - Supported list
    //
    // A17 Pro+ devices, which are required for Apple Foundation Models
    // and Apple Intelligence in iOS 26. Anything below this is silently
    // not supported (PRD: "gracefully disabled, not supported").
    //
    // Reference (Apple machine identifiers):
    //   iPhone 15 Pro       — iPhone16,1   (A17 Pro)
    //   iPhone 15 Pro Max   — iPhone16,2   (A17 Pro)
    //   iPhone 16 / Plus    — iPhone17,3 / iPhone17,4   (A18)
    //   iPhone 16 Pro       — iPhone17,1   (A18 Pro)
    //   iPhone 16 Pro Max   — iPhone17,2   (A18 Pro)
    //   iPhone 17 family    — iPhone18,*   (forward-compat, A19+)
    private static let supportedPrefixes: [String] = [
        "iPhone16,1", "iPhone16,2",                 // 15 Pro / Pro Max
        "iPhone17,1", "iPhone17,2",                 // 16 Pro / Pro Max
        "iPhone17,3", "iPhone17,4",                 // 16 / Plus (A18)
        "iPhone18,", "iPhone19,", "iPhone20,",      // forward-compat
    ]

    private static func isSupportedModel(_ id: String) -> Bool {
        supportedPrefixes.contains { id.hasPrefix($0) }
    }
}
