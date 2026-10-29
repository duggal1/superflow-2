import SuperflowDesignSystem
import SuperflowUIComponents
import SwiftUI

public struct DashboardView: View {
    @ObservedObject private var model: DashboardViewModel
    private let openHistory: () -> Void

    public init(model: DashboardViewModel, openHistory: @escaping () -> Void = {}) {
        self.model = model
        self.openHistory = openHistory
    }

    public var body: some View {
        Page(title: model.greeting, subtitle: model.subtitle) {
            if let error = model.error {
                NoticeBanner(error, tone: .rose)
                    .revealOnce(0, seen: model.hasAppeared)
            }

            if model.isLoading && model.activity.isEmpty {
                Text("Reading your library…")
                    .appType(.body)
                    .foregroundStyle(Tok.text2)
                    .revealOnce(0, seen: model.hasAppeared)
            } else {
                ledger
                    .revealOnce(0, seen: model.hasAppeared)
                graph
                    .revealOnce(1, seen: model.hasAppeared)
                RecentTranscripts(model: model.recent, openHistory: openHistory)
                    .revealOnce(2, seen: model.hasAppeared)
                lowerHalf
                    .revealOnce(3, seen: model.hasAppeared)
            }
        }
        .task { await model.load() }
        .onChange(of: model.usageRange) { _, _ in Task { await model.loadUsage() } }
        .onDisappear { model.recent.stopPlayback(); model.markAppeared() }
    }

    /// Four equal columns that fill the card. Label and number only: the note
    /// under each number repeated what the number already said, and the ledger
    /// now reads in one pass.
    private var ledger: some View {
        Card {
            HStack(alignment: .top, spacing: Space.lg) {
                Metric("Words", value: model.words, glyph: .words)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Metric("Time saved", value: model.timeSaved, glyph: .timeSaved)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Metric("Average speed", value: model.speed, glyph: .speed)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Metric("Day streak", value: model.streak, glyph: .streak)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    /// The title and the canvas are one component: `ActivityYear` already draws
    /// "Last 12 months" and its readout line, so the page adds no second header.
    private var graph: some View {
        ActivityYear(days: model.activity, animatesIn: !model.hasAppeared)
    }

    /// Both cards take the taller one's height, which comes from their content: no
    /// fixed row height, and no dead third of either card.
    private var usageCard: some View {
        UsageCard(usage: model.usage.isEmpty ? AppUsage.examples : model.usage,
                  range: $model.usageRange, isExample: model.usage.isEmpty,
                  animatesIn: !model.hasAppeared)
    }

    private var lowerHalf: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: Space.md) {
                usageCard.frame(minWidth: 420)
                HoursCard(hours: model.insights.hourly).frame(width: 320)
            }
            VStack(alignment: .leading, spacing: Space.md) {
                usageCard
                HoursCard(hours: model.insights.hourly)
            }
        }
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
