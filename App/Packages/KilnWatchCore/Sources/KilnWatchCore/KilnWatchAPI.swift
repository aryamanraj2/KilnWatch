import Foundation

public enum APIError: Error {
    case invalidPagination
    /// No HTTP response: offline, timeout, TLS, cancelled.
    case transport(any Error)
    /// The token provider failed; the user probably needs to sign in again.
    case token(any Error)
    /// Non-2xx response. `body` is the raw error JSON (see docs/api-contract.md).
    case status(Int, body: Data)
    /// The body did not match the contract. `keyPath` names the field, for example "kilns[0].kilnId".
    case decoding(keyPath: String, DecodingError)

    /// True when waiting is the fix for every request, not just this one.
    var isSystemic: Bool {
        switch self {
        case .transport, .token: true
        case .status(let code, _): code >= 500 || [401, 408, 429].contains(code)
        case .decoding, .invalidPagination: false
        }
    }
}

/// REST client for the endpoints in docs/api-contract.md.
public struct KilnWatchAPI: Sendable {
    public var baseURL: URL
    public var session: URLSession
    /// Returns a Cognito JWT, refreshing it if needed.
    public var token: @Sendable () async throws -> String

    /// Public reads need no token. Protected calls still fail unless a provider is supplied.
    public init(baseURL: URL, session: URLSession = .shared, token: @escaping @Sendable () async throws -> String = { throw URLError(.userAuthenticationRequired) }) {
        self.baseURL = baseURL
        self.session = session
        self.token = token
    }

    /// Public registry reads must reach the network and must not persist response bodies.
    /// Protected clients keep their existing session and authentication behavior.
    public static func publicReadSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForResource = 40
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCredentialStorage = nil
        return URLSession(configuration: configuration)
    }

    public func kilns(district: String, status: KilnStatus? = nil) async throws(APIError) -> [Kiln] {
        var query = [URLQueryItem(name: "district", value: district)]
        if let status { query.append(URLQueryItem(name: "status", value: status.rawValue)) }
        return try await list(path: "kilns", query: query, authorized: true)
    }

    /// Reads every public district page, with the same cursor safety as inspector reads.
    public func publicKilns(district: String) async throws(APIError) -> [Kiln] {
        try await list(path: "public/kilns", query: [URLQueryItem(name: "district", value: district)], authorized: false)
    }

    /// Nearby public results may include distance_m, which the kiln decoder safely ignores.
    public func publicKilns(latitude: Double, longitude: Double, radiusM: Double) async throws(APIError) -> [Kiln] {
        let query = [URLQueryItem(name: "lat", value: String(latitude)),
                     URLQueryItem(name: "lon", value: String(longitude)),
                     URLQueryItem(name: "radius_m", value: String(radiusM))]
        return try await send(URLRequest(url: baseURL.appending(path: "public/kilns").appending(queryItems: query)), as: KilnList.self, authorized: false).kilns
    }

    public func publicKiln(id: String) async throws(APIError) -> Kiln {
        try await send(URLRequest(url: baseURL.appending(path: "public/kilns").appending(path: id)), as: Kiln.self, authorized: false)
    }

    private func list(path: String, query: [URLQueryItem], authorized: Bool) async throws(APIError) -> [Kiln] {
        var query = query
        var result: [Kiln] = []
        var seen: Set<String> = []
        while true {
            let page = try await send(URLRequest(url: baseURL.appending(path: path).appending(queryItems: query)), as: KilnList.self, authorized: authorized)
            result.append(contentsOf: page.kilns)
            guard let cursor = page.nextCursor else { return result }
            guard !cursor.isEmpty, !page.kilns.isEmpty, seen.insert(cursor).inserted else { throw .invalidPagination }
            query.removeAll { $0.name == "cursor" }
            query.append(URLQueryItem(name: "cursor", value: cursor))
        }
    }

    public func kiln(id: String) async throws(APIError) -> Kiln {
        try await send(URLRequest(url: baseURL.appending(path: "kilns").appending(path: id)), as: Kiln.self)
    }

    public func todayRoute() async throws(APIError) -> Route {
        try await send(URLRequest(url: baseURL.appending(path: "routes/today")), as: Route.self)
    }

    public func rules() async throws(APIError) -> [Rule] {
        try await send(URLRequest(url: baseURL.appending(path: "rules")), as: RuleList.self).rules
    }

    /// Safe to repeat: the verdict's id is sent as the Idempotency-Key.
    public func submit(_ verdict: Verdict) async throws(APIError) -> VerdictReceipt {
        var request = URLRequest(url: baseURL.appending(path: "verdicts"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(verdict.id.uuidString, forHTTPHeaderField: "Idempotency-Key")
        do {
            request.httpBody = try JSONEncoder.kilnWatch.encode(verdict)
        } catch {
            preconditionFailure("Only a NaN coordinate fails to encode, and VerdictOutbox.enqueue rejects those first: \(error)")
        }
        return try await send(request, as: VerdictReceipt.self)
    }

    /// PUTs a JPEG to a presigned S3 URL from a `VerdictReceipt`. No bearer token: S3 rejects two auth schemes.
    public func upload(_ jpeg: Data, to url: URL) async throws(APIError) {
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("image/jpeg", forHTTPHeaderField: "Content-Type")
        _ = try await perform(request, body: jpeg)
    }

    private func send<T: Decodable>(_ request: URLRequest, as type: T.Type, authorized: Bool = true) async throws(APIError) -> T {
        var request = request
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if authorized {
            do {
                request.setValue("Bearer \(try await token())", forHTTPHeaderField: "Authorization")
            } catch {
                throw .token(error)
            }
        } else {
            request.setValue(nil, forHTTPHeaderField: "Authorization")
            request.cachePolicy = .reloadIgnoringLocalCacheData
        }
        let data = try await perform(request, body: nil)
        do {
            return try JSONDecoder.kilnWatch.decode(T.self, from: data)
        } catch let error as DecodingError {
            throw .decoding(keyPath: error.keyPath, error)
        } catch {
            preconditionFailure("JSONDecoder throws only DecodingError: \(error)")
        }
    }

    private func perform(_ request: URLRequest, body: Data?) async throws(APIError) -> Data {
        let data: Data, response: URLResponse
        do {
            (data, response) = if let body {
                try await session.upload(for: request, from: body)
            } else {
                try await session.data(for: request)
            }
        } catch {
            throw .transport(error)
        }
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else { throw .status(code, body: data) }
        return data
    }
}

extension DecodingError {
    /// "kilns[0].footprint.centroid.latitude", including the missing key for keyNotFound.
    var keyPath: String {
        let path: [any CodingKey] = switch self {
        case .keyNotFound(let key, let context): context.codingPath + [key]
        case .typeMismatch(_, let context), .valueNotFound(_, let context), .dataCorrupted(let context): context.codingPath
        @unknown default: []
        }
        return path.reduce("") { result, key in
            if let index = key.intValue { "\(result)[\(index)]" } else { result.isEmpty ? key.stringValue : "\(result).\(key.stringValue)" }
        }
    }
}
