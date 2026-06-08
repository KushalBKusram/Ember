import SwiftUI
import AVFoundation
import Speech
import EventKit

// MARK: - Root

struct OnboardingView: View {
    @State private var page = 0

    var body: some View {
        ZStack(alignment: .topLeading) {
            ZStack {
                if page == 0 {
                    WelcomePage { advance() }
                        .transition(forwardTransition)
                }
                if page == 1 {
                    PermissionsPage { advance() }
                        .transition(forwardTransition)
                }
                if page == 2 {
                    FaceIDPage { advance() }
                        .transition(forwardTransition)
                }
                if page == 3 {
                    IdentityPage()
                        .transition(forwardTransition)
                }
            }
            .animation(.easeInOut(duration: 0.35), value: page)

            if page > 0 {
                Button {
                    Haptics.tap()
                    page -= 1
                } label: {
                    Image(systemName: "chevron.backward")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                        .frame(width: 36, height: 36)
                        .glassEffect(in: Circle())
                }
                .padding(.leading, 20)
                .padding(.top, 8)
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: page > 0)
    }

    private func advance() {
        Haptics.tap()
        page += 1
    }

    private var forwardTransition: AnyTransition {
        .asymmetric(
            insertion: .move(edge: .trailing).combined(with: .opacity),
            removal:   .move(edge: .leading).combined(with: .opacity)
        )
    }
}

// MARK: - Page 1 · Welcome

private struct WelcomePage: View {
    let onNext: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            Image(systemName: "flame.fill")
                .font(.system(size: 72))
                .foregroundStyle(.orange)
                .padding(.bottom, 20)

            Text("Ember")
                .font(.system(size: 48, weight: .bold, design: .rounded))
                .padding(.bottom, 8)

            Text("Private AI that learns about you.")
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Spacer().frame(height: 56)

            VStack(alignment: .leading, spacing: 24) {
                featureRow(icon: "cpu",
                           color: .orange,
                           title: "Runs entirely on-device",
                           subtitle: "Your data never leaves your iPhone.")
                featureRow(icon: "brain.head.profile",
                           color: .purple,
                           title: "Learns from conversations",
                           subtitle: "Builds a personal profile that improves over time.")
                featureRow(icon: "lock.shield.fill",
                           color: .green,
                           title: "Completely private",
                           subtitle: "No cloud, no analytics, no tracking.")
            }
            .padding(.horizontal, 36)

            Spacer()

            Button("Get Started", action: onNext)
                .buttonStyle(PrimaryButtonStyle())
                .padding(.horizontal, 32)
                .padding(.bottom, 52)
        }
    }

    private func featureRow(icon: String, color: Color, title: String, subtitle: String) -> some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(color)
                .frame(width: 36)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.subheadline).fontWeight(.semibold)
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
    }
}

// MARK: - Page 2 · Permissions

private struct PermissionsPage: View {
    let onNext: () -> Void
    @State private var isRequesting = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            Text("Supercharge Ember")
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .padding(.bottom, 8)

            Text("Grant access so Ember can answer questions using your personal data.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
                .padding(.bottom, 48)

            VStack(alignment: .leading, spacing: 28) {
                permissionRow(icon: "mic.fill",      color: .purple, title: "Microphone & Speech",
                              benefit: "Talk to Ember using your voice")
                permissionRow(icon: "calendar",      color: .red,    title: "Calendar",
                              benefit: "Know what's on your schedule")
                permissionRow(icon: "checklist",     color: .blue,   title: "Reminders",
                              benefit: "Help you manage your tasks")
            }
            .padding(.horizontal, 36)

            Spacer()

            VStack(spacing: 14) {
                Button {
                    requestAll()
                } label: {
                    if isRequesting {
                        ProgressView().tint(.white)
                    } else {
                        Text("Allow Access")
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(isRequesting)
                .padding(.horizontal, 32)

                Button("Continue without permissions", action: onNext)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.bottom, 52)
        }
    }

    private func permissionRow(icon: String, color: Color, title: String, benefit: String) -> some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(color)
                .frame(width: 36)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.subheadline).fontWeight(.semibold)
                Text(benefit).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private func requestAll() {
        isRequesting = true
        Task {
            await requestSystemPermissions()
            isRequesting = false
            onNext()
        }
    }
}

// MARK: - Permission helper
//
// Defined at file scope so it is `nonisolated` — Swift schedules it on the
// cooperative thread pool rather than the main actor. This avoids the
// `unsafeForcedSync` trap that fires when EventKit's async API internally
// calls `dispatch_sync` from a pool thread. We use the callback-based
// `requestAccess(to:)` instead of the `async throws` variants for the
// same reason: callback EventKit uses plain GCD, which has no such restriction.

