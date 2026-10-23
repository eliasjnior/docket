import DocketActivity
import DocketCore
import DocketTestSupport
import Testing

struct PullRequestSizeTests {
    /// Lines changed, split between additions and deletions, and the size they make.
    private static let cases: [(Int, PullRequestSize)] = [
        (0, .extraSmall), (10, .extraSmall), (11, .small), (100, .small), (101, .medium), (400, .medium),
        (401, .large), (1000, .large), (1001, .extraLarge),
    ]

    @Test(arguments: cases)
    func linesAddedAndDeletedDecideTheSize(lines: Int, expected: PullRequestSize) {
        var pullRequest = Fixtures.pullRequest()
        pullRequest.additions = lines - lines / 3
        pullRequest.deletions = lines / 3
        #expect(PullRequestSize.of(pullRequest) == expected)
        #expect(expected.isLarge == (lines > 400))
    }

    @Test func aCacheWithoutLineCountsHasNoSize() {
        #expect(PullRequestSize.of(Fixtures.pullRequest()) == nil)
    }
}
