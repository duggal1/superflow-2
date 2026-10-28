import Foundation
import SuperflowKernel
import SuperflowTextCodeSpeak

/// One dropdown replaces the three block steppers. The Standard row is today's
/// values; Short and Long are placeholders for the owner to tune.
enum BlockLength: String, CaseIterable, Hashable, Sendable {
    case short, standard, long

    var title: String {
        switch self {
        case .short: "Short"
        case .standard: "Standard"
        case .long: "Long"
        }
    }

    /// Words below which a paragraph break is refused, the preferred maximum,
    /// and the hard maximum.
    var values: (min: Int, preferred: Int, hard: Int) {
        switch self {
        case .short: (15, 25, 35)
        case .standard: (25, 35, 45)
        case .long: (40, 60, 80)
        }
    }
}

extension SettingsViewModel {
    /// Maps the dropdown onto the three existing line-format properties.
    var blockLength: BlockLength {
        get {
            BlockLength.allCases.first {
                $0.values == (settings.lineFormat.minWords,
                              settings.lineFormat.preferredMax,
                              settings.lineFormat.hardMax)
            } ?? .standard
        }
        set {
            let values = newValue.values
            settings.lineFormat.minWords = values.min
            settings.lineFormat.preferredMax = values.preferred
            settings.lineFormat.hardMax = values.hard
        }
    }

    /// The real Code Speak stage, bounded so a pasted document cannot rebuild on
    /// every keystroke.
    func codeSpeakPreview(_ input: String) -> String {
        let bounded = String(input.prefix(4_000))
        return CodeSpeakRewriter.rewrite(bounded, protected: Protected()).text
    }

    static var audioRetentionOptions: [Int?] { [1, 7, 30, nil] }

    static func audioRetentionLabel(for days: Int?) -> String {
        guard let days else { return "Keep forever" }
        return days == 1 ? "After 1 day" : "After \(days) days"
    }

    static var codeSpeakCommands: [(say: String, types: String)] { [
        ("camel case user profile", "userProfile"),
        ("snake case user profile", "user_profile"),
        ("pascal case user profile", "UserProfile"),
        ("src slash main dot ts", "src/main.ts"),
        ("dash dash dry run", "--dry-run"),
        ("open bracket x close bracket", "[x]"),
        ("fat arrow", "=>"),
    ] }
}
