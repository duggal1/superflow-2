# Expected backend API — Knowledge front end → Agent 5 (knowledge-back)

Owner: Agent 4 (front end). Consumer: Agent 5 (Dictionary/Shortcuts packages + SQLite store).
This is the **contract the front end compiles against**. Keep these declarations source-compatible.
I will re-read `.proof/knowledge-back/provided-backend-api.md` if it appears and adapt my views to
the real API; until then this file is the source of truth for the seam.

Last checked against the working tree at `51ebf0f` (all signatures below already exist and compile).

## 1. Targets and modules

| Module | Note |
|---|---|
| `SuperflowFeatureDictionary` | `DictionaryViewModel`, `TermDialog` |
| `SuperflowFeatureShortcuts` | `ShortcutsViewModel`, `ShortcutDialog` |
| `SuperflowKernel` | `LexiconEntry`, `LexiconKind`, `EntrySource`, `ShortcutEntry`, `ShortcutMatch`, `LearningCandidate`, `LearningState` |
| `SuperflowTextPipeline` | `DictionaryLearningEngine` |
| `SuperflowUIComponents` | `ToastCenter`, `Toast` (owned by UI, do not change for this task) |

## 2. `DictionaryViewModel` (`@MainActor`, `ObservableObject`)

```swift
@MainActor public final class DictionaryViewModel: ObservableObject {
    @Published public private(set) var entries: [LexiconEntry]
    @Published public private(set) var isLoading: Bool
    @Published public private(set) var error: String?
    @Published public var query: String
    @Published public var filter: LexiconFilter
    public let toast: ToastCenter

    public var visibleEntries: [LexiconEntry] { get }
    public var userEntryCount: Int { get }
    public var isEmpty: Bool { get }

    public func load() async
    public func draft(for entry: LexiconEntry) -> LexiconDraft
    public func issues(for draft: LexiconDraft) -> [LexiconIssue]
    @discardableResult public func save(_ draft: LexiconDraft) async -> Bool
    public func toggle(_ entry: LexiconEntry) async
    public func delete(_ entry: LexiconEntry) async
    public func undoDelete() async
    public func exportData() -> Data?
    public func importData(_ data: Data) async -> LexiconImportResult
}
public enum LexiconFilter: String, CaseIterable, Sendable { case all, terms, corrections }
```

Front-end usage: `visibleEntries`, `entries`, `isLoading`, `error`, `query`, `toast`, `load()`,
`save(_:)`, `delete(_:)`, `exportData()`, `importData(_:)`. `toggle(_:)`, `draft(for:)`, `issues(for:)`
and `filter` are used by the dialogs and must stay.

## 3. `ShortcutsViewModel` (`@MainActor`, `ObservableObject`)

```swift
@MainActor public final class ShortcutsViewModel: ObservableObject {
    @Published public private(set) var entries: [ShortcutEntry]
    @Published public private(set) var isLoading: Bool
    @Published public private(set) var error: String?
    @Published public var query: String
    @Published public var filter: ShortcutFilter
    public let toast: ToastCenter

    public var visibleEntries: [ShortcutEntry] { get }
    public var isEmpty: Bool { get }

    public func load() async
    public func draft(for entry: ShortcutEntry) -> ShortcutDraft
    public func issues(for draft: ShortcutDraft) -> [ShortcutIssue]
    @discardableResult public func save(_ draft: ShortcutDraft) async -> Bool
    public func toggle(_ entry: ShortcutEntry) async
    public func delete(_ entry: ShortcutEntry) async
    public func undoDelete() async
    public func preview(_ utterance: String, using candidates: [ShortcutEntry]? = nil) async -> String
    public func exportData() -> Data?
    public func importData(_ data: Data) async -> ShortcutImportResult
}
public enum ShortcutFilter: String, CaseIterable, Sendable { case all, wholeUtterance, inline }
```

Front-end usage: `visibleEntries`, `entries`, `isLoading`, `error`, `query`, `toast`, `load()`,
`save(_:)`, `delete(_:)`, `exportData()`, `importData(_:)`.

## 4. Model fields the front end reads (must not be renamed/removed)

