import SuperflowDesignSystem
import SuperflowKernel
import SuperflowMeetingEngine
import SuperflowUIComponents
import SwiftUI

public struct PastMeetingsView: View {
    @ObservedObject private var model: PastMeetingsModel
    @State private var searchFocus = false
    @State private var selected: SessionID?
    @State private var expanded: SessionID?
    @State private var hovered: SessionID?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(model: PastMeetingsModel) { self.model = model }

    public var body: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            SearchField(text: $model.query, prompt: "Search meetings", isFocused: $searchFocus)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        if model.isLoading && model.sessions.isEmpty {
                            ProgressView().frame(maxWidth: .infinity).padding(Space.lg)
                        } else if model.sessions.isEmpty {
                            EmptyState(model.query.isEmpty ? "No meetings yet." : "No meetings match.",
                                       message: model.query.isEmpty ? "Hold right ⌘ or double-tap it to record." : "Clear the search to see your meetings.")
                        } else {
                            ForEach(model.groups) { group in
                                Text(Humanize.day(group.day)).appType(.caption).foregroundStyle(Tok.text2)
                                    .padding(.vertical, Space.sm)
                                ForEach(group.sessions) { session in
                                    row(session, proxy: proxy).id(session.id)
                                    Rectangle().fill(Tok.control).frame(height: 1)
                                }
                            }
                        }
                    }
                }
                .focusable().focusEffectDisabled()
                .onKeyPress(.upArrow) { move(-1, proxy: proxy); return .handled }
                .onKeyPress(.downArrow) { move(1, proxy: proxy); return .handled }
                .onKeyPress(.return) {
                    if let id = selected { toggle(id, proxy: proxy) }
                    return .handled
                }
                .onKeyPress(.escape) { expanded = nil; return .handled }
                .onKeyPress(keys: ["c"], phases: .down) { key in
                    guard key.modifiers.contains(.command), !key.modifiers.contains(.shift),
                          let id = selected, model.selectedID == id, let document = model.selectedDocument else { return .ignored }
                    Task { _ = await model.copyMarkdown(document) }
                    return .handled
                }
            }
        }
        .searchShortcut($searchFocus)
        .task(id: model.query) { await model.reload() }
        .overlay(alignment: .top) { if let error = model.error { NoticeBanner(error, tone: .rose) } }
    }

    private func row(_ session: SessionRecord, proxy: ScrollViewProxy) -> some View {
        let isExpanded = expanded == session.id
        let active = isExpanded || selected == session.id || hovered == session.id
        return VStack(alignment: .leading, spacing: 0) {
            if isExpanded {
                if model.selectedID == session.id, let document = model.selectedDocument {
                    MeetingDetail(model: model, document: document, proxy: proxy) { expanded = nil }
                        .padding(Space.sm).transition(.opacity)
                } else if model.selectedID == session.id, let error = model.documentError {
                    Text(error).appType(.body).foregroundStyle(Tok.text2).padding(Space.sm)
                } else {
                    ProgressView().padding(Space.sm)
                }
            } else {
                RowButton(session.displayTitle, radius: 0, hoverFill: .clear) {
                    selected = session.id
                    toggle(session.id, proxy: proxy)
                } content: {
                    VStack(alignment: .leading, spacing: Space.xs) {
                        HStack {
                            Text(session.displayTitle).appType(.label).foregroundStyle(Tok.text).lineLimit(1)
                            Spacer()
                            Text(Humanize.duration(Double(session.durationMs) / 1000)).appType(.caption)
                                .monospacedDigit().foregroundStyle(Tok.text2)
                        }
                        Text("\(Humanize.words(session.wordCount)) · \(Humanize.duration(Double(session.durationMs) / 1000))")
                            .appType(.caption).monospacedDigit().foregroundStyle(Tok.text2)
                        MeetingBarcode(turns: model.barcodes[session.id] ?? [], speakers: [],
                                       durationMs: session.durationMs, active: active)
                            .frame(maxWidth: 287, alignment: .leading).frame(height: 6)
                    }
                    .padding(Space.sm)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(active ? Tok.field : .clear)
        .onHover { hovered = $0 ? session.id : nil }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: hovered == session.id)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.22), value: isExpanded)
        .task { await model.loadBarcode(for: session.id) }
    }

    private func toggle(_ id: SessionID, proxy: ScrollViewProxy) {
        if expanded == id { expanded = nil; return }
        expanded = id
        Task { await model.select(id) }
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.22)) { proxy.scrollTo(id, anchor: .top) }
    }

    private func move(_ delta: Int, proxy: ScrollViewProxy) {
        let ids = model.groups.flatMap(\.sessions).map(\.id)
        guard !ids.isEmpty else { return }
        let index = selected.flatMap { ids.firstIndex(of: $0) } ?? (delta > 0 ? -1 : ids.count)
        let next = ids[min(max(index + delta, 0), ids.count - 1)]
        selected = next
        if expanded != next { expanded = nil }
        Task { await model.select(next) }
        proxy.scrollTo(next, anchor: .center)
    }
}
