import Testing
import Foundation
@testable import Ember

@Suite("AgentJob scheduling — interval jobs")
struct AgentJobIntervalTests {
    let agentId = UUID()

    @Test("Never-run interval job is always due")
    func neverRun() {
        let job = AgentJob.makeInterval(agentId: agentId, name: "A", prompt: "p", intervalMinutes: 60)
        #expect(job.isDue)
    }

    @Test("Interval job run recently is not due")
    func runRecently() {
        var job = AgentJob.makeInterval(agentId: agentId, name: "A", prompt: "p", intervalMinutes: 60)
        job.lastRunAt = Date().addingTimeInterval(-30 * 60)
        #expect(!job.isDue)
    }

    @Test("Interval job whose full interval has elapsed is due")
    func intervalElapsed() {
        var job = AgentJob.makeInterval(agentId: agentId, name: "A", prompt: "p", intervalMinutes: 60)
        job.lastRunAt = Date().addingTimeInterval(-90 * 60)
        #expect(job.isDue)
    }

    @Test("makeInterval clamps intervalMinutes to 15 minimum")
    func minimumClamped() {
        let job = AgentJob.makeInterval(agentId: agentId, name: "A", prompt: "p", intervalMinutes: 5)
        #expect(job.intervalMinutes == 15)
    }

    @Test("Clamped interval enforces 15-minute threshold for isDue")
    func clampedIsDue() {
        let job = AgentJob.makeInterval(agentId: agentId, name: "A", prompt: "p", intervalMinutes: 1)
        var notDue = job
        notDue.lastRunAt = Date().addingTimeInterval(-10 * 60)   // 10 min < 15 min floor
        #expect(!notDue.isDue)

        var due = job
        due.lastRunAt = Date().addingTimeInterval(-20 * 60)      // 20 min > 15 min floor
        #expect(due.isDue)
    }

    @Test("nextFireDate for never-run interval job is effectively now")
    func nextFireNeverRun() {
        let job = AgentJob.makeInterval(agentId: agentId, name: "A", prompt: "p", intervalMinutes: 60)
        #expect(job.nextFireDate.timeIntervalSinceNow < 5)
    }

    @Test("nextFireDate for interval job is lastRunAt + interval")
    func nextFireAfterRun() {
        var job = AgentJob.makeInterval(agentId: agentId, name: "A", prompt: "p", intervalMinutes: 60)
        let lastRun = Date().addingTimeInterval(-30 * 60)
        job.lastRunAt = lastRun
        let expected = lastRun.addingTimeInterval(60 * 60)
        #expect(abs(job.nextFireDate.timeIntervalSince(expected)) < 2)
    }

    @Test("nextFireDate for overdue interval job is effectively now")
    func nextFireOverdue() {
        var job = AgentJob.makeInterval(agentId: agentId, name: "A", prompt: "p", intervalMinutes: 60)
        job.lastRunAt = Date().addingTimeInterval(-120 * 60)
        #expect(job.nextFireDate.timeIntervalSinceNow < 5)
    }
}

@Suite("AgentJob scheduling — time-based jobs")
struct AgentJobTimeBasedTests {
    let agentId = UUID()

    @Test("Job scheduled at midnight (00:00) is due today if never run")
    func dueAfterMidnight() {
        let today = Calendar.current.component(.weekday, from: Date())
        let job = AgentJob.make(agentId: agentId, name: "A", prompt: "p",
                                hour: 0, minute: 0, days: [today])
        #expect(job.isDue)
    }

    @Test("Job scheduled 10 min before midnight is not yet due")
    func notYetDue() {
        let cal = Calendar.current
        let hour = cal.component(.hour, from: Date())
        guard hour < 23 else { return }   // skip when running near midnight
        let today = cal.component(.weekday, from: Date())
        let job = AgentJob.make(agentId: agentId, name: "A", prompt: "p",
                                hour: 23, minute: 50, days: [today])
        #expect(!job.isDue)
    }

    @Test("Job already run after midnight today is not due again")
    func alreadyRunToday() {
        let cal = Calendar.current
        let today = cal.component(.weekday, from: Date())
        var job = AgentJob.make(agentId: agentId, name: "A", prompt: "p",
                                hour: 0, minute: 0, days: [today])
        let midnight = cal.startOfDay(for: Date())
        job.lastRunAt = midnight.addingTimeInterval(3600)   // 1 AM today — after the 00:00 schedule
        #expect(!job.isDue)
    }

