import Foundation

final class EphemeralTokenProvider: TokenProvider {
    private let endpoint: URL
    private let session: URLSession
    private var cached: (value: String, expiry: Date)?
    private let headroom: TimeInterval = 30

    init(endpoint: URL, session: URLSession = .shared) { self.endpoint = endpoint; self.session = session }

    func getToken() async throws -> String {
        if let cached = cached, cached.expiry.timeIntervalSinceNow > headroom { return cached.value }
        var request = URLRequest(url: endpoint)
        request.httpMethod = "GET"
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else { throw TokenProviderError.networkFailure("Status code \((response as? HTTPURLResponse)?.statusCode ?? -1)") }
        struct Payload: Decodable { let token: String; let expiresAt: String? }
        let payload = try JSONDecoder().decode(Payload.self, from: data)
        guard !payload.token.isEmpty else { throw TokenProviderError.missingToken }
        var expiry: Date? = nil
        if let e = payload.expiresAt { expiry = parseExpiry(e) }
        if let expiry, expiry.timeIntervalSinceNow < headroom { throw TokenProviderError.expired }
        cached = (payload.token, expiry)
        return payload.token
    }

    private func parseExpiry(_ raw: String) -> Date? {
        let iso = ISO8601DateFormatter()
        if let d = iso.date(from: raw) { return d }
        if let t = TimeInterval(raw) { return Date(timeIntervalSince1970: t) }
        return nil
    }
}
