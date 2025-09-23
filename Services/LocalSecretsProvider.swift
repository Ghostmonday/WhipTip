import Foundation

final class LocalSecretsProvider: TokenProvider {
    private let tokenKey: String
    private let expiryKey: String?
    private let bundle: Bundle
    private var cached: (value: String, expiry: Date?)?
    private let headroom: TimeInterval = 30 // seconds

    init(tokenKey: String = "DEEPSEEK_API_KEY", expiryKey: String? = nil, bundle: Bundle = .main) {
        self.tokenKey = tokenKey
        self.expiryKey = expiryKey
        self.bundle = bundle
    }

    func getToken() async throws -> String {
        if let cached = cached {
            if let expiry = cached.expiry, expiry.timeIntervalSinceNow < headroom { throw TokenProviderError.expired }
            return cached.value
        }
        guard let path = bundle.path(forResource: "Secrets", ofType: "plist"), let dict = NSDictionary(contentsOfFile: path) as? [String: Any] else {
            throw TokenProviderError.missingToken
        }
        guard let token = dict[tokenKey] as? String, !token.isEmpty else { throw TokenProviderError.missingToken }
        var expiryDate: Date? = nil
        if let expiryKey, let raw = dict[expiryKey] {
            if let s = raw as? String { expiryDate = parseDateString(s) }
            else if let t = raw as? TimeInterval { expiryDate = Date(timeIntervalSince1970: t) }
            else if let n = raw as? NSNumber { expiryDate = Date(timeIntervalSince1970: n.doubleValue) }
        }
        if let expiry = expiryDate, expiry.timeIntervalSinceNow < headroom { throw TokenProviderError.expired }
        cached = (token, expiryDate)
        return token
    }

    private func parseDateString(_ s: String) -> Date? {
        let iso = ISO8601DateFormatter()
        if let d = iso.date(from: s) { return d }
        if let t = TimeInterval(s) { return Date(timeIntervalSince1970: t) }
        return nil
    }
}