    @Test("Job is not due on an excluded weekday")
    func wrongWeekday() {
        let cal = Calendar.current
        let today = cal.component(.weekday, from: Date())
        let otherDay = today == 7 ? 1 : today + 1
        let job = AgentJob.make(agentId: agentId, name: "A", prompt: "p",
                                hour: 0, minute: 0, days: [otherDay])
        #expect(!job.isDue)
    }

    @Test("nextFireDate for time-based job is always in the future or now")
    func nextFireDateIsNotPast() {
        let today = Calendar.current.component(.weekday, from: Date())
        let job = AgentJob.make(agentId: agentId, name: "A", prompt: "p",
                                hour: 9, minute: 0, days: [today])
        #expect(job.nextFireDate >= Date().addingTimeInterval(-2))
    }
}

@Suite("AgentJob properties and factories")
struct AgentJobPropertiesTests {
    let agentId = UUID()

    @Test("isIntervalBased distinguishes interval from time-based jobs")
    func isIntervalBased() {
        let time     = AgentJob.make(agentId: agentId, name: "A", prompt: "p", hour: 9, minute: 0, days: [])
        let interval = AgentJob.makeInterval(agentId: agentId, name: "A", prompt: "p", intervalMinutes: 30)
        #expect(!time.isIntervalBased)
        #expect(interval.isIntervalBased)
    }

    @Test("Empty scheduleDaysRaw means every day (1–7)")
    func everyDayWeekdays() {
        let job = AgentJob.make(agentId: agentId, name: "A", prompt: "p", hour: 9, minute: 0, days: [])
        #expect(job.effectiveWeekdays == Array(1...7))
    }

    @Test("Specific weekdays are parsed from scheduleDaysRaw in sorted order")
    func specificWeekdays() {
        let job = AgentJob.make(agentId: agentId, name: "A", prompt: "p",
                                hour: 9, minute: 0, days: [6, 2, 4])
        #expect(job.effectiveWeekdays == [2, 4, 6])
    }

    @Test("scheduleTimeString formats midnight, noon, morning, and evening correctly")
    func scheduleTimeString() {
        func job(h: Int, m: Int) -> AgentJob {
            AgentJob.make(agentId: agentId, name: "A", prompt: "p", hour: h, minute: m, days: [])
        }
        #expect(job(h: 0,  m: 0 ).scheduleTimeString == "12:00 AM")
        #expect(job(h: 12, m: 0 ).scheduleTimeString == "12:00 PM")
        #expect(job(h: 9,  m: 30).scheduleTimeString == "9:30 AM")
        #expect(job(h: 22, m: 5 ).scheduleTimeString == "10:05 PM")
        #expect(job(h: 1,  m: 1 ).scheduleTimeString == "1:01 AM")
    }

    @Test("intervalLabel formats minutes and hours")
    func intervalLabel() {
        #expect(AgentJob.intervalLabel(15)  == "Every 15 min")
        #expect(AgentJob.intervalLabel(30)  == "Every 30 min")
        #expect(AgentJob.intervalLabel(45)  == "Every 45 min")
        #expect(AgentJob.intervalLabel(60)  == "Every hour")
        #expect(AgentJob.intervalLabel(120) == "Every 2 hours")
        #expect(AgentJob.intervalLabel(480) == "Every 8 hours")
    }

    @Test("scheduleDescription for every-day job")
    func descriptionEveryDay() {
        let job = AgentJob.make(agentId: agentId, name: "A", prompt: "p", hour: 9, minute: 0, days: [])
        #expect(job.scheduleDescription == "Every day at 9:00 AM")
    }

    @Test("scheduleDescription for specific-day job")
    func descriptionSpecificDays() {
        let job = AgentJob.make(agentId: agentId, name: "A", prompt: "p",
                                hour: 8, minute: 0, days: [2, 4])
        #expect(job.scheduleDescription == "Mon, Wed at 8:00 AM")
    }

    @Test("scheduleDescription for interval job")
    func descriptionInterval() {
        let job = AgentJob.makeInterval(agentId: agentId, name: "A", prompt: "p", intervalMinutes: 60)
        #expect(job.scheduleDescription == "Every hour")
    }

    @Test("notificationBase and intervalNotificationId embed the job id")
    func notificationIds() {
        let job = AgentJob.make(agentId: agentId, name: "A", prompt: "p", hour: 9, minute: 0, days: [])
        #expect(job.notificationBase == "ember-job-\(job.id)")
        #expect(job.intervalNotificationId == "ember-job-\(job.id)-interval")
    }
}
