import SwiftUI

struct JobEditorView: View {
    let agentId:  UUID
    let existing: AgentJob?

    @Environment(\.dismiss) private var dismiss

    @State private var name    = ""
    @State private var prompt  = ""
    @State private var time    = defaultTime
    @State private var days:   Set<Int> = []   // empty = every day

    private let service = AgentService.shared

    private static var defaultTime: Date {
        Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: Date()) ?? Date()
    }

    private var isEditing: Bool { existing != nil }

    var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty &&
        !prompt.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("e.g. Morning Digest", text: $name)
                } header: { Text("Job Name") }

                Section {
                    TextField(
                        "e.g. Give me a morning finance digest including portfolio moves and relevant news.",
                        text: $prompt,
                        axis: .vertical
                    )
                    .lineLimit(4...8)
                } header: { Text("Prompt") }
                  footer: { Text("This message is auto-sent to the agent when the job fires.") }

                Section {
                    DatePicker("Time", selection: $time, displayedComponents: .hourAndMinute)
                } header: { Text("Schedule") }

                Section {
                    WeekdaySelectorView(selected: $days)
                } footer: {
                    Text(days.isEmpty ? "Runs every day." : "Runs on selected days only.")
                }
            }
            .navigationTitle(isEditing ? "Edit Job" : "New Job")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isEditing ? "Update" : "Add") { save() }
                        .disabled(!canSave)
                }
            }
            .onAppear { populate() }
        }
    }

    // MARK: - Helpers

    private func populate() {
        guard let job = existing else { return }
        name   = job.name
        prompt = job.prompt
        days   = job.scheduleDays
        let comps     = Calendar.current.dateComponents([.hour, .minute], from: Date())
        var target    = DateComponents()
        target.hour   = job.scheduleHour
        target.minute = job.scheduleMinute
        time = Calendar.current.date(from: target) ?? time
        _ = comps // suppress warning
    }

    private func save() {
        let comps  = Calendar.current.dateComponents([.hour, .minute], from: time)
        let hour   = comps.hour   ?? 9
        let minute = comps.minute ?? 0

        if var job = existing {
            job.name           = name.trimmingCharacters(in: .whitespaces)
            job.prompt         = prompt.trimmingCharacters(in: .whitespaces)
            job.scheduleHour   = hour
            job.scheduleMinute = minute
            job.scheduleDaysRaw = AgentJob.makeDaysRaw(days)
            Task {
                try? await service.saveJob(&job)
                await MainActor.run { dismiss() }
            }
        } else {
            var job = AgentJob.make(
                agentId: agentId,
                name: name.trimmingCharacters(in: .whitespaces),
                prompt: prompt.trimmingCharacters(in: .whitespaces),
                hour: hour,
                minute: minute,
                days: days
            )
            Task {
                try? await service.saveJob(&job)
                await MainActor.run { dismiss() }
            }
        }
    }
}

// MARK: - Weekday selector

struct WeekdaySelectorView: View {
    @Binding var selected: Set<Int>

    private let days: [(Int, String)] = [
        (2, "M"), (3, "T"), (4, "W"), (5, "T"), (6, "F"), (7, "S"), (1, "S")
    ]

    var body: some View {
        HStack(spacing: 6) {
            Spacer()
            ForEach(days, id: \.0) { num, label in
                Button {
                    if selected.contains(num) { selected.remove(num) }
                    else { selected.insert(num) }
                } label: {
                    Text(label)
                        .font(.caption).fontWeight(.semibold)
                        .frame(width: 34, height: 34)
                        .background(
                            selected.contains(num)
                                ? Color.accentColor
                                : Color.secondary.opacity(0.15),
                            in: Circle()
                        )
                        .foregroundStyle(selected.contains(num) ? .white : .primary)
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(.vertical, 4)
    }
}
