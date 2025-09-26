// TipEngine.swift (WhipTipCore)
// Core data models & pure calculation engine extracted from the monolithic app target.
// This module intentionally contains ZERO UI / networking / StoreKit code so it can be unit-tested in isolation.

import Foundation
import SwiftUI

// MARK: - Public Data Models

public struct TipTemplate: Codable, Identifiable, Equatable {
	public var id: UUID
	public var name: String
	public var createdDate: Date
	public var rules: TipRules
	public var participants: [Participant]
	public var displayConfig: DisplayConfig
    
	public init(id: UUID = UUID(), name: String, createdDate: Date, rules: TipRules, participants: [Participant], displayConfig: DisplayConfig) {
		self.id = id
		self.name = name
		self.createdDate = createdDate
		self.rules = rules
		self.participants = participants
		self.displayConfig = displayConfig
	}
}

public struct TipRules: Codable, Equatable {
	public var type: RuleType
	public var formula: String
	public var offTheTop: [OffTheTopRule]?
	public var roleWeights: [String: Double]?
	public var customLogic: String?
    
	public enum RuleType: String, Codable, CaseIterable { case hoursBased = "hours", percentage = "percentage", equal = "equal", roleWeighted = "role_weighted", hybrid = "hybrid" }
    
	public init(type: RuleType, formula: String, offTheTop: [OffTheTopRule]? = nil, roleWeights: [String: Double]? = nil, customLogic: String? = nil) {
		self.type = type
		self.formula = formula
		self.offTheTop = offTheTop
		self.roleWeights = roleWeights
		self.customLogic = customLogic
	}
}

public struct OffTheTopRule: Codable, Equatable { public var role: String; public var percentage: Double; public init(role: String, percentage: Double) { self.role = role; self.percentage = percentage } }

public struct Participant: Codable, Identifiable, Equatable {
	public var id: UUID
	public var name: String
	public var role: String
	public var hours: Double?
	public var weight: Double?
	public var calculatedAmount: Double?
	public var actualAmount: Double?
    
	public init(id: UUID = UUID(), name: String, role: String, hours: Double? = nil, weight: Double? = nil, calculatedAmount: Double? = nil, actualAmount: Double? = nil) {
		self.id = id; self.name = name; self.role = role; self.hours = hours; self.weight = weight; self.calculatedAmount = calculatedAmount; self.actualAmount = actualAmount
	}
    
