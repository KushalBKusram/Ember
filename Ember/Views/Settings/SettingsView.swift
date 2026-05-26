import SwiftUI

struct SettingsView: View {
    @AppStorage("customSystemPrompt") private var customSystemPrompt = ""
    @AppStorage("responseStyle") private var responseStyle = ResponseStyle.balanced
    @AppStorage("memoryEnabled") private var memoryEnabled = true
    @State private var showingSystemPromptEditor = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Model") {
                    LabeledContent("Engine", value: "Apple Foundation Models")
                    LabeledContent("Processing", value: "On-device · Private")
                }

                Section("Response Style") {
                    Picker("Style", selection: $responseStyle) {
                        ForEach(ResponseStyle.allCases) { style in
                            Text(style.label).tag(style)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section {
                    Button("Edit System Prompt") {
                        showingSystemPromptEditor = true
                    }
                    if !customSystemPrompt.isEmpty {
                        Text(customSystemPrompt)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                } header: {
                    Text("Personality")
                } footer: {
                    Text("Custom instructions added to every conversation.")
                }

                Section {
                    Toggle(isOn: $memoryEnabled) {
                        Label("Memory Learning", systemImage: "brain.head.profile")
                    }
                } header: {
                    Text("Memory")
                } footer: {
                    Text("When enabled, Ember learns facts about you from conversations and uses them to personalise future responses. All memory stays on-device.")
                }

                Section {
                    NavigationLink {
                        DataSourcesView()
                    } label: {
                        Label("Knowledge Sources", systemImage: "doc.text.magnifyingglass")
                    }
                } header: {
                    Text("RAG")
                } footer: {
                    Text("Connect your calendar, reminders, and documents so Ember can answer questions using your personal data.")
                }

                Section("Privacy") {
                    LabeledContent("Cloud Sync", value: "Never")
                    LabeledContent("Analytics", value: "None")
                    LabeledContent("Data Location", value: "This iPhone only")
                }

                Section("About") {
                    LabeledContent("Version", value: "1.0.0 (Milestone 1)")
                    Link("Source & License", destination: URL(string: "https://github.com")!)
                }
            }
            .navigationTitle("Settings")
            .sheet(isPresented: $showingSystemPromptEditor) {
                SystemPromptEditorView(prompt: $customSystemPrompt)
            }
        }
    }
}

// MARK: - Response Style

enum ResponseStyle: String, CaseIterable, Identifiable {
    case concise, balanced, detailed

    var id: String { rawValue }
    var label: String { rawValue.capitalized }
}

// MARK: - System Prompt Editor

struct SystemPromptEditorView: View {
    @Binding var prompt: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            TextEditor(text: $prompt)
                .padding()
                .navigationTitle("System Prompt")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Clear") { prompt = "" }
                    }
                }
        }
        .presentationDetents([.medium, .large])
        .presentationBackground(.regularMaterial)
    }
}
