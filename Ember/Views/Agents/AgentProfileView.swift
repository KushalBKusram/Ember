import SwiftUI

struct AgentProfileView: View {
    @State private var agent: Agent
    @State private var jobs: [AgentJob] = []
    @State private var showingJobEditor  = false
    @State private var editingJob: AgentJob? = nil
    @State private var isSaving = false

    // Editable fields
    @State private var name: String
    @State private var emoji: String
    @State private var description: String
    @State private var systemPrompt: String
    @State private var webSearch: Bool
    @State private var calendar: Bool
    @State private var memory: Bool
    @State private var rag: Bool

    private let service = AgentService.shared
    private let db      = AppDatabase.shared

    init(agent: Agent) {
        _agent       = State(initialValue: agent)
        _name        = State(initialValue: agent.name)
        _emoji       = State(initialValue: agent.emoji)
        _description = State(initialValue: agent.agentDescription)
        _systemPrompt = State(initialValue: agent.systemPrompt)
        _webSearch   = State(initialValue: agent.webSearchEnabled)
        _calendar    = State(initialValue: agent.calendarEnabled)
        _memory      = State(initialValue: agent.memoryEnabled)
        _rag         = State(initialValue: agent.ragEnabled)
    }

    var body: some View {
        Form {
            // Identity
            Section {
                HStack {
                    Text(emoji).font(.largeTitle)
                    TextField("Agent name", text: $name)
                        .font(.headline)
                }
                TextField("What does this agent focus on?", text: $description, axis: .vertical)
                    .lineLimit(2...4)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } header: { Text("Identity") }

            // System Prompt
            Section {
                TextEditor(text: $systemPrompt)
                    .font(.subheadline)
                    .frame(minHeight: 100)
            } header: { Text("System Prompt") }
              footer: { Text("Defines how the agent behaves. Auto-generated from the description — edit freely.") }

            // Data Sources
            Section {
                Toggle("Web Search", isOn: $webSearch)
                Toggle("Calendar", isOn: $calendar)
                Toggle("Memory", isOn: $memory)
                Toggle("Knowledge Sources", isOn: $rag)
            } header: { Text("Data Sources") }
              footer: { Text("Controls which context sources this agent can access, independent of global settings.") }

            // Jobs
            Section {
                ForEach(jobs) { job in
                    JobRowView(job: job) {
                        editingJob = job
                    } onToggle: {
                        Task {
                            try? await service.toggleJob(job)
                            loadJobs()
                        }
                    } onDelete: {
                        Task {
                            try? await service.deleteJob(job)
                            loadJobs()
                        }
                    }
                }
                Button {
                    editingJob    = nil
                    showingJobEditor = true
                } label: {
                    Label("Add Job", systemImage: "plus.circle")
                }
            } header: { Text("Jobs") }
              footer: { Text("Each job schedules a notification. Tapping it opens this agent and auto-runs the prompt.") }
        }
        .navigationTitle("Agent Settings")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { save() }
                    .disabled(isSaving || name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .sheet(isPresented: $showingJobEditor, onDismiss: loadJobs) {
            JobEditorView(agentId: agent.id, existing: nil)
        }
        .sheet(item: $editingJob, onDismiss: loadJobs) { job in
            JobEditorView(agentId: agent.id, existing: job)
        }
        .onAppear { loadJobs() }
    }

    // MARK: - Actions

    private func save() {
        isSaving = true
        var updated          = agent
        updated.name         = name.trimmingCharacters(in: .whitespaces)
        updated.emoji        = emoji
        updated.agentDescription = description.trimmingCharacters(in: .whitespaces)
        updated.systemPrompt = systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.webSearchEnabled = webSearch
        updated.calendarEnabled  = calendar
        updated.memoryEnabled    = memory
        updated.ragEnabled       = rag
        Task {
            try? await service.updateAgent(updated)
            agent    = updated
            isSaving = false
        }
    }

    private func loadJobs() {
        jobs = (try? db.jobs(for: agent.id)) ?? []
    }
}

// MARK: - Job row inside profile

private struct JobRowView: View {
    let job: AgentJob
    let onEdit: () -> Void
    let onToggle: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(job.name).font(.subheadline).fontWeight(.medium)
                Text(job.scheduleDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(job.prompt)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(2)
            }
            Spacer()
            Button(action: onToggle) {
                Image(systemName: job.isEnabled ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(job.isEnabled ? Color.accentColor : .secondary)
            }
            .buttonStyle(.plain)
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive, action: onDelete) {
                Label("Delete", systemImage: "trash")
            }
            Button(action: onEdit) {
                Label("Edit", systemImage: "pencil")
            }
            .tint(.blue)
        }
        .opacity(job.isEnabled ? 1 : 0.55)
    }
}
