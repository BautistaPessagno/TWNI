import SwiftUI
import SwiftData
import Charts

struct StatsView: View {
    @Query(sort: \ScreenSession.startDate, order: .reverse)
    private var sessions: [ScreenSession]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    TodaySummaryCard(summary: todaySummary)
                    WeeklyScreenTimeChart(dailySummaries: weekSummaries)
                    BreaksChart(dailySummaries: weekSummaries)
                }
                .padding()
            }
            .navigationTitle("Statistics")
        }
    }

    // MARK: - Computed

    private var todaySummary: DailySummary {
        summaryForDate(Date())
    }

    private var weekSummaries: [DailySummary] {
        let calendar = Calendar.current
        return (0..<7).reversed().compactMap { daysAgo in
            guard let date = calendar.date(byAdding: .day, value: -daysAgo, to: Date()) else {
                return nil
            }
            return summaryForDate(date)
        }
    }

    private func summaryForDate(_ date: Date) -> DailySummary {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) ?? startOfDay

        let daySessions = sessions.filter {
            $0.startDate >= startOfDay && $0.startDate < endOfDay
        }

        let totalSeconds = daySessions.reduce(0) { $0 + $1.durationSeconds }
        let allBreaks = daySessions.flatMap(\.breaks)
        let taken = allBreaks.filter(\.completed).count
        let skipped = allBreaks.filter { !$0.completed }.count

        return DailySummary(
            id: startOfDay,
            date: startOfDay,
            totalScreenTimeSeconds: totalSeconds,
            sessionsCount: daySessions.count,
            breaksTaken: taken,
            breaksSkipped: skipped
        )
    }
}

// MARK: - Today Summary Card

private struct TodaySummaryCard: View {
    let summary: DailySummary

    var body: some View {
        VStack(spacing: 16) {
            Text("Today")
                .font(.headline)
                .foregroundStyle(Color.monoPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 20) {
                SummaryMetric(
                    title: "Screen Time",
                    value: summary.totalScreenTimeFormatted,
                    icon: "desktopcomputer",
                    valueWeight: .heavy
                )

                SummaryMetric(
                    title: "Sessions",
                    value: "\(summary.sessionsCount)",
                    icon: "clock",
                    valueWeight: .bold
                )

                SummaryMetric(
                    title: "Breaks",
                    value: "\(summary.breaksTaken)/\(summary.breaksTaken + summary.breaksSkipped)",
                    icon: "eye",
                    valueWeight: .medium
                )

                SummaryMetric(
                    title: "Score",
                    value: "\(Int(summary.completionRate * 100))%",
                    icon: "star.fill",
                    valueWeight: .semibold
                )
            }
        }
        .padding()
        .monochromeCard()
    }
}

private struct SummaryMetric: View {
    let title: String
    let value: String
    let icon: String
    var valueWeight: Font.Weight = .bold

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(Color.monoSecondary)
            Text(value)
                .font(.headline)
                .fontWeight(valueWeight)
                .foregroundStyle(Color.monoPrimary)
            Text(title)
                .font(.caption2)
                .foregroundStyle(Color.monoTertiary)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Weekly Screen Time Chart

private struct WeeklyScreenTimeChart: View {
    let dailySummaries: [DailySummary]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Screen Time")
                .font(.headline)
                .foregroundStyle(Color.monoPrimary)

            Chart(dailySummaries) { summary in
                BarMark(
                    x: .value("Day", summary.date.shortDayName),
                    y: .value("Minutes", summary.totalScreenTimeSeconds / 60)
                )
                .foregroundStyle(
                    .linearGradient(
                        colors: [Color.monoPrimary, Color.monoSecondary],
                        startPoint: .bottom,
                        endPoint: .top
                    )
                )
                .clipShape(RoundedRectangle(cornerRadius: 4))
            }
            .chartYAxisLabel("Minutes")
            .frame(height: 200)
        }
        .padding()
        .monochromeCard()
    }
}

// MARK: - Breaks Chart

private struct BreaksChart: View {
    let dailySummaries: [DailySummary]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Breaks")
                .font(.headline)
                .foregroundStyle(Color.monoPrimary)

            Chart(dailySummaries) { summary in
                BarMark(
                    x: .value("Day", summary.date.shortDayName),
                    y: .value("Count", summary.breaksTaken)
                )
                .foregroundStyle(Color.monoPrimary)
                .position(by: .value("Type", "Taken"))

                BarMark(
                    x: .value("Day", summary.date.shortDayName),
                    y: .value("Count", summary.breaksSkipped)
                )
                .foregroundStyle(Color.monoSecondary.opacity(0.6))
                .position(by: .value("Type", "Skipped"))
            }
            .chartForegroundStyleScale([
                "Taken": Color.monoPrimary,
                "Skipped": Color.monoSecondary.opacity(0.6)
            ])
            .frame(height: 200)
        }
        .padding()
        .monochromeCard()
    }
}
