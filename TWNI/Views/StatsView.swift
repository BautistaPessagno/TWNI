import SwiftUI
import Charts

/// Progress: streaks, the week's Break Scores, breaks and screen time.
struct StatsView: View {
    var timerManager: TimerManager

    private var days: [DaySummary] { timerManager.lastSevenDays }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    StreakSummary(timerManager: timerManager)
                    ScoreChart(days: days, timerManager: timerManager)
                    BreaksChart(days: days)
                    ScreenTimeChart(days: days)
                }
                .padding()
                .frame(maxWidth: 640)
                .frame(maxWidth: .infinity)
            }
            .background(Color.monoSurface)
            .navigationTitle("Progress")
        }
    }
}

private func weekdayLabel(_ date: Date) -> String {
    date.formatted(.dateTime.weekday(.abbreviated))
}

// MARK: - Streak

private struct StreakSummary: View {
    var timerManager: TimerManager

    var body: some View {
        HStack(spacing: 0) {
            metric(value: "\(timerManager.currentStreak)", label: "Current streak", icon: "flame.fill")
            metric(value: "\(timerManager.bestStreak)", label: "Best streak", icon: "trophy")
            metric(value: "\(timerManager.lifetimeCompleted)", label: "Eye breaks", icon: "eye")
        }
        .padding(.vertical, 20)
        .monochromeCard(cornerRadius: 20)
    }

    private func metric(value: String, label: String, icon: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(Color.monoSecondary)
                .accessibilityHidden(true)
            Text(value)
                .font(.title.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(Color.monoPrimary)
            Text(label)
                .font(.caption.weight(.medium))
                .foregroundStyle(Color.monoSecondary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Charts

private struct ChartCard<Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(Color.monoPrimary)
                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(Color.monoSecondary)
            }
            content
                .frame(height: 180)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .monochromeCard(cornerRadius: 20)
    }
}

private struct ScoreChart: View {
    let days: [DaySummary]
    var timerManager: TimerManager

    var body: some View {
        ChartCard(title: "Break Score", subtitle: "Dashed line: your daily goal") {
            Chart {
                ForEach(days, id: \.day) { day in
                    if let score = timerManager.score(for: day) {
                        BarMark(
                            x: .value("Day", weekdayLabel(day.day)),
                            y: .value("Score", score)
                        )
                        .foregroundStyle(Color.monoPrimary)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                }
                RuleMark(y: .value("Goal", timerManager.dailyGoal))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .foregroundStyle(Color.monoSecondary)
            }
            .chartYScale(domain: 0...100)
            .chartXScale(domain: days.map { weekdayLabel($0.day) })
        }
    }
}

private struct BreaksChart: View {
    let days: [DaySummary]

    private struct Entry: Identifiable {
        let id = UUID()
        let day: String
        let kind: String
        let count: Int
    }

    private var entries: [Entry] {
        days.flatMap { day -> [Entry] in
            let label = weekdayLabel(day.day)
            return [
                Entry(day: label, kind: "Rested", count: day.rests),
                Entry(day: label, kind: "Skipped", count: day.skipped),
                Entry(day: label, kind: "Missed", count: day.missed),
            ]
        }
    }

    var body: some View {
        ChartCard(title: "Breaks", subtitle: "Rested includes stepping away on your own") {
            Chart(entries) { entry in
                BarMark(
                    x: .value("Day", entry.day),
                    y: .value("Breaks", entry.count)
                )
                .foregroundStyle(by: .value("Type", entry.kind))
            }
            .chartForegroundStyleScale([
                "Rested": Color.monoPrimary,
                "Skipped": Color.monoSecondary,
                "Missed": Color.monoBorder,
            ])
            .chartLegend(position: .bottom, alignment: .leading)
            .chartXScale(domain: days.map { weekdayLabel($0.day) })
        }
    }
}

private struct ScreenTimeChart: View {
    let days: [DaySummary]

    private var subtitle: String {
        #if os(macOS)
        "Time you were actively using this Mac"
        #else
        "Time inside screen sessions"
        #endif
    }

    var body: some View {
        ChartCard(title: "Screen time", subtitle: subtitle) {
            Chart(days, id: \.day) { day in
                BarMark(
                    x: .value("Day", weekdayLabel(day.day)),
                    y: .value("Minutes", Int(day.screenSeconds / 60))
                )
                .foregroundStyle(Color.monoSecondary)
                .clipShape(RoundedRectangle(cornerRadius: 4))
            }
            .chartYAxisLabel("Minutes")
            .chartXScale(domain: days.map { weekdayLabel($0.day) })
        }
    }
}
