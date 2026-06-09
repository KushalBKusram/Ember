import SwiftUI

struct JobEditorView: View {
    let agentId:  UUID
    let existing: AgentJob?

    @Environment(\.dismiss) private var dismiss

    // Common
    @State private var name   = ""
    @State private var prompt = ""

    // Schedule type
    @State private var scheduleType: ScheduleType = .atTime

    // Time-based fields
    @State private var time = Self.defaultTime
    @State private var days: Set<Int> = []   // empty = every day

    // Interval-based field
    @State private var intervalMinutes: Int = 60

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
                // ── Name ──────────────────────────────────────────────────
                Section {
                    TextField("e.g. Morning Digest", text: $name)
                } header: { Text("Job Name") }

                // ── Prompt ────────────────────────────────────────────────
                Section {
                    TextField(
                        "e.g. Give me a morning finance digest including portfolio moves and relevant news.",
                        text: $prompt,
                        axis: .vertical
                    )
                    .lineLimit(4...8)
                } header: { Text("Prompt") }
                  footer: { Text("This message is auto-sent to the agent when the job fires.") }

                // ── Schedule type ─────────────────────────────────────────
                Section {
                    Picker("Type", selection: $scheduleType) {
                        ForEach(ScheduleType.allCases) { type in
                            Text(type.label).tag(type)
                        }
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                } header: { Text("Schedule") }

                // ── Time-based options ────────────────────────────────────
                if scheduleType == .atTime {
                    Section {
                        DatePicker("Time", selection: $time, displayedComponents: .hourAndMinute)
                    }
                    Section {
                        WeekdaySelectorView(selected: $days)
                    } footer: {
                        Text(days.isEmpty ? "Runs every day." : "Runs on selected days only.")
                    }
                }

                // ── Interval-based options ────────────────────────────────
                if scheduleType == .onInterval {
                    Section {
                        Picker("Repeat every", selection: $intervalMinutes) {
                            ForEach(Self.intervalOptions, id: \.minutes) { option in
                                Text(option.label).tag(option.minutes)
                            }
                        }
                        .pickerStyle(.wheel)
                        .frame(height: 140)
                    } footer: {
                        Text("A notification fires on this interval. Tap it to run the agent.")
                    }
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

    // MARK: - Interval options

    private static let intervalOptions: [IntervalOption] = [
        .init(minutes: 15,   label: "15 minutes"),
        .init(minutes: 30,   label: "30 minutes"),
        .init(minutes: 60,   label: "1 hour"),
        .init(minutes: 120,  label: "2 hours"),
        .init(minutes: 240,  label: "4 hours"),
        .init(minutes: 360,  label: "6 hours"),
        .init(minutes: 720,  label: "12 hours"),
        .init(minutes: 1440, label: "24 hours"),
    ]

    private struct IntervalOption {
        let minutes: Int
        let label: String
    }

    // MARK: - Schedule type

    enum ScheduleType: String, CaseIterable, Identifiable {
        case atTime     = "atTime"
        case onInterval = "onInterval"

        var id: String { rawValue }

        var label: String {
            switch self {
            case .atTime:     return "At a Time"
            case .onInterval: return "On an Interval"
            }
        }
    }

    // MARK: - Helpers

    private func populate() {
        guard let job = existing else { return }
        name   = job.name
        prompt = job.prompt

        if let mins = job.intervalMinutes {
            scheduleType    = .onInterval
            intervalMinutes = mins
        } else {
            scheduleType = .atTime
            days         = job.scheduleDays
            var target    = DateComponents()
            target.hour   = job.scheduleHour
            target.minute = job.scheduleMinute
            time = Calendar.current.date(from: target) ?? time
        }
    }

    private func save() {
        let trimmedName   = name.trimmingCharacters(in: .whitespaces)
        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespaces)

        if var job = existing {
            job.name   = trimmedName
            job.prompt = trimmedPrompt
            if scheduleType == .onInterval {
                job.intervalMinutes = intervalMinutes
                job.scheduleHour    = 9   // unused but keep valid
                job.scheduleMinute  = 0
                job.scheduleDaysRaw = ""
            } else {
                let comps           = Calendar.current.dateComponents([.hour, .minute], from: time)
                job.scheduleHour    = comps.hour   ?? 9
                job.scheduleMinute  = comps.minute ?? 0
                job.scheduleDaysRaw = AgentJob.makeDaysRaw(days)
                job.intervalMinutes = nil
            }
            Task {
                try? await service.saveJob(&job)
                await MainActor.run { dismiss() }
            }
        } else {
            let job: AgentJob
            if scheduleType == .onInterval {
                job = AgentJob.makeInterval(
                    agentId: agentId,
                    name: trimmedName,
                    prompt: trimmedPrompt,
                    intervalMinutes: intervalMinutes
                )
            } else {
                let comps = Calendar.current.dateComponents([.hour, .minute], from: time)
                job = AgentJob.make(
                    agentId: agentId,
                    name: trimmedName,
                    prompt: trimmedPrompt,
                    hour: comps.hour   ?? 9,
                    minute: comps.minute ?? 0,
                    days: days
                )
            }
            var mutableJob = job
            Task {
                try? await service.saveJob(&mutableJob)
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