private func requestSystemPermissions() async {
    // Microphone
    _ = await AVAudioApplication.requestRecordPermission()

    // Speech recognition
    await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
        SFSpeechRecognizer.requestAuthorization { _ in cont.resume() }
    }

    // Calendar — callback form sidesteps unsafeForcedSync in EventKit async.
    // If the user grants access, enable the toggle so RAGService fetches events.
    await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
        let store = EKEventStore()
        store.requestAccess(to: .event) { granted, _ in
            if granted { AppSettings.calendarEnabled = true }
            cont.resume()
        }
    }

    // Reminders — same
    await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
        let store = EKEventStore()
        store.requestAccess(to: .reminder) { granted, _ in
            if granted { AppSettings.remindersEnabled = true }
            cont.resume()
        }
    }
}

// MARK: - Page 3 · Face ID

private struct FaceIDPage: View {
    let onNext: () -> Void
    @State private var faceIDEnabled = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            Image(systemName: "faceid")
                .font(.system(size: 72))
                .foregroundStyle(.green)
                .padding(.bottom, 24)

            Text("Protect Your Chats")
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .padding(.bottom, 8)

            Text("Lock Ember with Face ID whenever you leave the app.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Spacer().frame(height: 56)

            Toggle(isOn: $faceIDEnabled) {
                Label("Enable Face ID Lock", systemImage: "lock.shield.fill")
                    .font(.subheadline)
                    .fontWeight(.medium)
            }
            .padding(.horizontal, 32)

            Spacer()

            Button("Continue") {
                AppSettings.appLockEnabled = faceIDEnabled
                onNext()
            }
            .buttonStyle(PrimaryButtonStyle())
            .padding(.horizontal, 32)
            .padding(.bottom, 52)
        }
    }
}

// MARK: - Page 4 · Identity (SOUL)

private struct IdentityPage: View {
    @State private var identityText = ""
    @FocusState private var isFocused: Bool

    private let placeholder = """
        Tell Ember who you are — your name, what you do, your interests, \
        goals, or anything that matters to you. This becomes your personal \
        context from day one.
        """

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                VStack(spacing: 8) {
                    Image(systemName: "person.crop.circle.fill")
                        .font(.system(size: 56))
                        .foregroundStyle(.orange)
                        .padding(.top, 52)
                        .padding(.bottom, 8)

                    Text("Tell Ember About You")
                        .font(.system(size: 28, weight: .bold, design: .rounded))

                    Text("The more you share, the better Ember knows you from day one.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 36)
                }
                .padding(.bottom, 24)

                ZStack(alignment: .topLeading) {
                    Color.clear
                        .glassEffect(in: RoundedRectangle(cornerRadius: 16))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .strokeBorder(isFocused ? Color.orange.opacity(0.5) : Color.clear, lineWidth: 1.5)
                        )

                    if identityText.isEmpty {
                        Text(placeholder)
                            .font(.body)
                            .foregroundStyle(Color(.tertiaryLabel))
                            .padding(16)
                            .allowsHitTesting(false)
                    }

                    TextEditor(text: $identityText)
                        .font(.body)
                        .focused($isFocused)
                        .padding(12)
                        .scrollContentBackground(.hidden)
                }
                .frame(minHeight: 180)
                .padding(.horizontal, 24)
                .onTapGesture { isFocused = true }

                VStack(spacing: 14) {
                    Button("Get Started") { complete() }
                        .buttonStyle(PrimaryButtonStyle())
                        .padding(.horizontal, 32)

                    Button("Skip") { completeEmpty() }
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 32)
                .padding(.bottom, 52)
            }
            .frame(minHeight: UIScreen.main.bounds.height * 0.7)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private func complete() {
        let text = identityText.trimmingCharacters(in: .whitespacesAndNewlines)
        AppSettings.userIdentity = text
        if !text.isEmpty {
            let captured = text
            AppSettings.isInitialisingProfile = true
            Haptics.success()
            Task.detached(priority: .background) {
                await MemoryService.shared.initializeFromIdentity(captured)
                await MainActor.run { AppSettings.isInitialisingProfile = false }
            }
        } else {
            Haptics.tap()
        }
        withAnimation(.easeInOut(duration: 0.4)) {
            AppSettings.hasCompletedOnboarding = true
        }
    }

    private func completeEmpty() {
        Haptics.tap()
        withAnimation(.easeInOut(duration: 0.4)) {
            AppSettings.hasCompletedOnboarding = true
        }
    }
}

// MARK: - Shared button style

private struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(configuration.isPressed ? Color.orange.opacity(0.75) : .orange)
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}
