import SwiftUI
import UniformTypeIdentifiers

struct DataSourcesView: View {
    @State private var viewModel = DataSourcesViewModel()
    @State private var showFilePicker = false
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
                    Text("No files imported yet.")
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
                        Spacer()
                        Text("\(doc.chunkCount) chunks")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                .onDelete { viewModel.deleteDocuments(at: $0) }

            } header: {
                Text("Imported Files")
            } footer: {
                Text("PDF, text, and markdown files are chunked and embedded on-device.")
            }
        }
        .navigationTitle("Knowledge Sources")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showFilePicker = true
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
        .alert("Error", isPresented: .constant(viewModel.error != nil), actions: {
            Button("OK") { viewModel.error = nil }
        }, message: {
            Text(viewModel.error ?? "")
        })
        .onAppear { viewModel.startObserving() }
        .onDisappear { viewModel.stopObserving() }
    }

}
