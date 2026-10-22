import DocketActivity
import DocketCore
import DocketTestSupport
import Foundation
import Testing

struct IntegrationsTests {
    private func pullRequest(title: String = "Fix login", branch: String? = nil, links: [String] = []) -> PullRequest {
        var pullRequest = Fixtures.pullRequest(title: title)
        pullRequest.headRefName = branch
        pullRequest.issueLinks = links.compactMap(URL.init(string:))
        return pullRequest
    }

    @Test func jiraPrefersBodyLink() {
        let pullRequest = pullRequest(
            title: "API-7 Fix login", branch: "api-8-login",
            links: ["https://other.atlassian.net/browse/X-1", "https://acme.atlassian.net/browse/API-12"])
        #expect(
            Jira.link(for: pullRequest, base: "https://acme.atlassian.net/")?.absoluteString
                == "https://acme.atlassian.net/browse/API-12")
    }

    @Test func jiraFallsBackToTitleThenBranch() {
        #expect(
            Jira.link(for: pullRequest(title: "[API-7] Fix login", branch: "api-8"), base: "acme.atlassian.net")?
                .absoluteString == "https://acme.atlassian.net/browse/API-7")
        #expect(
            Jira.link(
                for: pullRequest(title: "Bump node-18", branch: "feature/api-8-login"), base: "acme.atlassian.net")?
                .absoluteString == "https://acme.atlassian.net/browse/API-8")
        #expect(Jira.link(for: pullRequest(title: "Fix login", branch: "main"), base: "acme.atlassian.net") == nil)
    }

    @Test func namesThatLookLikeKeysAreNotIssues() {
        for title in ["Decode UTF-8 names", "Pin SHA-256 digests", "Parse ISO-8601 dates"] {
            #expect(Jira.link(for: pullRequest(title: title), base: "acme.atlassian.net") == nil)
        }
    }

    @Test func aBareTitleIsFlagged() {
        #expect(CommandScript.titleStandsAlone("tool {title}"))
        #expect(!CommandScript.titleStandsAlone(#"tool "{title}" {url}"#))
        #expect(!CommandScript.titleStandsAlone(Config.Integrations.defaultReviewCommand))
    }

    @Test func jiraNilWithoutBase() {
        #expect(Jira.link(for: pullRequest(title: "API-7"), base: nil) == nil)
        #expect(Jira.link(for: pullRequest(title: "API-7"), base: "  ") == nil)
    }

    @Test func placeholdersAreQuotedForWhereTheySit() {
        let script = CommandScript.render(
            template: #"tool {url} "about {title}" 'literal {repo}' \{branch}"#, values: [:], directory: "/tmp/x")
        #expect(script.contains(#"tool "${DOCKET_URL}" "about ${DOCKET_TITLE}" 'literal {repo}' \{branch}"#))
        #expect(script.contains("cd -- '/tmp/x' || exit 1"))
        #expect(script.hasPrefix("#!/bin/zsh\nrm -f -- \"$0\"\n"))
        #expect(CommandScript.placeholdersInSingleQuotes(#"a '{repo}' "{url}" {title}"#) == ["repo"])
        #expect(CommandScript.render(template: "x", values: [:], directory: nil).contains("mktemp -d"))
    }

    @Test func hostileValuesStayLiteral() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "docket-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let marker = folder.appending(path: "pwned").path
        let hostile = "$(touch \(marker)) `touch \(marker)` '; touch \(marker); echo ' \"x\"\nline2 \\n {url}"
        let script = CommandScript.render(
            template: #"print -r -- "Title: {title}"; print -r -- {title}; print -r -- {branch}"#,
            values: ["title": hostile, "branch": "it's; touch \(marker)", "url": "https://github.com/acme/api/pull/1"],
            directory: folder.path)
        let file = folder.appending(path: "run.command")
        try script.write(to: file, atomically: true, encoding: .utf8)
        let shell = Process()
        shell.executableURL = URL(fileURLWithPath: "/bin/zsh")
        shell.arguments = [file.path]
        let output = Pipe()
        shell.standardOutput = output
        try shell.run()
        shell.waitUntilExit()
        let printed = String(bytes: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)
        #expect(printed == "Title: \(hostile)\n\(hostile)\nit's; touch \(marker)\n")
        #expect(!FileManager.default.fileExists(atPath: marker))
        #expect(!FileManager.default.fileExists(atPath: file.path))
    }

    @Test func integrationsDecodeWithDefaults() throws {
        let decoded = try JSONDecoder().decode(
            Config.self, from: Data(#"{"integrations":{"clones":{"acme/api":"/src/api"}}}"#.utf8))
        #expect(decoded.integrations.reviewCommand == Config.Integrations.defaultReviewCommand)
        #expect(decoded.integrations.clone(of: "ACME/api") == "/src/api")
        #expect(decoded.integrations.clone(of: "acme/web") == nil)
        #expect(Config.Integrations.defaultReviewCommand.contains("{url}"))
    }
}
