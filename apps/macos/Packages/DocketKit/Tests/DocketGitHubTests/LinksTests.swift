import DocketCore
import Foundation
import Testing

@testable import DocketGitHub

struct LinksTests {
    @Test func markdownHtmlAndBareLinksKeepTheirTextAndSkipImages() {
        let body = """
            Deployed! [**Visit Preview**](https://preview-482.acme.dev/) · <a href="https://ci.acme.dev/run/9">CI run</a>
            ![screenshot](https://acme.dev/shot.png) [![badge](https://img.shields.io/x.svg)](https://acme.dev/docs)
            Spec: https://acme.atlassian.net/wiki/page, again https://preview-482.acme.dev/.
            <img src="https://avatars.githubusercontent.com/u/1"> https://github.com/user-attachments/assets/abc
            """
        let links = Links.extract(from: body, source: "vercel[bot]")
        #expect(
            links.map(\.url.absoluteString) == [
                "https://preview-482.acme.dev/", "https://ci.acme.dev/run/9", "https://acme.dev/docs",
                "https://acme.atlassian.net/wiki/page",
            ])
        #expect(links.map(\.title) == ["Visit Preview", "CI run", nil, nil])
        #expect(links.allSatisfy { $0.source == "vercel[bot]" })
    }

    @Test func atMostTenAndNothingFromNothing() {
        let body = (1...15).map { "https://acme.dev/\($0)" }.joined(separator: " ")
        #expect(Links.extract(from: body).count == 10)
        #expect(Links.extract(from: nil).isEmpty)
    }
}
