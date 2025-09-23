import Foundation
import SwiftUI

// MARK: - Domain Models (migrated from monolith)

struct TipTemplate: Codable, Identifiable {
    var id = UUID()
    var name: String
    var createdDate: Date
    var rules: TipRules
    var participants: [Participant]
    var displayConfig: DisplayConfig
}

struct TipRules: Codable {
    var type: RuleType
    var formula: String
    var offTheTop: [OffTheTopRule]?
    var roleWeights: [String: Double]?
    var customLogic: String?
    
    enum RuleType: String, Codable, CaseIterable {
        case hoursBased = "hours"
        case percentage = "percentage"
        case equal = "equal"
        case roleWeighted = "role_weighted"
        case hybrid = "hybrid"
    }
}

struct OffTheTopRule: Codable {
    var role: String
    var percentage: Double
}

struct Participant: Codable, Identifiable {
    var id = UUID()
    var name: String
    var role: String
    var hours: Double?
    var weight: Double?
    var calculatedAmount: Double?
    var actualAmount: Double?
    
    var emoji: String {
        switch role.lowercased() {
        case "server": return "👤"
        case "busser": return "🍽️"
        case "host": return "🎯"
        case "bartender": return "🍹"
        case "cook", "kitchen": return "👨‍🍳"
        case "manager": return "💼"
        default: return "💰"
        }
    }
    
    var color: Color {
        switch role.lowercased() {
        case "server": return .purple
        case "busser": return .blue
        case "host": return .mint
        case "bartender": return .orange
        case "cook", "kitchen": return .pink
        case "manager": return .indigo
        default: return .gray
        }
    }
}

struct DisplayConfig: Codable {
    var primaryVisualization: String
    var accentColor: String
    var showPercentages: Bool
    var showComparison: Bool
}

struct OnboardingResponse: Codable {
    var status: ResponseStatus
    var message: String
    var clarificationNeeded: Bool
    var template: TipTemplate?
    var suggestedQuestions: [String]?
    
    enum ResponseStatus: String, Codable {
        case inProgress = "in_progress"
        case needsClarification = "needs_clarification"
        case complete = "complete"
        case error = "error"
    }
}

struct CalculationResponse: Codable {
    var splits: [Participant]
    var summary: String
    var warnings: [String]?
    var visualizationHints: [String: String]?
}

struct MockProduct: Identifiable {
    let id: String
    let displayName: String
    let displayPrice: String
    let description: String
    
    func purchase() async throws -> PurchaseResult {
        try await Task.sleep(nanoseconds: 500_000_000)
        return .success
    }
    
    enum PurchaseResult { case success, userCancelled, pending }
}
