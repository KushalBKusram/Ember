import SwiftUI

struct SettingsView: View {
    @AppStorage("appLockEnabled")    private var appLockEnabled    = true
    @AppStorage("webSearchEnabled")  private var webSearchEnabled  = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Model") {
                    LabeledContent("Engine", value: "Apple Foundation Models")
                    LabeledContent("Processing", value: "On-device · Private")
                }

                Section {
                    NavigationLink {
                        MemoryView()
                    } label: {
                        Label("Memory", systemImage: "brain.head.profile")
                    }
                } header: {
                    Text("Memory")
                } footer: {
                    Text("Ember can learn facts about you from conversations to personalise responses. Tap to manage settings and see what's been learned.")
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

                Section {
                    Toggle(isOn: $webSearchEnabled) {
                        Label("Web Search", systemImage: "magnifyingglass.circle")
                    }
                } header: {
                    Text("Internet")
                } footer: {
                    Text("When enabled, Ember searches DuckDuckGo to answer questions about current events or general knowledge. Your query is sent to DuckDuckGo — disable to keep all activity fully on-device.")
                }

                Section {
                    Toggle(isOn: $appLockEnabled) {
                        Label("Face ID Lock", systemImage: "faceid")
                    }
                } header: {
                    Text("Security")
                } footer: {
                    Text("Lock Ember with Face ID whenever you leave the app.")
                }

                Section("Privacy") {
                    LabeledContent("Cloud Sync", value: "Never")
                    LabeledContent("Analytics", value: "None")
                    LabeledContent("Data Location", value: "This iPhone only")
                }

                Section("About") {
                    LabeledContent("Version", value: "\(AppSettings.currentVersion) (v1 candidate)")
                    Link("Source & License", destination: URL(string: "https://github.com/KushalBKusram/Ember")!)
                }
            }
            .navigationTitle("Settings")
        }
    }
}
