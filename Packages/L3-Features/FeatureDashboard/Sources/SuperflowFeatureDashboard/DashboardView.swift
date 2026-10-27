import SuperflowDesignSystem
import SuperflowUIComponents
import SwiftUI

public struct DashboardView: View {
    @ObservedObject private var model: DashboardViewModel

    public init(model: DashboardViewModel) {
        self.model = model
    }

    public var body: some View {
        Page(title: model.greeting, subtitle: model.subtitle) {
            if let error = model.error {
                NoticeBanner(error, tone: .rose)
                    .revealOnce(0, seen: model.hasAppeared)
            }

            if model.isLoading && model.contributions.isEmpty {
                Text("Reading your library…")
                    .font(Typography.body)
                    .foregroundStyle(Tok.text2)
                    .revealOnce(0, seen: model.hasAppeared)
            } else {
                ledger
                    .revealOnce(0, seen: model.hasAppeared)
                graph
                    .revealOnce(1, seen: model.hasAppeared)
                if model.insights.hasData {
                    lowerHalf
                        .revealOnce(2, seen: model.hasAppeared)
                    CleanupCard(mode: model.insights.latest.map(CleanupCard.Mode.latest) ?? .example)
                        .revealOnce(3, seen: model.hasAppeared)
                } else {
                    CleanupCard(mode: .example)
                        .revealOnce(2, seen: model.hasAppeared)
                }
            }
        }
        .task { await model.load() }
        .onDisappear { model.markAppeared() }
    }

    /// Four equal columns that fill the card, so no third of it sits empty.
    private var ledger: some View {
        Card {
            HStack(alignment: .top, spacing: Space.lg) {
                Metric("Words", value: model.words, note: model.sessionsNote, glyph: .words)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Metric("Time saved", value: model.timeSaved, note: "estimate", glyph: .timeSaved)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Metric("Average speed", value: model.speed, note: "speaking time only", glyph: .speed)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Metric("Day streak", value: model.streak, note: model.todayNote, glyph: .streak)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var graph: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            SectionHeader("Last 12 months", note: "Dictation words per day")
            ContributionGrid(model.contributions, animateReveal: !model.hasAppeared)
        }
    }

    /// Both cards take the taller one's height; the row is fixed, not hug-height.
    private var lowerHalf: some View {
        HStack(alignment: .top, spacing: Space.md) {
            AppsCard(apps: model.insights.topApps)
                .frame(maxWidth: .infinity)
            HoursCard(hours: model.insights.hourly)
                .frame(width: 320)
        }
        .frame(height: 320, alignment: .top)
    }
}

private extension View {
    @ViewBuilder
    func revealOnce(_ index: Int, seen: Bool) -> some View {
        if seen {
            self
        } else {
            reveal(index)
        }
    }
}
