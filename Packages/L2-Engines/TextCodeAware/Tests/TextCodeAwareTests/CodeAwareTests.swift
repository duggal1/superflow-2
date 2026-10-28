import XCTest
import SuperflowKernel
import SuperflowPorts
@testable import SuperflowTextCodeAware

final class CodeAwareTests: XCTestCase {
    private let root = FileManager.default.temporaryDirectory.appendingPathComponent("code-aware-root")

    private func project(coding: Bool = true,
                         paths: [String] = [
                            "lib/backend/",
                            "lib/backend/main/engine/router/prospect-main-engine.ts",
                            "src/main.ts",
                            "src/other/main.ts",
                            "src/other/unique-widget.tsx",
                         ]) -> ProjectContext {
        ProjectContext(root: root, paths: paths, isCoding: coding, approvedByUser: true)
    }

    private func run(_ input: String, project: ProjectContext? = nil, coding: Bool = true,
                     protected: Protected = Protected()) async -> String {
        var settings = AppSettings.default
        settings.codeSpeakEnabled = coding
        let stage = CodeAwareStage(project: project)
        return await stage.apply(TranscriptDraft(text: input, protected: protected),
                                 context: TextContext(settings: settings, project: project)).text
    }

    func testSpokenExtensionsBecomeFilenames() async {
        let cases: [(String, String)] = [
            ("hero dot t s x", "hero.tsx"),
            ("config dot json", "config.json"),
            ("prospect main engine dot t s", "prospect-main-engine.ts"),
            ("hero.tsx", "hero.tsx"),
        ]
        for (input, expected) in cases {
            let actual = await run(input)
            XCTAssertEqual(actual, expected, "input: \(input)")
        }
    }

    func testBareExtensionOnlyInCodingSessions() async {
        let bare = await run("hero tsx")
        XCTAssertEqual(bare, "hero.tsx")
        let punctuated = await run("config json.")
        XCTAssertEqual(punctuated, "config.json.")
        let prose = await run("hero tsx", coding: false)
        XCTAssertEqual(prose, "hero tsx")
    }

    func testBareExtensionDoesNotRewriteProse() async {
        let plural = await run("renders tsx files")
        XCTAssertEqual(plural, "renders tsx files")
        let article = await run("the tsx market")
        XCTAssertEqual(article, "the tsx market")
        let ordinary = await run("read the file now")
        XCTAssertEqual(ordinary, "read the file now")
    }

    func testFilenameSlugNeedsAnExplicitFileCue() async {
        let withCue = await run("the file prospect main engine")
        XCTAssertEqual(withCue, "the file prospect-main-engine")
        let withoutCue = await run("prospect main engine")
        XCTAssertEqual(withoutCue, "prospect main engine")
    }

    func testProjectPathsResolveWhenUnique() async {
        let context = project()
        let file = await run("fix prospect main engine", project: context)
        XCTAssertEqual(file, "fix lib/backend/main/engine/router/prospect-main-engine.ts")
        let directory = await run("go to lib backend folder", project: context)
        XCTAssertEqual(directory, "go to lib/backend/")
        let separated = await run("open src slash main", project: context)
        XCTAssertEqual(separated, "open src/main.ts")
        let component = await run("open unique widget", project: context)
        XCTAssertEqual(component, "open src/other/unique-widget.tsx")
    }

    func testAmbiguousOrCommonPathsAreLeftAlone() async {
        let context = project()
        let common = await run("open main", project: context)
        XCTAssertEqual(common, "open main")
        let ambiguous = await run("open src", project: context)
        XCTAssertEqual(ambiguous, "open src")
        let missing = await run("fix missing thing", project: context)
        XCTAssertEqual(missing, "fix missing thing")
        let extensionWord = await run("renders tsx files", project: context)
        XCTAssertEqual(extensionWord, "renders tsx files")
    }

    func testNoRootMeansNoPathResolution() async {
        let context = project()
        let noRoot = await run("fix prospect main engine", project: nil)
        XCTAssertEqual(noRoot, "fix prospect main engine")
        let filenameWithoutRoot = await run("hero dot t s x", project: nil)
        XCTAssertEqual(filenameWithoutRoot, "hero.tsx")
        let filenameWithRoot = await run("hero dot t s x", project: context)
        XCTAssertEqual(filenameWithRoot, "hero.tsx")
    }

