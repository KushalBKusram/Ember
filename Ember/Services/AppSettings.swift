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

    static var calendarEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: "calendarEnabled") }
        set { UserDefaults.standard.set(newValue, forKey: "calendarEnabled") }
    }

    static var remindersEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: "remindersEnabled") }
        set { UserDefaults.standard.set(newValue, forKey: "remindersEnabled") }
    }
}
