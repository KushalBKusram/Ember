import SwiftUI

struct AgentsListView: View {
    @State private var viewModel   = AgentsViewModel()
    @State private var navPath     = NavigationPath()
    @State private var showCreate  = false

    /// Job consumed from `AgentNavigationState.pendingTrigger`, held until the
    /// pushed conversation view picks it up via its `triggerJobId` init param.
    @State private var routedJob: (agentId: UUID, jobId: UUID)?

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
                AgentConversationView(agent: agent, triggerJobId: routedJobId(for: agent))
                    .onAppear { clearRoutedJob(for: agent) }
            }
            .sheet(isPresented: $showCreate) {
                CreateAgentView { newAgent in
                    navPath.append(newAgent)
                }
            }
        }
        .onAppear {
            viewModel.startObserving()
            routePendingNavigation()
        }
        .onDisappear { viewModel.stopObserving() }
        // Three hooks cover every arrival order: the notification tap can land
        // before this view exists (cold start), before the agents have loaded,
        // or while the view is already on screen.
        .onChange(of: navState.pendingTrigger?.agentId) { routePendingNavigation() }
        .onChange(of: navState.pendingOpen) { routePendingNavigation() }
        .onChange(of: viewModel.agents) { routePendingNavigation() }
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

    private func routePendingNavigation() {
        handlePendingTrigger()
        handlePendingOpen()
    }

    /// Tap-to-run notification: navigate AND auto-trigger the job.
    /// The trigger is consumed from the shared state the moment routing is
    /// committed so repeated onChange firings can't push (and run) it twice.
    private func handlePendingTrigger() {
        guard let trigger = navState.pendingTrigger,
              let agent = viewModel.agents.first(where: { $0.id == trigger.agentId }) else { return }
        navState.pendingTrigger = nil
        routedJob = trigger
        navPath.removeLast(navPath.count)
        navPath.append(agent)
    }

    /// Result-ready notification: the job already ran in the background —
    /// only navigate to the conversation, never re-trigger.
    private func handlePendingOpen() {
        guard let agentId = navState.pendingOpen,
              let agent = viewModel.agents.first(where: { $0.id == agentId }) else { return }
        navState.pendingOpen = nil
        navPath.removeLast(navPath.count)
        navPath.append(agent)
    }

    private func routedJobId(for agent: Agent) -> UUID? {
        routedJob?.agentId == agent.id ? routedJob?.jobId : nil
    }

    private func clearRoutedJob(for agent: Agent) {
        if routedJob?.agentId == agent.id {
            routedJob = nil
        }
    }
}
