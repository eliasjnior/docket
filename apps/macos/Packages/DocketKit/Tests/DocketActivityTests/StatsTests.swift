import DocketActivity
import DocketCore
import DocketTestSupport
import Foundation
import Testing

struct StatsTests {
    private let now = Fixtures.now
    private let hour: TimeInterval = 3600
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        return calendar
    }

    @Test func theThreeMetrics() {
        let viewer = ViewerContext(login: "you", teams: nil)
        let reviewed = [
            ReviewHistory(
                id: "PR_1", author: "ana", mergedAt: nil,
                requests: [Fixtures.request("E1", at: now.addingTimeInterval(-10 * hour))],
                reviews: [Fixtures.review("R1", by: "you", .approved, at: now.addingTimeInterval(-8 * hour))]),
            ReviewHistory(
                id: "PR_2", author: "bruno", mergedAt: nil,
                requests: [
                    Fixtures.request("E2", at: now.addingTimeInterval(-20 * hour)),
                    Fixtures.request("E3", to: .user(login: "carla"), at: now),
                ],
                reviews: [Fixtures.review("R2", by: "you", .commented, at: now.addingTimeInterval(-16 * hour))]),
            ReviewHistory(
                id: "PR_3", author: "dave", mergedAt: nil,
                requests: [Fixtures.request("E4", at: now.addingTimeInterval(-10 * 86400))], reviews: []),
        ]
        let authored = [
            ReviewHistory(
                id: "PR_4", author: "you", mergedAt: now,
                requests: [],
                reviews: [Fixtures.review("R3", by: "ana", .approved, at: now.addingTimeInterval(-5 * hour))]),
            ReviewHistory(
                id: "PR_5", author: "you", mergedAt: now,
                requests: [],
                reviews: [Fixtures.review("R4", by: "ana", .approved, at: now.addingTimeInterval(-hour))]),
            ReviewHistory(id: "PR_6", author: "you", mergedAt: nil, requests: [], reviews: []),
        ]
        let report = Stats.report(reviewed: reviewed, authored: authored, viewer: viewer, now: now, calendar: calendar)
        #expect(report.answeredRequests == 2)
        #expect(report.medianTimeToFirstReview == 3 * hour)
        #expect(report.requestsOlderThanTwoWorkingDays == 1)
        #expect(report.approvedButUnmergedOverFourHours == 1)
        #expect(report.mergedPullRequests == 2)
    }

    @Test func medianAndWorkingDays() {
        #expect(Stats.median([]) == nil)
        #expect(Stats.median([3, 1, 2]) == 2)
        #expect(Stats.median([4, 1, 2, 3]) == 2.5)
        // 2026-10-23 is a Friday; to the next Tuesday is 2 working days.
        let friday = Date(timeIntervalSince1970: 1_792_756_800)
        #expect(Stats.workingDays(from: friday, to: friday.addingTimeInterval(4 * 86400), calendar: calendar) == 2)
        #expect(Stats.workingDays(from: friday, to: friday, calendar: calendar) == 0)
    }
}
