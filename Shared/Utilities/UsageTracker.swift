import Foundation

struct UsageRecord: Codable {
    let date: String
    let provider: String
    var callCount: Int
    var inputTokens: Int
    var outputTokens: Int
    var estimatedCost: Double
}

final class UsageTracker {
    static let shared = UsageTracker()

    // Usage records are stored in UserDefaults.standard (local to each process).
    // The keyboard extension and main app track separately since App Group is removed.
    // Budget limit is shared via SharedSettings (Keychain-backed).
    private let defaults = UserDefaults.standard

    private init() {}

    // MARK: - Record Usage

    func recordCall(provider: String, inputText: String, outputText: String) {
        let inputTokens = estimateTokens(inputText)
        let outputTokens = estimateTokens(outputText)
        let rate = AppConstants.Pricing.rate(for: provider)
        let cost = (Double(inputTokens) * rate.inputPerMillion + Double(outputTokens) * rate.outputPerMillion) / 1_000_000.0

        let dateKey = todayString()
        var records = loadRecords()

        if let index = records.firstIndex(where: { $0.date == dateKey && $0.provider == provider }) {
            records[index].callCount += 1
            records[index].inputTokens += inputTokens
            records[index].outputTokens += outputTokens
            records[index].estimatedCost += cost
        } else {
            records.append(UsageRecord(
                date: dateKey,
                provider: provider,
                callCount: 1,
                inputTokens: inputTokens,
                outputTokens: outputTokens,
                estimatedCost: cost
            ))
        }

        // Keep only last 90 days
        let cutoff = Calendar.current.date(byAdding: .day, value: -90, to: Date())!
        let cutoffString = dateFormatter.string(from: cutoff)
        records = records.filter { $0.date >= cutoffString }

        saveRecords(records)
    }

    func lastCallCost(provider: String, inputText: String, outputText: String) -> Double {
        let inputTokens = estimateTokens(inputText)
        let outputTokens = estimateTokens(outputText)
        let rate = AppConstants.Pricing.rate(for: provider)
        return (Double(inputTokens) * rate.inputPerMillion + Double(outputTokens) * rate.outputPerMillion) / 1_000_000.0
    }

    // MARK: - Query Stats

    func todayStats() -> (calls: Int, cost: Double) {
        let today = todayString()
        let records = loadRecords().filter { $0.date == today }
        return (
            calls: records.reduce(0) { $0 + $1.callCount },
            cost: records.reduce(0.0) { $0 + $1.estimatedCost }
        )
    }

    func weekStats() -> (calls: Int, cost: Double) {
        let weekAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date())!
        let cutoff = dateFormatter.string(from: weekAgo)
        let records = loadRecords().filter { $0.date >= cutoff }
        return (
            calls: records.reduce(0) { $0 + $1.callCount },
            cost: records.reduce(0.0) { $0 + $1.estimatedCost }
        )
    }

    func monthStats() -> (calls: Int, cost: Double) {
        let monthAgo = Calendar.current.date(byAdding: .day, value: -30, to: Date())!
        let cutoff = dateFormatter.string(from: monthAgo)
        let records = loadRecords().filter { $0.date >= cutoff }
        return (
            calls: records.reduce(0) { $0 + $1.callCount },
            cost: records.reduce(0.0) { $0 + $1.estimatedCost }
        )
    }

    func allTimeStats() -> (calls: Int, cost: Double) {
        let records = loadRecords()
        return (
            calls: records.reduce(0) { $0 + $1.callCount },
            cost: records.reduce(0.0) { $0 + $1.estimatedCost }
        )
    }

    // MARK: - Budget

    var dailyBudget: Double? {
        get { SharedSettings.shared.dailyBudget }
        set { SharedSettings.shared.dailyBudget = newValue }
    }

    func budgetStatus() -> (used: Double, limit: Double, percent: Double)? {
        guard let limit = dailyBudget, limit > 0 else { return nil }
        let today = todayStats()
        let percent = today.cost / limit
        return (used: today.cost, limit: limit, percent: percent)
    }

    func isBudgetExceeded() -> Bool {
        guard let status = budgetStatus() else { return false }
        return status.percent >= 1.0
    }

    func isBudgetWarning() -> Bool {
        guard let status = budgetStatus() else { return false }
        return status.percent >= 0.8 && status.percent < 1.0
    }

    // MARK: - Helpers

    private func estimateTokens(_ text: String) -> Int {
        max(1, text.count / 4)
    }

    private let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private func todayString() -> String {
        dateFormatter.string(from: Date())
    }

    private let recordsKey = "usageRecords"

    private func loadRecords() -> [UsageRecord] {
        guard let data = defaults.data(forKey: recordsKey) else { return [] }
        return (try? JSONDecoder().decode([UsageRecord].self, from: data)) ?? []
    }

    private func saveRecords(_ records: [UsageRecord]) {
        if let data = try? JSONEncoder().encode(records) {
            defaults.set(data, forKey: recordsKey)
        }
    }
}
