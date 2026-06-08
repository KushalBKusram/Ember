import Foundation

enum AppSettings {
    static var memoryEnabled: Bool {
        get { UserDefaults.standard.object(forKey: "memoryEnabled") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "memoryEnabled") }
    }

    static var calendarEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: "calendarEnabled") }
        set { UserDefaults.standard.set(newValue, forKey: "calendarEnabled") }
    }

    static var remindersEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: "remindersEnabled") }
        set { UserDefaults.standard.set(newValue, forKey: "remindersEnabled") }
    }

    static var userProfile: String {
        get { UserDefaults.standard.string(forKey: "userProfile") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "userProfile") }
    }

    static var appLockEnabled: Bool {
        get { UserDefaults.standard.object(forKey: "appLockEnabled") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "appLockEnabled") }
    }

    static var hasCompletedOnboarding: Bool {
        get { UserDefaults.standard.bool(forKey: "hasCompletedOnboarding") }
        set { UserDefaults.standard.set(newValue, forKey: "hasCompletedOnboarding") }
    }

    static var userIdentity: String {
        get { UserDefaults.standard.string(forKey: "userIdentity") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "userIdentity") }
    }

    /// True while the initial profile is being synthesised from the
    /// onboarding identity text. Surfaced as a toast in the first-run app.
    static var isInitialisingProfile: Bool {
        get { UserDefaults.standard.bool(forKey: "isInitialisingProfile") }
        set { UserDefaults.standard.set(newValue, forKey: "isInitialisingProfile") }
    }

    /// When true, Ember sends the user's query to DuckDuckGo to fetch
    /// web search snippets and injects them as context. Opt-in because it
    /// involves outbound network traffic. Default off.
    static var webSearchEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: "webSearchEnabled") }
        set { UserDefaults.standard.set(newValue, forKey: "webSearchEnabled") }
    }

    /// Marketing version of the most recent launch. Used by the upgrade
    /// hook to drive one-off migrations or "what's new" surfaces.
    static var lastSeenVersion: String {
        get { UserDefaults.standard.string(forKey: "lastSeenVersion") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "lastSeenVersion") }
    }
}

// MARK: - Current bundle version

extension AppSettings {
    static var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }
}
