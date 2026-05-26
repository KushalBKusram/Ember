import Foundation

enum AppSettings {
    static var memoryEnabled: Bool {
        get { UserDefaults.standard.object(forKey: "memoryEnabled") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "memoryEnabled") }
    }

    static var customSystemPrompt: String {
        get { UserDefaults.standard.string(forKey: "customSystemPrompt") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "customSystemPrompt") }
    }
}
