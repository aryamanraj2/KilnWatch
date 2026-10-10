#if DEBUG
import Foundation
import KilnWatchCore
import Synchronization

/// Isolated synthetic HTTP responses. Never used to replace a failed live response.
/// -publicDemo loading|loaded|empty|offline|429|429Recovery|503
/// -publicDetail offline|503|404|429|slow|recovery affects detail only.
enum PublicDemo {
    private struct Configuration: Sendable {
        let scenario: String
        let detail: String?
        let list: Data
        let records: [String: Data]
        let askScenario: String?
        var askCalls = 0
        var listCalls = 0
        var detailCalls = 0
    }
    private static let configurations = Mutex<[String: Configuration]>([:])

    static func api(scenario: String) -> KilnWatchAPI {
        let host = "\(UUID().uuidString.lowercased()).example"
        let records: [[String: Any]] = DemoOptions.string("rulesDemo").map(R1Demo.records) ?? Fixtures.kilns.compactMap { kiln in
            guard let data = try? JSONEncoder.kilnWatch.encode(kiln),
                  var object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
            if DemoOptions.string("askDemo") != nil, kiln.kilnId == "KW-0412" { object["kiln_id"] = "KW-00000000000000000000000000000001" }
            object["violations"] = []
            object["exposure"] = NSNull()
            object["rules_assessment"] = "not_evaluated"
            object["type_verification"] = "unverified"
            object["status"] = "flagged"
            object["evidence"] = ["before": NSNull(), "after": NSNull()]
            return object
        }
        let details = Dictionary(uniqueKeysWithValues: records.map { ($0["kiln_id"] as! String, (try? JSONSerialization.data(withJSONObject: $0)) ?? Data()) })
        let list = (try? JSONSerialization.data(withJSONObject: ["kilns": records, "next_cursor": NSNull()])) ?? Data()
        let config = Configuration(scenario: scenario, detail: DemoOptions.string("publicDetail"), list: list, records: details, askScenario: DemoOptions.string("askDemo"))
        configurations.withLock { $0[host] = config }
        let session = URLSessionConfiguration.ephemeral
        session.protocolClasses = [PublicDemoProtocol.self]
        return KilnWatchAPI(baseURL: URL(string: "https://\(host)")!, session: URLSession(configuration: session))
    }

    static func response(for request: URLRequest) -> (Int, Data) {
        configurations.withLock { configs in
            guard let host = request.url?.host, var config = configs[host] else { return (503, Data()) }
            if request.url?.path == "/ask" {
                config.askCalls += 1; configs[host] = config
                return AskDemo.response(scenario: config.askScenario ?? "unavailable", call: config.askCalls)
            }
            let isDetail = request.url?.path != "/public/kilns"
            if isDetail { config.detailCalls += 1 } else { config.listCalls += 1 }
            configs[host] = config
            let scenario = isDetail ? (config.detail ?? "loaded") : config.scenario
            switch scenario {
            case "offline": return (-1, Data())
            case "503": return (503, Data())
            case "404": return (404, Data())
            case "429": return (429, Data())
            case "429Recovery" where config.listCalls == 1: return (429, Data())
            case "recovery" where config.detailCalls == 1: return (503, Data())
            case "empty": return (200, Data(#"{"kilns":[],"next_cursor":null}"#.utf8))
            default: if isDetail {
                    guard let id = request.url?.lastPathComponent, let record = config.records[id] else { return (404, Data()) }
                    return (200, record)
                }
                return (200, config.list)
            }
        }
    }

    static func isSlowDetail(_ request: URLRequest) -> Bool {
        configurations.withLock { configs in
            guard let host = request.url?.host else { return false }
            if request.url?.path == "/ask" { return configs[host]?.askScenario == "waiting" }
            return request.url?.path != "/public/kilns" && configs[host]?.detail == "slow"
        }
    }
}

/// The delayed DEBUG callback only reads the immutable request/client and the
/// cancellation bit below; its sole mutable state is protected by Mutex.
private final class PublicDemoProtocol: URLProtocol, @unchecked Sendable {
    private let stopped = Mutex(false)
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() { stopped.withLock { $0 = true } }
    override func startLoading() {
        let (code, body) = PublicDemo.response(for: request)
        if PublicDemo.isSlowDetail(request) {
            DispatchQueue.global().asyncAfter(deadline: .now() + (request.url?.path == "/ask" ? 20 : 2)) { [weak self] in self?.deliver(code: code, body: body) }
        } else { deliver(code: code, body: body) }
    }

    private func deliver(code: Int, body: Data) {
        guard !stopped.withLock({ $0 }) else { return }
        if code == -1 { client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet)); return }
        guard let url = request.url, let response = HTTPURLResponse(url: url, statusCode: code, httpVersion: nil, headerFields: nil) else { return }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }
}
#endif
