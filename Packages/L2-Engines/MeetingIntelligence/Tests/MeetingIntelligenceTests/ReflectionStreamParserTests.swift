import XCTest
@testable import SuperflowMeetingIntelligence

final class ReflectionStreamParserTests: XCTestCase {
    func testReasoningTextUsageAndCompletion() throws {
        var parser = ReflectionStreamParser()
        XCTAssertEqual(try parser.consume(": keepalive"), [])
        XCTAssertEqual(try parser.consume(#"data: {"choices":[{"delta":{"reasoning_content":"private"}}]}"#), [.thinking])
        XCTAssertEqual(try parser.consume(#"data: {"choices":[{"delta":{"reasoning_content":"more","content":"answer"}}]}"#), [.text("answer")])
        XCTAssertEqual(try parser.consume(#"data: {"choices":[{"delta":{},"finish_reason":"length"}]}"#), [])
        XCTAssertEqual(try parser.consume(#"data: {"choices":[],"usage":{"prompt_tokens":1,"completion_tokens":2,"total_tokens":3}}"#), [])
        XCTAssertEqual(try parser.consume("data: [DONE]"), [.finished(reason: "length", usage: ReflectionUsage(promptTokens: 1, completionTokens: 2, totalTokens: 3))])
        XCTAssertNoThrow(try parser.validateCompletion())
    }

    func testIncompleteAndErrorStreamsFail() throws {
        var parser = ReflectionStreamParser()
        _ = try parser.consume(#"data: {"choices":[{"delta":{"content":"partial"}}]}"#)
        XCTAssertThrowsError(try parser.validateCompletion())
        XCTAssertThrowsError(try parser.consume(#"data: {"error":{"message":"private"}}"#))
        XCTAssertThrowsError(try parser.consume("data: [DONE]"))
    }
}
