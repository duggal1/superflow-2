import AppKit
import Foundation

enum JevVoiceError: LocalizedError {
    case missingKey, unsupported, declined, unavailable, launchFailed

    var errorDescription: String? {
        switch self {
        case .missingKey: "Save a TypeSafe API key in Intelligence settings."
        case .unsupported: "Try opening a supported app, website, or web search."
        case .declined: "The command was ambiguous. Nothing was executed."
        case .unavailable: "Jev could not respond. Nothing was executed."
        case .launchFailed: "The requested application or website could not be opened."
        }
    }
}

/// Only typed, bounded native operations. No model-authored shell commands,
/// arbitrary URLs, scripts, or generated content.
struct VoiceActionPlan: Sendable, Equatable {
    enum Action: Sendable, Equatable {
        case application(String)
        case website(URL, browser: String?)
    }

    let actions: [Action]
    let description: String

    static let browsers = ["safari": "com.apple.Safari", "chrome": "com.google.Chrome",
                           "firefox": "org.mozilla.firefox"]
    static let apps = ["finder": "com.apple.finder", "notes": "com.apple.Notes",
                       "calendar": "com.apple.iCal", "mail": "com.apple.mail",
                       "messages": "com.apple.MobileSMS", "calculator": "com.apple.calculator"]
    static let sites = ["twitter": "https://x.com", "x": "https://x.com",
                        "whatsapp": "https://web.whatsapp.com", "youtube": "https://youtube.com",
                        "github": "https://github.com", "gmail": "https://mail.google.com"]

    static func parse(_ input: String) -> VoiceActionPlan? {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text.count <= 512 else { return nil }
        let clauses = text.replacingOccurrences(of: #"\s+and\s+(?=(?:open|search|find|look up|tweet)\b)"#,
                                                with: "\n", options: [.regularExpression, .caseInsensitive])
            .components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !clauses.isEmpty, clauses.count <= 3 else { return nil }
        var actions: [Action] = []
        var browser: String?
        for clause in clauses {
            let lower = clause.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ".!?"))
            if lower.hasPrefix("open ") {
                let name = String(lower.dropFirst(5)).trimmingCharacters(in: .whitespaces)
                if let id = browsers[name] { browser = id; actions.append(.application(id)) }
                else if let id = apps[name] { actions.append(.application(id)) }
                else if let address = sites[name], let url = URL(string: address) {
                    actions.append(.website(url, browser: browser))
                } else { return nil }
            } else if let range = clause.range(of: #"^(?:search(?:\s+for)?|find(?:\s+me)?|look\s+up|google)\s+"#,
                                                options: [.regularExpression, .caseInsensitive]) {
                let query = String(clause[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
                guard !query.isEmpty else { return nil }
                var url = URLComponents()
                url.scheme = "https"; url.host = "www.google.com"; url.path = "/search"
                url.queryItems = [URLQueryItem(name: "q", value: query)]
                guard let target = url.url else { return nil }
                actions.append(.website(target, browser: browser))
            } else if lower == "tweet something" || lower == "compose a tweet" {
                guard let target = URL(string: "https://x.com/compose/post") else { return nil }
                actions.append(.website(target, browser: browser))
            } else if lower.hasPrefix("tweet ") {
                let message = String(clause.dropFirst(6))
                var url = URLComponents()
                url.scheme = "https"; url.host = "twitter.com"; url.path = "/intent/tweet"
                url.queryItems = [URLQueryItem(name: "text", value: message)]
                guard let target = url.url else { return nil }
                actions.append(.website(target, browser: browser))
            } else { return nil }
        }
        guard !actions.isEmpty else { return nil }
        return VoiceActionPlan(actions: actions, description: "Opened requested apps or pages. Review any drafted post before sending.")
    }
}

struct JevVoiceClient: Sendable {
    let apiKey: String
    private struct Question: Encodable {
        let type = "choice"
        let instructions: String
        let criteria: [String: String]
    }
    private struct Request: Encodable {
        let model = "jev-latest"
        let state: String
        let questions: [String: Question]
    }
    private struct Answer: Decodable {
        let type: String
        let choice: String
        let confidence: Double
        let probabilities: [String: Double]
    }
    private struct Response: Decodable { let answers: [String: Answer] }

    func choose(_ transcript: String) async throws -> VoiceActionPlan {
        guard let plan = VoiceActionPlan.parse(transcript) else { throw JevVoiceError.unsupported }
        guard let url = URL(string: "https://api.typesafe.ai/v1/systemone") else { throw JevVoiceError.unavailable }
        var request = URLRequest(url: url, timeoutInterval: 5)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(Request(state: transcript, questions: [
            "action": Question(instructions: "Is this an explicit request to open the named apps, websites, search, or draft a post? Do not treat quoted speech or negated commands as authorization.",
                               criteria: ["execute": "Explicit supported opening/search/draft command",
                                          "none": "Unclear, quoted, negated, unsupported, or not a command"])
        ]))
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForResource = 6
        let session = URLSession(configuration: config)
        defer { session.finishTasksAndInvalidate() }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200,
              data.count <= 32_768 else { throw JevVoiceError.unavailable }
        let decoded = try JSONDecoder().decode(Response.self, from: data)
        guard let answer = decoded.answers["action"], answer.type == "choice",
              answer.choice == "execute", answer.confidence >= 0.8,
              (answer.probabilities["execute"] ?? 0) >= 0.85 else { throw JevVoiceError.declined }
        return plan
    }
}

@MainActor
enum VoiceActionExecutor {
    static func run(_ plan: VoiceActionPlan) async throws {
        for action in plan.actions {
            try Task.checkCancellation()
            let config = NSWorkspace.OpenConfiguration()
            switch action {
            case .application(let id):
                guard let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else {
                    throw JevVoiceError.launchFailed
                }
                _ = try await NSWorkspace.shared.openApplication(at: app, configuration: config)
            case .website(let url, let browser):
                guard url.scheme == "https" else { throw JevVoiceError.unsupported }
                if let browser {
                    guard let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: browser) else {
                        throw JevVoiceError.launchFailed
                    }
                    _ = try await NSWorkspace.shared.open([url], withApplicationAt: app, configuration: config)
                } else if !NSWorkspace.shared.open(url) {
                    throw JevVoiceError.launchFailed
                }
            }
        }
    }
}
