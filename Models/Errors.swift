import Foundation

// MARK: - Error Types (migrated)

enum APIError: LocalizedError {
    case invalidURL
    case noInternetConnection
    case requestTimeout
    case invalidResponse
    case decodingError(Error)
    case serverError(Int)
    case unknown(Error)
    case networkError(Int)
    
    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid API endpoint"
        case .noInternetConnection: return "Internet connection required. Please check your connection."
        case .requestTimeout: return "Request timed out. Please try again."
        case .invalidResponse: return "Received invalid response from server"
        case .decodingError(let error): return "Failed to parse response: \(error.localizedDescription)"
    case .serverError(let code): return "Server error (HTTP \(code))"
    case .networkError(let code): return "Network error (HTTP \(code))"
        case .unknown(let error): return "An unexpected error occurred: \(error.localizedDescription)"
        }
    }
}

enum TokenProviderError: LocalizedError {
    case missingSecrets
    case invalidResponse
    case backendUnavailable
    case emptyToken
    case expired
    
    var errorDescription: String? {
        switch self {
        case .missingSecrets: return "Secrets.plist not found or API_TOKEN missing."
        case .invalidResponse: return "Invalid token response."
        case .backendUnavailable: return "Token backend unavailable."
        case .emptyToken: return "Empty token returned."
        case .expired: return "Token expired."
        }
    }
}

extension Error {
    var isNetworkError: Bool {
        let nsError = self as NSError
        return nsError.domain == NSURLErrorDomain || nsError.domain == NSPOSIXErrorDomain
    }
}
