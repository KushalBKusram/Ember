import SwiftUI
import UniformTypeIdentifiers

struct DataSourcesView: View {
    @State private var viewModel = DataSourcesViewModel()
    @State private var showFilePicker = false
    @State private var editingNote: NoteEdit?
    @AppStorage("calendarEnabled") private var calendarEnabled = false
    @AppStorage("remindersEnabled") private var remindersEnabled = false

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $calendarEnabled) {
                    Label("Calendar", systemImage: "calendar")
                }
                .onChange(of: calendarEnabled) { _, newValue in
                    if newValue { viewModel.requestCalendarAccess() }
                }
                Toggle(isOn: $remindersEnabled) {
                    Label("Reminders", systemImage: "checklist")
                }
                .onChange(of: remindersEnabled) { _, newValue in
                    if newValue { viewModel.requestRemindersAccess() }
                }
            } header: {
                Text("Live Sources")
            } footer: {
                Text("Ember reads your calendar and reminders at query time — no data is stored.")
            }

            Section {
                if viewModel.documents.isEmpty && !viewModel.isIndexing {
                    Text("No documents yet. Add a note or import a file from the + menu.")
                        .foregroundStyle(.secondary)
                }

                if viewModel.isIndexing {
                    HStack {
                        ProgressView()
                            .controlSize(.small)
                        Text("Indexing \"\(viewModel.indexingTitle)\"…")
                            .foregroundStyle(.secondary)
                    }
                }

                ForEach(viewModel.documents) { doc in
                    HStack {
                        Label(doc.title, systemImage: doc.source.icon)
                            .foregroundStyle(doc.isEnabled ? .primary : .secondary)
                        Spacer()
                        Text(doc.chunkCount == 1 ? "1 chunk" : "\(doc.chunkCount) chunks")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if doc.source == .note { openNote(doc) }
                    }
                    .swipeActions(edge: .leading, allowsFullSwipe: false) {
                        Button {
                            viewModel.toggleDocument(doc)
                        } label: {
                            Label(
                                doc.isEnabled ? "Disable" : "Enable",
                                systemImage: doc.isEnabled ? "pause.circle" : "play.circle"
                            )
                        }
                        .tint(doc.isEnabled ? .orange : .green)
                    }
                }
                .onDelete { viewModel.deleteDocuments(at: $0) }

            } header: {
                Text("Documents")
            } footer: {
                Text("PDFs and text files are chunked and embedded on-device. Notes you write here are stored privately and indexed the same way.")
            }
        }
        .navigationTitle("Knowledge Sources")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button {
                        editingNote = NoteEdit()
                    } label: {
                        Label("New Note", systemImage: "note.text")
                    }
                    Button {
                        showFilePicker = true
                    } label: {
                        Label("Import File", systemImage: "doc")
                    }
                } label: {
                    Image(systemName: "plus")
                }
                .disabled(viewModel.isIndexing)
            }
        }
        .fileImporter(
            isPresented: $showFilePicker,
            allowedContentTypes: [.pdf, .plainText, .text],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    viewModel.importFile(at: url)
                }
            case .failure(let error):
                viewModel.error = error.localizedDescription
            }
        }
        .sheet(item: $editingNote) { note in
            noteEditor(note)
        }
        .alert(viewModel.error?.localizedCaseInsensitiveContains("denied") == true ? "Access Needed" : "Something Went Wrong",
               isPresented: .constant(viewModel.error != nil), actions: {
            if viewModel.error?.localizedCaseInsensitiveContains("denied") == true {
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                    viewModel.error = nil
                }
            }
            Button("OK", role: .cancel) { viewModel.error = nil }
        }, message: {
            Text(viewModel.error ?? "")
        })
        .onAppear { viewModel.startObserving() }
        .onDisappear { viewModel.stopObserving() }
    }

    // MARK: - Note editor

    @ViewBuilder
    private func noteEditor(_ note: NoteEdit) -> some View {
        NoteEditorView(initial: note) { title, body in
            viewModel.saveNote(title: title, body: body, replacing: note.existing)
            editingNote = nil
        } onCancel: {
            editingNote = nil
        }
    }

    private func openNote(_ doc: RAGDocument) {
        Task {
            let body = await viewModel.loadNoteBody(for: doc)
            editingNote = NoteEdit(existing: doc, title: doc.title, body: body)
        }
    }
}

// MARK: - Note edit model

struct NoteEdit: Identifiable {
    let id = UUID()
    var existing: RAGDocument?
    var title: String = ""
    var body: String = ""
}

// MARK: - Editor view

private struct NoteEditorView: View {
    let initial: NoteEdit
    let onSave: (String, String) -> Void
    let onCancel: () -> Void

    @State private var title: String
    @State private var bodyText: String
    @FocusState private var bodyFocused: Bool

    init(initial: NoteEdit, onSave: @escaping (String, String) -> Void, onCancel: @escaping () -> Void) {
        self.initial = initial
        self.onSave = onSave
        self.onCancel = onCancel
        _title = State(initialValue: initial.title)
        _bodyText = State(initialValue: initial.body)
    }

    var canSave: Bool {
        !bodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Title", text: $title)
                }
                Section {
                    TextEditor(text: $bodyText)
                        .frame(minHeight: 240)
                        .focused($bodyFocused)
                } header: {
                    Text("Body")
                } footer: {
                    Text("This note is indexed for RAG and surfaced when relevant to a question.")
                }
            }
            .navigationTitle(initial.existing == nil ? "New Note" : "Edit Note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Haptics.success()
                        onSave(title, bodyText)
                    }
                    .disabled(!canSave)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
            }
            .onAppear {
                if initial.existing == nil { bodyFocused = true }
            }
        }
    }
}
