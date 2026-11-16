import SwiftUI
import OSLog

private let errorLog = Logger(subsystem: "com.kushal.ember", category: "user-errors")

/// Wording for a failed user action, shared so every screen reports failures the same way.
enum UserFacingError {
    /// The underlying error (often raw SQLite text) goes to the log, not the alert.
    static func message(_ action: String, _ error: Error) -> String {
        errorLog.error("Failed to \(action, privacy: .public): \(String(describing: error), privacy: .public)")
        return "Couldn't \(action). Please try again."
    }
}

extension View {
    /// Shows `message` in an alert and clears it on dismiss.
    func errorAlert(_ message: Binding<String?>, title: String = "Something Went Wrong") -> some View {
        alert(
            title,
            isPresented: Binding(
                get: { message.wrappedValue != nil },
                set: { if !$0 { message.wrappedValue = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(message.wrappedValue ?? "")
        }
    }
}
