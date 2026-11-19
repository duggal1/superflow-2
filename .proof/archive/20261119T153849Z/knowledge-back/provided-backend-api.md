# Provided back-end API — knowledge surface (Agent 5 → Agent 4)

Peer handshake. This is the **stable public API** the knowledge back end
exposes. All existing signatures are preserved (no breaking changes); new
capabilities are additive. Agent 4 may consume any of it from
`KnowledgeView.swift` / `KnowledgeNoticeRouter.swift`.

Ownership: `FeatureDictionary`, `FeatureShortcuts`, `DictionaryLearningEngine`,
the knowledge files of `StorageSQLite`. Kernel port types (`LexiconEntry`,
`ShortcutEntry`, `LearningCandidate`, `LibraryRepository`, `LearningRepository`)
are unchanged and remain the shared currency.

---

## 1. `DictionaryViewModel` — `SuperflowFeatureDictionary`, `@MainActor`, `ObservableObject`

Existing (unchanged):
```swift
init(repository: any LibraryRepository,
     toast: ToastCenter = ToastCenter(),
     onChange: (@MainActor () -> Void)? = nil)

@Published private(set) var entries: [LexiconEntry]
@Published private(set) var isLoading: Bool
@Published private(set) var error: String?      // honest load error, nil when healthy
@Published var query: String
@Published var filter: LexiconFilter            // .all | .terms | .corrections
let toast: ToastCenter

var visibleEntries: [LexiconEntry] { get }      // filter + full-text query + deterministic sort
var userEntryCount: Int { get }
var isEmpty: Bool { get }

func load() async
func draft(for entry: LexiconEntry) -> LexiconDraft
func issues(for draft: LexiconDraft) -> [LexiconIssue]
@discardableResult func save(_ draft: LexiconDraft) async -> Bool
func toggle(_ entry: LexiconEntry) async
func delete(_ entry: LexiconEntry) async
func undoDelete() async
func exportData() -> Data?                       // JSON document, versioned
func importData(_ data: Data) async -> LexiconImportResult
```

Additive (new):
```swift
/// Full-text search over the loaded lexicon: tokenised, multi-term (AND),
/// unicode/case/diacritic-insensitive, ranked by match quality then
/// deterministic (enabled desc, canonical case-insensitive asc, id asc).
func search(_ query: String) -> [LexiconEntry]

/// Deterministic plain-text export (UTF-8, CRLF-free). One entry per line:
///   # comments start with '#'
///   trigger1, trigger2 => canonical
/// Multiple triggers are comma-separated; '=>' separates triggers from form.
/// Literal '\', ',' in a trigger and '=>' in canonical are escaped.
func exportPlainText() -> String

/// Plain-text import. Skips blank/comment/malformed lines; reports counts and
/// the same collision/common-word warnings as JSON import. Idempotent by id.
func importPlainText(_ text: String) async -> LexiconImportResult
```

## 2. `ShortcutsViewModel` — `SuperflowFeatureShortcuts`, `@MainActor`, `ObservableObject`

Existing (unchanged):
```swift
init(repository: any LibraryRepository,
     toast: ToastCenter = ToastCenter(),
     onChange: (@MainActor () -> Void)? = nil)

@Published private(set) var entries: [ShortcutEntry]
@Published private(set) var isLoading: Bool
@Published private(set) var error: String?
@Published var query: String
@Published var filter: ShortcutFilter             // .all | .wholeUtterance | .inline
let toast: ToastCenter

var visibleEntries: [ShortcutEntry] { get }
var isEmpty: Bool { get }

func load() async
func draft(for entry: ShortcutEntry) -> ShortcutDraft
func issues(for draft: ShortcutDraft) -> [ShortcutIssue]
@discardableResult func save(_ draft: ShortcutDraft) async -> Bool
func toggle(_ entry: ShortcutEntry) async
func delete(_ entry: ShortcutEntry) async
func undoDelete() async
func preview(_ utterance: String, using candidates: [ShortcutEntry]? = nil) async -> String
func exportData() -> Data?
func importData(_ data: Data) async -> ShortcutImportResult
```

Additive (new):
```swift
/// Full-text search over trigger + content; same ranking/order rules as above.
func search(_ query: String) -> [ShortcutEntry]

/// Deterministic plain text: one shortcut per line
///   trigger => match | content
/// `match` is `wholeUtterance` or `inline`; content newlines are `\n` escaped.
func exportPlainText() -> String
func importPlainText(_ text: String) async -> ShortcutImportResult
```

## 3. `DictionaryLearningEngine` — `SuperflowTextPipeline`, `actor`

Existing (unchanged, all public):
```swift
init(learning: any LearningRepository, lexicon: any LibraryRepository)
func setOnApplied(_ callback: @escaping @Sendable (LearningCandidate, Bool) async -> Void)

func candidates() async throws -> [LearningCandidate]   // ordered by updatedAt desc
@discardableResult func observe(_ observation: ObservedCorrection, consent: Bool,
                                autoPromote: Bool = false) async throws -> LearningCandidate?
func confirm(id: String) async throws -> String           // commits a real lexicon rule
func reject(id: String) async throws
func undo(id: String) async throws

enum DictionaryLearningError: Error, Sendable {
    case candidateNotFound, rejected, conflictingCorrection
}
```
Semantics already implemented and now covered by real-DB tests: consent gating,
anchor de-dup, phrase safety, observation counting, auto-promote only on
high-similarity repeats, reject never rewrites speech, undo never deletes a
manual rule, all states persist and reload after restart.

## 4. `SQLiteStore` knowledge APIs — `SuperflowStorageSQLite`, `actor`

Conforms to the unchanged `LibraryRepository` + `LearningRepository` ports.
CRUD is idempotent (`UPSERT` by id), serialized by the actor, and atomic with
its FTS index (base row + FTS row change in one `BEGIN IMMEDIATE` transaction).

Additive public methods (real SQLite FTS5, safe against hostile queries):
```swift
func searchLexicon(query: String, limit: Int = 200) async throws -> [LexiconEntry]
func searchShortcuts(query: String, limit: Int = 200) async throws -> [ShortcutEntry]
```
Deterministic SQL ordering is enforced in `lexicon()` / `shortcuts()` and in
the search methods (enabled desc, canonical/trigger asc, id asc as tiebreak).

## 5. Documents & results (unchanged public shapes)

`LexiconDocument`, `ShortcutDocument` (`version`, `entries`, `encoded()`,
`decode(_:)`), `LexiconImportResult`/`ShortcutImportResult` (`imported`,
`skipped`, `warnings`, `summary`), validation types, `LexiconIssue`,
`ShortcutIssue`, `LexiconKind`, `ShortcutMatch`, `EntrySource`, `LexiconFilter`,
`ShortcutFilter`.

---

## Error-state contract
- `load()` sets `error` (non-nil, human-readable) on repository failure; never
  silently keeps stale data.
- Every mutating VM action returns a Bool or shows a toast; failures never
  mutate local state.
- SQLite failures surface as `SQLiteError` with `LocalizedError` description;
  disk-full is detected explicitly.
- Import reports `skipped`/`warnings` instead of throwing on per-row data errors;
  malformed files produce an error toast and a zero result.

## Notes for Agent 4
- Keep using `visibleEntries` for display (now truly full-text + deterministic).
- `query` on the VM feeds `visibleEntries`; `search(_:)` is available when you
  need an explicit ranked result set.
- Plain-text import/export are additive; JSON remains the default in menus.
- No new module dependencies were added to any feature package.
