import Foundation

struct ReflectionStreamParser {
    private(set) var done = false
    private var thinking = false
    private var finishReason: String?
    private var usage: ReflectionUsage?

    mutating func consume(_ line: String) throws -> [ReflectionEvent] {
        guard !done, line.hasPrefix("data:") else { return [] }
        let data = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
        if data == "[DONE]" {
            guard let finishReason else { throw ReflectionError.incomplete }
            done = true
            return [.finished(reason: finishReason, usage: usage)]
        }
        let chunk: Chunk
        do { chunk = try JSONDecoder().decode(Chunk.self, from: Data(data.utf8)) }
        catch { throw ReflectionError.invalidResponse }
        if chunk.error != nil { throw ReflectionError.api }
        if let received = chunk.usage { usage = received }
        guard let choice = chunk.choices?.first else { return [] }
        var events: [ReflectionEvent] = []
        if let reasoning = choice.delta?.reasoningContent, !reasoning.isEmpty, !thinking {
            thinking = true
            events.append(.thinking)
        }
        if let content = choice.delta?.content, !content.isEmpty { events.append(.text(content)) }
        if let reason = choice.finishReason { finishReason = reason }
        return events
    }

    func validateCompletion() throws {
        guard done else { throw ReflectionError.incomplete }
    }
}

private struct Chunk: Decodable {
    struct Choice: Decodable {
        struct Delta: Decodable {
            let content: String?
            let reasoningContent: String?
            enum CodingKeys: String, CodingKey { case content; case reasoningContent = "reasoning_content" }
        }
        let delta: Delta?
        let finishReason: String?
        enum CodingKeys: String, CodingKey { case delta; case finishReason = "finish_reason" }
    }
    struct APIError: Decodable {}
    let choices: [Choice]?
    let usage: ReflectionUsage?
    let error: APIError?
}