```swift
public struct LexiconEntry: Sendable, Codable, Hashable, Identifiable {
    public var id: String
    public var kind: LexiconKind            // .term | .correction
    public var triggers: [String]
    public var canonical: String
    public var enabled: Bool
    public var source: EntrySource          // .user | .bundled
    public var appScope: String?            // nil = all apps
    // remaining optional metadata fields may change but must stay optional
}
public enum LexiconKind: String, Sendable, Codable, CaseIterable { case term, correction }
public enum EntrySource: String, Sendable, Codable { case user, bundled }

public struct ShortcutEntry: Sendable, Codable, Hashable, Identifiable {
    public var id: String
    public var trigger: String
    public var content: String              // may be long Markdown
    public var match: ShortcutMatch         // .wholeUtterance | .inline
    public var enabled: Bool
}
public enum ShortcutMatch: String, Sendable, Codable, CaseIterable { case wholeUtterance, inline }

public struct LearningCandidate: Identifiable, Codable, Sendable, Equatable {
    public var id: String
    public var heard: String
    public var canonical: String
    public var appScope: String?
    public var confidence: Double
    public var observations: Int
    public var state: LearningState          // .suggested | .confirmed | .rejected
}
public enum LearningState: String, Codable, Sendable { case suggested, confirmed, rejected }
```

`ShortcutEntry.content` is **byte-for-byte** on expansion; the front end only ever shows a
single-line derived preview (`content.components(separatedBy: .newlines).first`), clamped with an
edge fade. Do not pre-truncate it in the model.

## 5. `DictionaryLearningEngine` (`SuperflowTextPipeline`) — used by KnowledgeView and the router

```swift
public func candidates() async throws -> [LearningCandidate]
public func confirm(id: String) async throws -> String
public func reject(id: String) async throws
public func undo(id: String) async throws
// actor-isolated but synchronous; callers use `await learning.setOnApplied { ... }`
public func setOnApplied(_ callback: @escaping @Sendable (LearningCandidate, Bool) async -> Void)
@discardableResult public func observe(_ observation: ObservedCorrection, consent: Bool,
                                       autoPromote: Bool = false) async throws -> LearningCandidate?
```

Semantics required by the front end:
- `confirm(id:)` performs **both** SQLite writes (candidate state + lexicon rule) before it returns;
  only then does `setOnApplied` fire with `active = true`. The router's undo notice depends on it.
- `reject(id:)` and `undo(id:)` are idempotent enough to be called once per user action; failures throw.
- `candidates()` returns all non-expired candidates including `.confirmed`/`.rejected`; the front end
  filters by state. Empty array is the honest "no suggestions" state.

## 6. `KnowledgeNoticeRouter` (front-end owned, AppCore) — wiring expectation

```swift
@MainActor final class KnowledgeNoticeRouter {
    init(learning: DictionaryLearningEngine, island: IslandModel)
    func applied(_ candidate: LearningCandidate, active: Bool)
    func handle(_ notice: IslandNotice)
}
```

`IslandNotice(kind: .knowledge, title: "Added to Knowledge", detail: "\(heard) → \(canonical)",
action: "Undo")` is the exact shape the existing `KnowledgeNoticeRouterTests` asserts. Do not change
the notice kind/title/detail/action strings. The router's Undo path calls `learning.undo(id:)` and
re-queues the notice when that write fails.

## 7. Error states the front end renders

- Load failure → view model's `error: String?` set; **never thrown** out of `load()`. Front end shows
  an inline `NoticeBanner`-equivalent via `toast` and keeps the empty state honest.
- Save/import/delete failure → `toast.show(_:style:)` with `.error`/`.warning`; boolean returns stay
  `false` on invalid drafts.
- `isLoading` is true only during a fetch; `isEmpty` stays false while loading so the "Reading…"
  state is not replaced by a false empty state.
- Import results (`LexiconImportResult`, `ShortcutImportResult`) keep `imported`, `skipped`,
  `warnings`, `summary` so the front end can show the toast the view model already produces.

## 8. Explicit "do not change" list for Agent 5

1. Do not change the `@Published` property names or their `private(set)` exposure above.
2. Do not make `load()`, `save(_:)`, `delete(_:)` or `importData(_:)` throwing; keep their current return types.
3. Do not rename `visibleEntries` (the front end filters/sorts on it in `KnowledgeView`).
4. Do not pre-clamp or truncate `ShortcutEntry.content`.
5. Do not change the strings asserted in `KnowledgeNoticeRouterTests`.
6. Do not edit `KnowledgeView.swift`, `KnowledgeNoticeRouter.swift`, or `FeatureHistory/**` — Agent 4 owns them.

## 9. Adaptation to the real API (read 2026-11-18)

`.proof/knowledge-back/provided-backend-api.md` appeared and was read in full. It preserves every
signature above and adds `search(_:)`, `exportPlainText()`, `importPlainText(_:)` and SQLite FTS
methods. **No source change was needed in my views**: I keep `visibleEntries` for display and JSON
import/export (the additive plain-text surface is out of scope for this task). The only correction
to this contract was the exact `setOnApplied` signature, now fixed in §5 to match the actor.
