import Testing
import Foundation
@testable import Ember

@Suite("Job run safety", .serialized)
struct JobRunTests {
    private let db = AppDatabase.shared

    @Test("A job that is already running cannot be started again until it ends")
    func guardBlocksOverlap() async {
        let guardActor = JobRunGuard()
        let id = UUID()
        #expect(await guardActor.tryBegin(id))
        #expect(!(await guardActor.tryBegin(id)))
        await guardActor.end(id)
        #expect(await guardActor.tryBegin(id))
    }

    @Test("Different jobs do not block each other")
    func guardIsPerJob() async {
        let guardActor = JobRunGuard()
        #expect(await guardActor.tryBegin(UUID()))
        #expect(await guardActor.tryBegin(UUID()))
    }

    private func makeFixture() throws -> (Conversation, Agent, AgentJob) {
        var convo = Conversation()
        try db.save(&convo)
        var agent = Agent.make(name: "T", emoji: "x", description: "test")
        agent.conversationId = convo.id
        try db.saveAgent(&agent)
        var job = AgentJob.make(agentId: agent.id, name: "j", prompt: "p", hour: 9, minute: 0, days: [])
        try db.saveJob(&job)
        return (convo, agent, job)
    }

    private func cleanup(_ convo: Conversation, _ agent: Agent) {
        try? db.deleteAgent(agent)
        try? db.delete(convo)
    }

    @Test("A completed run saves prompt, reply and last-run stamps together")
    func recordsRun() throws {
        let (convo, agent, job) = try makeFixture()
        defer { cleanup(convo, agent) }
        let user = Message(conversationId: convo.id, role: .user, content: "p")
        let reply = Message(conversationId: convo.id, role: .assistant, content: "r")

        try db.recordJobRun(userMessage: user, assistantMessage: reply, jobId: job.id, agentId: agent.id)

        #expect(try db.messages(for: convo.id).count == 2)
        #expect(try db.jobs(for: agent.id).first?.lastRunAt != nil)
    }

    @Test("If any part of a run fails, nothing is saved, so a retry doesn't leave duplicate prompts")
    func failedRunLeavesNothing() throws {
        let (convo, agent, job) = try makeFixture()
        defer { cleanup(convo, agent) }
        let user = Message(conversationId: convo.id, role: .user, content: "p")
        // Same primary key as the prompt, so the second insert fails.
        var clash = Message(conversationId: convo.id, role: .assistant, content: "r")
        clash.id = user.id

        #expect(throws: (any Error).self) {
            try db.recordJobRun(userMessage: user, assistantMessage: clash, jobId: job.id, agentId: agent.id)
        }

        #expect(try db.messages(for: convo.id).isEmpty)
        #expect(try db.jobs(for: agent.id).first?.lastRunAt == nil)
    }
}
