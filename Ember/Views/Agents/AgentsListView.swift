import SwiftUI

struct AgentsListView: View {
    @State private var viewModel   = AgentsViewModel()
    @State private var navPath     = NavigationPath()
    @State private var showCreate  = false

    private let navState = AgentNavigationState.shared

    var body: some View {
        NavigationStack(path: $navPath) {
            Group {
                if viewModel.agents.isEmpty {
                    emptyState
                } else {
                    agentList
                }
            }
            .navigationTitle("Agents")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showCreate = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .navigationDestination(for: Agent.self) { agent in
                AgentConversationView(agent: agent, triggerJobId: pendingJobId(for: agent))
                    .onAppear { clearPendingTrigger(for: agent) }
            }
            .sheet(isPresented: $showCreate) {
                CreateAgentView { newAgent in
                    navPath.append(newAgent)
                }
            }
        }
        .onAppear { viewModel.startObserving() }
        .onDisappear { viewModel.stopObserving() }
        .onChange(of: navState.pendingTrigger?.agentId) { handlePendingTrigger() }
    }

    // MARK: - Agent list

    private var agentList: some View {
        List {
            ForEach(viewModel.agents) { agent in
                NavigationLink(value: agent) {
                    AgentRowView(agent: agent)
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button(role: .destructive) {
                        viewModel.delete(agent)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    // MARK: - Empty state

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Agents Yet", systemImage: "sparkles")
        } description: {
            Text("Create an agent to get specialised assistance and schedule daily briefings.")
        } actions: {
            Button("Create Agent") { showCreate = true }
                .buttonStyle(.borderedProminent)
        }
    }

    // MARK: - Notification routing

    private func handlePendingTrigger() {
        guard let trigger = navState.pendingTrigger,
              let agent = viewModel.agents.first(where: { $0.id == trigger.agentId }) else { return }
        // Navigate to the agent's conversation — the job trigger is passed via pendingJobId.
        navPath.removeLast(navPath.count)
        navPath.append(agent)
    }

    private func pendingJobId(for agent: Agent) -> UUID? {
        navState.pendingTrigger?.agentId == agent.id
            ? navState.pendingTrigger?.jobId
            : nil
    }

    private func clearPendingTrigger(for agent: Agent) {
        if navState.pendingTrigger?.agentId == agent.id {
            navState.pendingTrigger = nil
        }
    }
}
