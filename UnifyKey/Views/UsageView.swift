import SwiftUI

struct UsageView: View {
    @State private var todayStats = (calls: 0, cost: 0.0)
    @State private var weekStats = (calls: 0, cost: 0.0)
    @State private var monthStats = (calls: 0, cost: 0.0)
    @State private var allTimeStats = (calls: 0, cost: 0.0)
    @State private var budgetText: String = ""
    @State private var showCostPerTranslation: Bool = false

    private let tracker = UsageTracker.shared
    private let settings = SharedSettings.shared

    var body: some View {
        Section {
            usageRow("Today", stats: todayStats)
            usageRow("This week", stats: weekStats)
            usageRow("This month", stats: monthStats)
            usageRow("All time", stats: allTimeStats)
        } header: {
            Text("Usage & Cost")
        }

        Section {
            HStack {
                Text("Daily budget")
                Spacer()
                TextField("No limit", text: $budgetText)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 80)
                    .onChange(of: budgetText) {
                        if let val = Double(budgetText), val > 0 {
                            tracker.dailyBudget = val
                        } else if budgetText.isEmpty {
                            tracker.dailyBudget = nil
                        }
                    }
            }

            if let status = tracker.budgetStatus() {
                HStack {
                    Text("Today's usage")
                    Spacer()
                    Text("\(Int(status.percent * 100))%")
                        .foregroundStyle(budgetColor(status.percent))
                        .fontWeight(.medium)
                }

                ProgressView(value: min(status.percent, 1.0))
                    .tint(budgetColor(status.percent))
            }

            Toggle("Show cost in keyboard", isOn: $showCostPerTranslation)
                .onChange(of: showCostPerTranslation) {
                    settings.showCostPerTranslation = showCostPerTranslation
                }
        } header: {
            Text("Budget")
        } footer: {
            Text("Set a daily spending limit. Translations pause when the limit is reached.")
        }
    }

    private func usageRow(_ label: String, stats: (calls: Int, cost: Double)) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text("\(stats.calls) translations")
                .foregroundStyle(.secondary)
                .font(.subheadline)
            Text("~$\(stats.cost, specifier: "%.4f")")
                .font(.subheadline)
                .fontWeight(.medium)
                .monospacedDigit()
        }
    }

    private func budgetColor(_ percent: Double) -> Color {
        if percent >= 1.0 { return .red }
        if percent >= 0.8 { return .orange }
        return .green
    }

    func refreshStats() -> UsageView {
        var view = self
        view._todayStats = State(initialValue: tracker.todayStats())
        view._weekStats = State(initialValue: tracker.weekStats())
        view._monthStats = State(initialValue: tracker.monthStats())
        view._allTimeStats = State(initialValue: tracker.allTimeStats())

        let budget = tracker.dailyBudget
        view._budgetText = State(initialValue: budget != nil ? String(format: "%.2f", budget!) : "")
        view._showCostPerTranslation = State(initialValue: SharedSettings.shared.showCostPerTranslation)

        return view
    }
}