	public var emoji: String {
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
    
	public var color: Color {
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

public struct DisplayConfig: Codable, Equatable { public var primaryVisualization: String; public var accentColor: String; public var showPercentages: Bool; public var showComparison: Bool; public init(primaryVisualization: String, accentColor: String, showPercentages: Bool, showComparison: Bool) { self.primaryVisualization = primaryVisualization; self.accentColor = accentColor; self.showPercentages = showPercentages; self.showComparison = showComparison } }

// MARK: - Calculation Engine (Pure)

private struct Bucket { var memberIDs: [UUID]; var weight: Double }
private let weightNormalizationEpsilon = 0.001

/// Public entry point for computing tip splits.
@discardableResult
public func computeSplits(template: TipTemplate, pool: Double) -> (splits: [Participant], warnings: [String]) {
	var warnings: [String] = []
	var participants = template.participants
	guard pool >= 0 else { return (participants, ["Pool cannot be negative"]) }
	guard !participants.isEmpty else { return ([], ["No participants to split"]) }
	let poolCents = Int(round(pool * 100))
	let (offTopPerID, remainderAfterOffTop, offTopWarnings) = allocateOffTheTop(participants: participants, poolCents: poolCents, rules: template.rules.offTheTop)
	warnings.append(contentsOf: offTopWarnings)
	let (mainPerID, mainWarnings) = allocateByRule(participants: participants, remainderCents: remainderAfterOffTop, rules: template.rules)
	warnings.append(contentsOf: mainWarnings)
	let combined = combineAndFixPennies(offTop: offTopPerID, main: mainPerID, targetTotal: poolCents, participants: participants)
	for i in participants.indices { participants[i].calculatedAmount = Double(combined[participants[i].id] ?? 0) / 100.0 }
	return (participants, warnings)
}

// MARK: - Allocation Helpers

private func allocateOffTheTop(participants: [Participant], poolCents: Int, rules: [OffTheTopRule]?) -> (perID: [UUID: Int], remainder: Int, warnings: [String]) {
	guard let rules = rules, !rules.isEmpty else { return ([:], poolCents, []) }
	var warnings: [String] = []
	let rawSum = rules.reduce(0.0) { $0 + max(0, $1.percentage) }
	if rawSum <= 0 { return ([:], poolCents, []) }
	var scale = 1.0
	if rawSum > 100 { scale = 100 / rawSum; warnings.append("Off-the-top total percentage exceeded 100%; clamped.") }
	var perID: [UUID: Int] = [:]
	var totalAllocated = 0
	for rule in rules {
		let adjustedPct = rule.percentage * scale
		guard adjustedPct > 0 else { continue }
		let roleMembers = participants.filter { $0.role.lowercased() == rule.role.lowercased() }
		if roleMembers.isEmpty { warnings.append("Off-the-top role \(rule.role) has no participants"); continue }
		let targetCents = Int(round(Double(poolCents) * adjustedPct / 100.0))
		guard targetCents > 0 else { continue }
		let rawEach = Double(targetCents) / Double(roleMembers.count)
		var base: [UUID: Int] = [:]
		var remainders: [UUID: Double] = [:]
		var floorSum = 0
		for member in roleMembers { let floor = Int(rawEach); base[member.id] = floor; floorSum += floor; remainders[member.id] = rawEach - Double(floor) }
		let remaining = targetCents - floorSum
		let ordered = orderForPennyDistribution(ids: roleMembers.map { $0.id }, remainders: remainders, participants: participants, context: .offTop)
		if remaining > 0 { for i in 0..<remaining { if let current = base[ordered[i]] { base[ordered[i]] = current + 1 } } }
		for (k,v) in base { perID[k, default: 0] += v }
		totalAllocated += targetCents
	}
	if totalAllocated > poolCents {
		let delta = totalAllocated - poolCents
		warnings.append("Off-the-top rounding overflow of \(delta) cents adjusted.")
		let ids = participants.sorted { $0.name.lowercased() < $1.name.lowercased() }.map { $0.id }
		var remaining = delta
		for id in ids.reversed() { if remaining > 0, let current = perID[id], current > 0 { perID[id] = current - 1; remaining -= 1 } }
		totalAllocated = poolCents
	}
	let remainder = max(0, poolCents - totalAllocated)
	return (perID, remainder, warnings)
}

private func allocateByRule(participants: [Participant], remainderCents: Int, rules: TipRules) -> (perID: [UUID: Int], warnings: [String]) {
	guard remainderCents > 0 else { return ([:], []) }
	switch rules.type {
	case .equal: return allocateEqual(participants: participants, remainderCents: remainderCents, ruleType: .equal)
	case .percentage: return allocatePercentage(participants: participants, remainderCents: remainderCents, rules: rules)
	case .hoursBased: return allocateHours(participants: participants, remainderCents: remainderCents)
	case .roleWeighted: return allocateRoleWeighted(participants: participants, remainderCents: remainderCents, rules: rules)
	case .hybrid: return allocateHybrid(participants: participants, remainderCents: remainderCents, rules: rules)
	}
}

private func allocateEqual(participants: [Participant], remainderCents: Int, ruleType: TipRules.RuleType) -> (perID: [UUID: Int], warnings: [String]) {
	let rawEach = Double(remainderCents) / Double(participants.count)
	var base: [UUID: Int] = [:]
	var remainders: [UUID: Double] = [:]
	var floorSum = 0
	for p in participants { let floor = Int(rawEach); base[p.id] = floor; floorSum += floor; remainders[p.id] = rawEach - Double(floor) }
	let remaining = remainderCents - floorSum
	let ordered = orderForPennyDistribution(ids: participants.map { $0.id }, remainders: remainders, participants: participants, context: .equal(ruleType))
	if remaining > 0 { for i in 0..<remaining { base[ordered[i], default: 0] += 1 } }
	return (base, [])
}

private func allocatePercentage(participants: [Participant], remainderCents: Int, rules: TipRules) -> (perID: [UUID: Int], warnings: [String]) {
	var warnings: [String] = []
	var weights: [UUID: Double] = [:]
	var usedRoleWeights = false
	let roleWeightsLower = rules.roleWeights?.reduce(into: [String: Double]()) { $0[$1.key.lowercased()] = $1.value }
	for p in participants { if let w = p.weight { weights[p.id] = max(0, w) } }
	if weights.isEmpty, let roleWeightsLower = roleWeightsLower { usedRoleWeights = true; for p in participants { weights[p.id] = max(0, roleWeightsLower[p.role.lowercased()] ?? 0) } }
	if weights.isEmpty { return allocateEqual(participants: participants, remainderCents: remainderCents, ruleType: .percentage) }
	let total = weights.values.reduce(0,+)
	if total <= 0 { return allocateEqual(participants: participants, remainderCents: remainderCents, ruleType: .percentage) }
	if usedRoleWeights, abs(total - 100) > weightNormalizationEpsilon { warnings.append("Role weights for percentage did not sum to 100; normalized.") }
	var raw: [UUID: Double] = [:]
	for (id, weight) in weights { raw[id] = Double(remainderCents) * (weight / total) }
	let (rounded, _) = finalizeRounding(raw: raw, targetTotal: remainderCents, participants: participants, context: .percentage)
	return (rounded, warnings)
}

private func allocateHours(participants: [Participant], remainderCents: Int) -> (perID: [UUID: Int], warnings: [String]) {
	var warnings: [String] = []
	var hourMap: [UUID: Double] = [:]
	for p in participants { hourMap[p.id] = max(0, p.hours ?? 0) }
	let totalHours = hourMap.values.reduce(0,+)
	if totalHours <= 0 { warnings.append("Total hours were zero; fell back to equal split."); return allocateEqual(participants: participants, remainderCents: remainderCents, ruleType: .hoursBased) }
	var raw: [UUID: Double] = [:]
	for (id, hours) in hourMap { raw[id] = Double(remainderCents) * (hours / totalHours) }
	let (rounded, _) = finalizeRounding(raw: raw, targetTotal: remainderCents, participants: participants, context: .hours)
	return (rounded, warnings)
}

private func allocateRoleWeighted(participants: [Participant], remainderCents: Int, rules: TipRules) -> (perID: [UUID: Int], warnings: [String]) {
	var warnings: [String] = []
	guard let roleWeights = rules.roleWeights, !roleWeights.isEmpty else { warnings.append("No roleWeights provided for roleWeighted; fell back to equal."); return allocateEqual(participants: participants, remainderCents: remainderCents, ruleType: .roleWeighted) }
	let roleWeightsLower = roleWeights.reduce(into: [String: Double]()) { $0[$1.key.lowercased()] = max(0,$1.value) }
	var validTotal = 0.0
	for (role, weight) in roleWeightsLower { if weight > 0 { if participants.contains(where: { $0.role.lowercased() == role }) { validTotal += weight } } }
	if validTotal <= 0 { warnings.append("All role weights invalid; fell back to equal."); return allocateEqual(participants: participants, remainderCents: remainderCents, ruleType: .roleWeighted) }
	if abs(validTotal - 100) > weightNormalizationEpsilon { warnings.append("Role weights did not sum to 100; normalized.") }
	var raw: [UUID: Double] = [:]
	for (role, weight) in roleWeightsLower where weight > 0 {
		let members = participants.filter { $0.role.lowercased() == role }
		if members.isEmpty { continue }
		let roleShare = Double(remainderCents) * (weight / validTotal)
		let each = roleShare / Double(members.count)
		for m in members { raw[m.id, default: 0] += each }
	}
	let (rounded, _) = finalizeRounding(raw: raw, targetTotal: remainderCents, participants: participants, context: .roleWeighted)
	return (rounded, warnings)
}

private func allocateHybrid(participants: [Participant], remainderCents: Int, rules: TipRules) -> (perID: [UUID: Int], warnings: [String]) {
	var warnings: [String] = []
	let parsed = parseHybridFormula(rules.formula)
	if parsed.isEmpty { warnings.append("Hybrid formula empty or invalid; fell back to equal."); return allocateEqual(participants: participants, remainderCents: remainderCents, ruleType: .hybrid) }
	var valid: [(String, Double, [Participant])] = []
	var totalPctValid = 0.0
	for (role, pct) in parsed {
		let members = participants.filter { $0.role.lowercased() == role }
		if members.isEmpty { warnings.append("Hybrid role \(role) has no participants"); continue }
		if pct > 0 { valid.append((role, pct, members)); totalPctValid += pct }
	}
	if totalPctValid <= 0 { warnings.append("Hybrid formula produced no valid roles; fell back to equal."); return allocateEqual(participants: participants, remainderCents: remainderCents, ruleType: .hybrid) }
	if abs(totalPctValid - 100) > weightNormalizationEpsilon { warnings.append("Hybrid role percentages did not sum to 100; normalized.") }
	var raw: [UUID: Double] = [:]
	for (_, pct, members) in valid {
		let roleShare = Double(remainderCents) * (pct / totalPctValid)
		let each = roleShare / Double(members.count)
		for m in members { raw[m.id, default: 0] += each }
	}
	let (rounded, _) = finalizeRounding(raw: raw, targetTotal: remainderCents, participants: participants, context: .hybrid)
	return (rounded, warnings)
}

private func parseHybridFormula(_ formula: String) -> [(String, Double)] {
	formula.split(separator: ",").compactMap { pair in
		let parts = pair.split(separator: ":"); guard parts.count == 2 else { return nil }
		let role = parts[0].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
		let pct = Double(parts[1].trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
		return (role, pct)
	}
}

// MARK: - Rounding

private enum RoundingContext { case offTop, equal(TipRules.RuleType), percentage, hours, roleWeighted, hybrid }

private func finalizeRounding(raw: [UUID: Double], targetTotal: Int, participants: [Participant], context: RoundingContext) -> ([UUID: Int], [UUID: Double]) {
	if raw.isEmpty { return ([:], [:]) }
	var scaledRaw = raw
	let rawSum = raw.values.reduce(0,+)
	if rawSum <= 0 { return ([:], [:]) }
	let scale = Double(targetTotal) / rawSum
	for (k,v) in raw { scaledRaw[k] = v * scale }
	var base: [UUID: Int] = [:]
	var remainders: [UUID: Double] = [:]
	var floorSum = 0
	for (id, value) in scaledRaw { let floor = Int(value); base[id] = floor; floorSum += floor; remainders[id] = value - Double(floor) }
	let remaining = targetTotal - floorSum
	if remaining > 0 {
		let ordered = orderForPennyDistribution(ids: Array(raw.keys), remainders: remainders, participants: participants, context: context)
		for i in 0..<remaining { base[ordered[i], default: 0] += 1 }
	}
	return (base, remainders)
}

private func combineAndFixPennies(offTop: [UUID: Int], main: [UUID: Int], targetTotal: Int, participants: [Participant]) -> [UUID: Int] {
	var combined = offTop
	for (k,v) in main { combined[k, default: 0] += v }
	let sum = combined.values.reduce(0,+)
	if sum == targetTotal { return combined }
	var delta = targetTotal - sum
	if delta == 0 { return combined }
	let ordered = participants.sorted { $0.name.lowercased() < $1.name.lowercased() }.map { $0.id }
	if delta > 0 { for id in ordered { if delta > 0 { combined[id, default: 0] += 1; delta -= 1 } } } else { for id in ordered.reversed() { if delta < 0, let current = combined[id], current > 0 { combined[id] = current - 1; delta += 1 } } }
	return combined
}

private func orderForPennyDistribution(ids: [UUID], remainders: [UUID: Double], participants: [Participant], context: RoundingContext) -> [UUID] {
	let participantMap = Dictionary(uniqueKeysWithValues: participants.map { ($0.id, $0) })
	let epsilon = 1e-9
	func tieBreak(_ a: Participant, _ b: Participant) -> Bool {
		switch context {
		case .offTop, .equal: if a.name.lowercased() != b.name.lowercased() { return a.name.lowercased() < b.name.lowercased() }; return a.id.uuidString < b.id.uuidString
		case .hours: let ha = a.hours ?? 0, hb = b.hours ?? 0; if abs(ha - hb) > epsilon { return ha > hb }; if a.name.lowercased() != b.name.lowercased() { return a.name.lowercased() < b.name.lowercased() }; return a.id.uuidString < b.id.uuidString
		case .percentage, .roleWeighted, .hybrid: let wa = a.weight ?? 0, wb = b.weight ?? 0; if abs(wa - wb) > epsilon { return wa > wb }; if a.name.lowercased() != b.name.lowercased() { return a.name.lowercased() < b.name.lowercased() }; return a.id.uuidString < b.id.uuidString
		}
	}
	return ids.sorted { lhs, rhs in
		let r1 = remainders[lhs] ?? 0, r2 = remainders[rhs] ?? 0
		if abs(r1 - r2) > epsilon { return r1 > r2 }
		guard let pa = participantMap[lhs], let pb = participantMap[rhs] else { return lhs.uuidString < rhs.uuidString }
		return tieBreak(pa, pb)
	}
}

// MARK: - Convenience

public func formatTemplateJSON(_ template: TipTemplate) -> String {
	let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; encoder.dateEncodingStrategy = .iso8601
	guard let data = try? encoder.encode(template), let json = String(data: data, encoding: .utf8) else { return "Unable to display template data" }
	return json
}
