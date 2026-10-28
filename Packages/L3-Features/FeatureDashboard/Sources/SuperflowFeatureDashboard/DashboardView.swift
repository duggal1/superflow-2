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
                latest
                    .revealOnce(2, seen: model.hasAppeared)
                if model.insights.hasData {
                    lowerHalf
                        .revealOnce(3, seen: model.hasAppeared)
                }
            }
        }
        .task { await model.load() }
        .onDisappear { model.markAppeared() }
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

    /// The newest dictation, with the archived clip and the cleanup line. This is
    /// the component directly under the 12-month graph.
    private var latest: some View {
        LatestDictationCard(sample: model.insights.latest ?? .example,
                            audio: model.latestAudioURL,
                            isExample: model.insights.latest == nil,
                            fnHeld: model.isFnHeld)
    }

    /// Both cards take the taller one's height, which comes from their content: no
    /// fixed row height, and no dead third of either card.
    private var lowerHalf: some View {
        HStack(alignment: .top, spacing: Space.md) {
            AppsCard(apps: model.insights.topApps)
                .frame(maxWidth: .infinity)
            HoursCard(hours: model.insights.hourly)
                .frame(width: 320)
        }
        .fixedSize(horizontal: false, vertical: true)
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
