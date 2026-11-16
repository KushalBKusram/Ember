import SwiftUI

private let emojiOptions = ["💼", "🔬", "📚", "🏋️", "✈️", "🍳", "📰", "🎯",
                            "💡", "🎵", "💊", "🌍", "📈", "🧠", "⚡️", "🛠️"]

struct CreateAgentView: View {
    var onCreate: (Agent) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var name        = ""
    @State private var emoji       = "💡"
    @State private var description = ""
    @State private var isCreating  = false
    @State private var error: String?

    private let service = AgentService.shared

    var canCreate: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty &&
        !description.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                // Emoji picker
                Section {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 8), spacing: 10) {
                        ForEach(emojiOptions, id: \.self) { e in
                            Text(e)
                                .font(.title2)
                                .frame(width: 40, height: 40)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(emoji == e ? Color.accentColor.opacity(0.2) : Color.clear)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .strokeBorder(emoji == e ? Color.accentColor : Color.clear, lineWidth: 2)
                                )
                                .onTapGesture { emoji = e }
                        }
                    }
                    .padding(.vertical, 4)
                } header: { Text("Icon") }

                Section {
                    TextField("e.g. Finance Agent", text: $name)
                } header: { Text("Name") }

                Section {
                    TextField(
                        "e.g. Tracks my portfolio, market news, and financial goals",
                        text: $description,
                        axis: .vertical
                    )
                    .lineLimit(3...5)
                } header: { Text("What does this agent focus on?") }
                  footer: { Text("Ember uses this to generate the agent's system prompt. You can refine it later.") }
            }
            .errorAlert($error)
            .navigationTitle("New Agent")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        create()
                    }
                    .disabled(!canCreate || isCreating)
                }
            }
        }
    }

    private func create() {
        isCreating = true
        var agent = Agent.make(
            name: name.trimmingCharacters(in: .whitespaces),
            emoji: emoji,
            description: description.trimmingCharacters(in: .whitespaces)
        )
        Task {
            do {
                try await service.createAgent(&agent)
                await MainActor.run {
                    dismiss()
                    onCreate(agent)
                }
            } catch {
                await MainActor.run {
                    isCreating = false
                    self.error = UserFacingError.message("create the agent", error)
                }
            }
        }
    }
}
