import Foundation

public protocol TokenProvider {
    func getToken() async throws -> String
}

public enum TokenProviderError: Error {
    case missingToken
    case expired
    case networkFailure(String)
    case decodingFailure
}
