import Foundation

public enum ReasoningEffort: String, CaseIterable, Sendable {
    case low, medium, high, xhigh

    public var deeper: Self? {
        switch self {
        case .low: .medium
        case .medium: .high
        case .high: .xhigh
        case .xhigh: nil
        }
    }

    var maxCompletionTokens: Int {
        switch self {
        case .low: 1_500
        case .medium: 3_000
        case .high: 8_000
        case .xhigh: 14_000
        }
    }
}

public struct ReflectionUsage: Decodable, Sendable, Equatable {
    public let promptTokens: Int
    public let completionTokens: Int
    public let totalTokens: Int

    enum CodingKeys: String, CodingKey {
        case promptTokens = "prompt_tokens", completionTokens = "completion_tokens", totalTokens = "total_tokens"
    }
}

public enum ReflectionEvent: Sendable, Equatable {
    case thinking
    case text(String)
    case finished(reason: String, usage: ReflectionUsage?)
}

public enum ReflectionError: LocalizedError {
    case http(Int), api, incomplete, invalidResponse

    public var errorDescription: String? {
        switch self {
        case .http(let status): "Request failed (\(status))."
        case .api: "Reflection reported a stream error."
        case .incomplete: "Connection dropped before the answer finished."
        case .invalidResponse: "Reflection returned an invalid response."
        }
    }
}

public struct ReflectionClient: Sendable {
    private let apiKey: String
    private let baseURL: URL
    private let session: URLSession

    public init(apiKey: String, baseURL: URL, session: URLSession = .shared) {
        self.apiKey = apiKey
        self.baseURL = baseURL
        self.session = session
    }

    public func stream(system: String, user: String, effort: ReasoningEffort) -> AsyncThrowingStream<ReflectionEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var request = URLRequest(url: baseURL.appending(path: "chat/completions"))
                    request.httpMethod = "POST"
                    request.timeoutInterval = 90
                    request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.httpBody = try JSONEncoder().encode(Request(system: system, user: user, effort: effort))
                    let (bytes, response) = try await session.bytes(for: request)
                    guard let http = response as? HTTPURLResponse else { throw ReflectionError.invalidResponse }
                    guard http.statusCode == 200 else { throw ReflectionError.http(http.statusCode) }
                    var parser = ReflectionStreamParser()
                    for try await line in bytes.lines {
                        try Task.checkCancellation()
                        for event in try parser.consume(line) { continuation.yield(event) }
                        if parser.done { break }
                    }
                    try parser.validateCompletion()
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

private struct Request: Encodable {
    struct Message: Encodable { let role: String; let content: String }
    struct StreamOptions: Encodable { let include_usage = true }
    let model = "Beam-1.0-501B-A23B"
    let messages: [Message]
    let stream = true
    let stream_options = StreamOptions()
    let reasoning_effort: String
    let max_completion_tokens: Int
    let temperature = 0.7
    let top_p = 0.99

    init(system: String, user: String, effort: ReasoningEffort) {
        messages = [Message(role: "system", content: system), Message(role: "user", content: user)]
        reasoning_effort = effort.rawValue
        max_completion_tokens = effort.maxCompletionTokens
    }
}
