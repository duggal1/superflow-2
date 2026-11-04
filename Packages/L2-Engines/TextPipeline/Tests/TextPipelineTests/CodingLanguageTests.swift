import XCTest
import SuperflowKernel
@testable import SuperflowTextPipeline

final class CodingLanguageTests: XCTestCase {
    func testExplicitFilenamesAndExtensions() {
        let cases: [(String, String)] = [
            ("agents dot md", "AGENTS.md"),
            ("architecture dot md", "architecture.md"),
            ("design dot md", "design.md"),
            ("readme dot md", "README.md"),
            ("package dot json", "package.json"),
            ("status dot swift", "status.swift"),
            ("config dot yaml", "config.yaml"),
            ("main dot tsx", "main.tsx"),
            ("open the agents dot md file", "open the AGENTS.md file"),
        ]
        for (input, expected) in cases {
            XCTAssertEqual(CodingLanguageNormalizer.normalize(input).text, expected, input)
        }
    }

    func testGitCommandsNeverAddUnspokenArguments() {
        let cases: [(String, String)] = [
            ("get add", "git add"),
            ("get commit", "git commit"),
            ("get push", "git push"),
            ("get merge main", "git merge main"),
            ("get checkout main", "git checkout main"),
            ("get remote v", "git remote -v"),
            ("git remote v", "git remote -v"),
            ("get add dot", "git add ."),
            ("git add dot", "git add ."),
            ("git push origin main", "git push origin main"),
            ("git commit", "git commit"),
        ]
        for (input, expected) in cases {
            XCTAssertEqual(CodingLanguageNormalizer.normalize(input).text, expected, input)
        }
    }

    func testOrdinaryGetAndProtectedTextStayLiteral() {
        for input in [
            "please get me a coffee",
            "get additional details",
            "I need to get ready for work",
            "it is a dot on my shirt",
            "my file is at https://example.com/agents dot md",
        ] {
            XCTAssertEqual(CodingLanguageNormalizer.normalize(input).text, input, input)
        }
        let protected = Protected(literals: ["agents dot md"])
        XCTAssertEqual(CodingLanguageNormalizer.normalize("read agents dot md", protected: protected).text,
                       "read agents dot md")
    }

    func testNoShellExecutionAndIdempotence() {
        let once = CodingLanguageNormalizer.normalize("get add dot and get push").text
        XCTAssertEqual(once, "git add . and git push")
        XCTAssertEqual(CodingLanguageNormalizer.normalize(once).text, once)
    }
}
