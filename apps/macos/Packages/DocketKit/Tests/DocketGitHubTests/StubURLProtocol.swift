import DocketCore
import Foundation
import Synchronization

/// Serves scripted responses at the network edge, and records every request (`docs/03-architecture.md` §7).
final class StubURLProtocol: URLProtocol {
    struct Stub {
        var status: Int = 200
        var headers: [String: String] = [:]
        var body: Data
    }

    private struct Script {
        var queue: [Stub] = []
        var recorded: [URLRequest] = []
    }

    private static let script = Mutex(Script())

    static func reset(_ stubs: [Stub]) {
        script.withLock { $0 = Script(queue: stubs) }
    }

    static var requests: [URLRequest] { script.withLock { $0.recorded } }

    static func fixture(_ name: String) -> Data {
        guard let url = Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"),
            let data = try? Data(contentsOf: url)
        else { return Data() }
        return data
    }

    override static func canInit(with request: URLRequest) -> Bool { true }
    override static func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        var request = request
        if request.httpBody == nil, let stream = request.httpBodyStream {
            request.httpBody = Self.read(stream)
        }
        let stub: Stub? = Self.script.withLock { script in
            script.recorded.append(request)
            return script.queue.isEmpty ? nil : script.queue.removeFirst()
        }
        guard let stub, let url = request.url,
            let response = HTTPURLResponse(
                url: url, statusCode: stub.status, httpVersion: "HTTP/1.1", headerFields: stub.headers)
        else {
            client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: stub.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    private static func read(_ stream: InputStream) -> Data {
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count <= 0 { break }
            data.append(buffer, count: count)
        }
        return data
    }
}

/// Hands out scripted tokens.
actor ScriptedTokens: TokenProvider {
    private var tokens: [String]
    private(set) var refreshes = 0

    init(_ tokens: [String]) {
        self.tokens = tokens
    }

    func token() async throws -> String { tokens.first ?? "" }

    func refresh() async throws -> String {
        refreshes += 1
        if tokens.count > 1 { tokens.removeFirst() }
        return tokens.first ?? ""
    }
}
