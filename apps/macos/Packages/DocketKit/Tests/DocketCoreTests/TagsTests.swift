import DocketCore
import Testing

struct TagsTests {
    @Test(arguments: [(" WIP ", "wip"), ("After Release", "after-release"), ("needs_review", "needs-review")])
    func normalization(input: String, expected: String) {
        #expect(Tags.normalize(input) == expected)
        #expect(Tags.normalize(expected) == expected)
    }

    @Test func validation() {
        #expect(Tags.validate(" WIP ", existing: []) == .success("wip"))
        #expect(Tags.validate("ünïcode", existing: []) == .failure(.invalidCharacters))
        #expect(Tags.validate("a/b", existing: []) == .failure(.invalidCharacters))
        #expect(Tags.validate(String(repeating: "a", count: 25), existing: []) == .failure(.tooLong))
        #expect(
            Tags.validate(String(repeating: "a", count: 24), existing: [])
                == .success(String(repeating: "a", count: 24)))
        #expect(Tags.validate("wip", existing: ["wip"]) == .failure(.alreadyAdded))
        #expect(Tags.validate("six", existing: ["a", "b", "c", "d", "e"]) == .failure(.tooMany))
        #expect(Tags.validate("   ", existing: []) == .failure(.empty))
    }

    @Test func suggestionsAreMostUsedFirstAndWipWhenNone() {
        let inUse = Tags.inUse([["wip", "infra"], ["infra"], ["blocked"]])
        #expect(inUse == ["infra", "blocked", "wip"])
        #expect(Tags.suggestions(inUse: inUse, prefix: "", excluding: ["infra"]) == ["blocked", "wip"])
        #expect(Tags.suggestions(inUse: inUse, prefix: "B", excluding: []) == ["blocked"])
        #expect(Tags.suggestions(inUse: [], prefix: "", excluding: []) == ["wip"])
    }
}