    func testStageSeesARefreshedIndexAtTheSameRoot() async {
        let stage = CodeAwareStage()
        var settings = AppSettings.default
        settings.codeSpeakEnabled = true
        let first = project(paths: ["src/alpha.ts"])
        let second = project(paths: ["src/beta.ts"])
        let firstResult = await stage.apply(
            TranscriptDraft(text: "open alpha"),
            context: TextContext(settings: settings, project: first))
        XCTAssertEqual(firstResult.text, "open src/alpha.ts")
        let secondResult = await stage.apply(
            TranscriptDraft(text: "open beta"),
            context: TextContext(settings: settings, project: second))
        XCTAssertEqual(secondResult.text, "open src/beta.ts",
                       "the cache must not keep the previous index when the root and count match")
    }

    func testPropertyOrdinaryProseIsNeverRewritten() async {
        var state: UInt64 = 0xC0DE
        func next(_ bound: Int) -> Int {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Int((state >> 33) % UInt64(bound))
        }
        let vocabulary = ["the", "quick", "brown", "fox", "jumps", "over", "lazy",
                          "dog", "we", "need", "to", "check", "this", "is", "fine"]
        let context = project()
        for _ in 0..<250 {
            let count = 1 + next(14)
            let words = (0..<count).map { _ in vocabulary[next(vocabulary.count)] }
            let input = words.joined(separator: " ")
            let actual = await run(input, project: context)
            XCTAssertEqual(actual, input, "rewrote ordinary prose: \(input)")
        }
    }

    func testPropertyFilenameRewritesAreIdempotent() async {
        var state: UInt64 = 0xBEEF
        func next(_ bound: Int) -> Int {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Int((state >> 33) % UInt64(bound))
        }
        let stems = ["hero", "prospect", "config", "unique", "widget", "engine"]
        let endings = ["dot t s x", "dot json", "dot swift", "tsx", "json"]
        let context = project()
        for _ in 0..<100 {
            let stem = stems[next(stems.count)]
            let ending = endings[next(endings.count)]
            let input = "\(stem) \(ending)"
            let once = await run(input, project: context)
            let twice = await run(once, project: context)
            XCTAssertEqual(twice, once, "not idempotent: \(input) -> \(once)")
            XCTAssertEqual(once.filter { $0 == "\n" }.count, input.filter { $0 == "\n" }.count,
                           "changed line structure: \(input)")
        }
    }

    func testPathTraversalIsDroppedFromTheIndex() {
        let context = ProjectContext(root: root,
                                     paths: ["../etc/passwd", "/etc/passwd", "lib/../../etc/passwd",
                                             "src/main.ts", "src/main.ts"],
                                     isCoding: true)
        XCTAssertEqual(context.paths, ["src/main.ts"])
        XCTAssertFalse(context.contains(relative: "../etc/passwd"))
        XCTAssertTrue(context.contains(relative: "src/main.ts"))
    }

    func testProtectedSpansAreNeverTouched() async {
        let protected = Protected(literals: ["prospect main engine", "hero dot t s x"])
        let context = project()
        let path = await run("fix prospect main engine", project: context, protected: protected)
        XCTAssertEqual(path, "fix prospect main engine")
        let filename = await run("hero dot t s x", project: context, protected: protected)
        XCTAssertEqual(filename, "hero dot t s x")
    }

    func testEmptyAndIdempotent() async {
        let context = project()
        let empty = await run("", project: context)
        XCTAssertEqual(empty, "")
        let whitespace = await run("   \n\t\n", project: context)
        XCTAssertEqual(whitespace, "   \n\t\n")
        let inputs = [
            "hero dot t s x",
            "fix prospect main engine",
            "go to lib backend folder",
            "the file prospect main engine",
            "renders tsx files",
            "open src slash main",
        ]
        for input in inputs {
            let once = await run(input, project: context)
            let twice = await run(once, project: context)
            XCTAssertEqual(once, twice, "input: \(input)")
        }
    }

    func testExplainNamesTheRule() async {
        let context = project()
        let stage = CodeAwareStage(project: context)
        let before = TranscriptDraft(text: "hero dot t s x and fix prospect main engine")
        let after = await stage.apply(before, context: TextContext(settings: AppSettings.default,
                                                                   project: context))
        let edits = await stage.explainEdits(before: before, after: after,
                                             context: TextContext(settings: AppSettings.default,
                                                                  project: context))
        XCTAssertEqual(edits?.map(\.ruleID), ["filename.extension", "path.project"])
        let input = before.text as NSString
        XCTAssertEqual(input.substring(with: edits![1].input.nsRange), "prospect main engine")
    }

    func testProjectContextBoundsTheIndex() {
        let paths = (0..<6_000).map { "src/file\($0).ts" }
        let context = ProjectContext(root: root, paths: paths, isCoding: true)
        XCTAssertEqual(context.paths.count, ProjectContext.pathLimit)
    }
}
