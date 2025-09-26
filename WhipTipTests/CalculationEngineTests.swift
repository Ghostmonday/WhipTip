// CalculationEngineTests.swift
// Tests for core split computation logic.
// NOTE: This test target uses a lightweight mirror of production types because the app is a monolith.
// As the monolith evolves, consider extracting the calculation engine into a module for direct import.

import XCTest
import WhipTipCore

final class CalculationEngineTests: XCTestCase {
    // Helper to build a minimal TipTemplate leveraging existing production structures.
    private func buildTemplate(
        name: String = "Test",
        ruleType: TipRules.RuleType,
        participants: [Participant],
        roleWeights: [String: Double]? = nil,
        offTop: [OffTheTopRule]? = nil,
        formula: String = ""
    ) -> TipTemplate {
        TipTemplate(
            name: name,
            createdDate: Date(),
            rules: TipRules(
                type: ruleType,
                formula: formula,
                offTheTop: offTop,
                roleWeights: roleWeights,
                customLogic: nil
            ),
            participants: participants,
            displayConfig: DisplayConfig(
                primaryVisualization: "pie",
                accentColor: "purple",
                showPercentages: true,
                showComparison: true
            )
        )
    }

    func testEqualSplitEvenlyDivisible() throws {
        let participants = [
            Participant(name: "A", role: "any", hours: nil, weight: nil, calculatedAmount: nil, actualAmount: nil),
            Participant(name: "B", role: "any", hours: nil, weight: nil, calculatedAmount: nil, actualAmount: nil),
            Participant(name: "C", role: "any", hours: nil, weight: nil, calculatedAmount: nil, actualAmount: nil)
        ]
        let template = buildTemplate(ruleType: .equal, participants: participants)
        let (splits, warnings) = computeSplits(template: template, pool: 300)
        XCTAssertTrue(warnings.isEmpty, "Unexpected warnings: \(warnings)")
        let amounts = splits.compactMap { $0.calculatedAmount }
        XCTAssertEqual(Set(amounts), [100.0])
        XCTAssertEqual(amounts.reduce(0,+), 300.0)
    }

    func testRoundingDistributesPenniesFairly() throws {
        let participants = ["A","B","C"].map { Participant(name: $0, role: "any", hours: nil, weight: nil, calculatedAmount: nil, actualAmount: nil) }
        let template = buildTemplate(ruleType: .equal, participants: participants)
        let (splits, _) = computeSplits(template: template, pool: 100)
        let amounts = splits.compactMap { $0.calculatedAmount }
        // Convert to cents to avoid truncation errors when casting to Int dollars.
        let cents = amounts.map { Int(round($0 * 100)) }
        XCTAssertEqual(cents.reduce(0,+), 10000, "Total cents should equal $100.00")
        // Expect exactly one participant to get the extra cent (3334) and others 3333.
        // If algorithm evolves but still fair, allow any ordering; just enforce distribution shape.
        let maxC = cents.max() ?? 0
        let minC = cents.min() ?? 0
        XCTAssertLessThanOrEqual(maxC - minC, 1, "Difference between max and min allocation should be at most 1 cent")
        XCTAssertEqual(cents.filter { $0 == maxC }.count, 1, "Exactly one participant should have the extra cent")
    }

    func testOffTheTopClamp() throws {
        // Off the top tries to allocate more than 100% total.
        let participants = [
            Participant(name: "A", role: "server", hours: nil, weight: nil, calculatedAmount: nil, actualAmount: nil),
            Participant(name: "B", role: "busser", hours: nil, weight: nil, calculatedAmount: nil, actualAmount: nil)
        ]
        let offTop = [
            OffTheTopRule(role: "server", percentage: 80),
            OffTheTopRule(role: "busser", percentage: 70) // total 150%
        ]
        let template = buildTemplate(ruleType: .equal, participants: participants, offTop: offTop)
        let (splits, warnings) = computeSplits(template: template, pool: 100)
        let total = splits.compactMap { $0.calculatedAmount }.reduce(0,+)
        XCTAssertLessThanOrEqual(total, 100.0)
        XCTAssertTrue(warnings.contains { $0.localizedCaseInsensitiveContains("clamped") }, "Expected clamped warning")
    }

    func testRoleWeightedDistribution() throws {
        let participants = [
            Participant(name: "A", role: "server", hours: nil, weight: nil, calculatedAmount: nil, actualAmount: nil),
            Participant(name: "B", role: "support", hours: nil, weight: nil, calculatedAmount: nil, actualAmount: nil)
        ]
        let template = buildTemplate(ruleType: .roleWeighted, participants: participants, roleWeights: ["server": 70, "support": 30])
        let (splits, warnings) = computeSplits(template: template, pool: 100)
        XCTAssertTrue(warnings.isEmpty, "Unexpected warnings: \(warnings)")
        let amounts = splits.compactMap { $0.calculatedAmount }
        XCTAssertEqual(amounts.reduce(0,+), 100.0)
        XCTAssertTrue(amounts.contains(70.0))
        XCTAssertTrue(amounts.contains(30.0))
    }

    func testHoursBasedZeroHoursFallback() throws {
        let participants = [
            Participant(name: "A", role: "x", hours: 0, weight: nil, calculatedAmount: nil, actualAmount: nil),
            Participant(name: "B", role: "y", hours: 0, weight: nil, calculatedAmount: nil, actualAmount: nil),
            Participant(name: "C", role: "z", hours: 0, weight: nil, calculatedAmount: nil, actualAmount: nil)
        ]
        let template = buildTemplate(ruleType: .hoursBased, participants: participants)
        let (splits, warnings) = computeSplits(template: template, pool: 99)
        let amounts = splits.compactMap { $0.calculatedAmount }
        XCTAssertEqual(amounts.reduce(0,+), 99.0)
        // Acceptable distribution: 33,33,33 or 33,33,34 etc. Ensure no negative & sum integrity.
        XCTAssertTrue(amounts.allSatisfy { $0 >= 0 })
        XCTAssertTrue(amounts.max()! - amounts.min()! <= 1, "Distribution should be nearly equal when hours are zero")
        XCTAssertFalse(warnings.contains { $0.localizedCaseInsensitiveContains("error") })
    }
}
