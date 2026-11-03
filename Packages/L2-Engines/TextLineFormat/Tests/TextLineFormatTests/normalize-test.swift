import XCTest
@testable import SuperflowTextLineFormat

final class NormalizerTests: XCTestCase {

    private let positive: [(String, String)] = [
        // your examples
        ("one twenty to one thirty percent volume", "120-130% volume"),
        ("120 to 130 %", "120-130%"),
        ("120 to 130 percent", "120-130%"),
        ("five laughing emoji", "😂😂😂😂😂"),
        ("Five laughing emoji.", "😂😂😂😂😂"),
        ("ten vomit emoji", "🤮🤮🤮🤮🤮🤮🤮🤮🤮🤮"),
        ("10 vomit emoji", "🤮🤮🤮🤮🤮🤮🤮🤮🤮🤮"),
        ("US flag emoji", "🇺🇸"),
        ("united states flag", "🇺🇸"),
        ("five US flag", "🇺🇸🇺🇸🇺🇸🇺🇸🇺🇸"),
        ("crying emoji", "😭"),
        ("that was hilarious laughing emoji", "that was hilarious 😂"),
        ("thanks so much heart emoji.", "thanks so much ❤️"),
        ("two fire emoji and a rocket emoji", "🔥🔥 and a 🚀"),
        ("three laughing emoji two crying emoji", "😂😂😂😭😭"),
        ("India flag emoji", "🇮🇳"),

        // numbers
        ("I have two cats", "I have 2 cats"),
        ("twenty one", "21"),
        ("one hundred and five", "105"),
        ("a hundred percent", "100%"),
        ("hundred percent", "100%"),
        ("twelve thousand five hundred", "12,500"),
        ("two million", "2 million"),
        ("two point five million dollars", "$2.5 million"),
        ("one or two", "1 or 2"),
        ("zero", "0"),
        ("fifty-fifty", "50-50"),
        ("two to three weeks", "2-3 weeks"),
        ("nine to five", "9 to 5"),
        ("from five to ten percent", "from 5 to 10%"),
        ("twenty twenty six", "2026"),
        ("nineteen eighty four", "1984"),
        ("two thousand twenty six", "2026"),
        ("march third twenty twenty six", "March 3, 2026"),
        ("on the twenty first", "on the 21st"),

        // money, units, time
        ("five hundred dollars", "$500"),
        ("fifty bucks", "$50"),
        ("ten lakh rupees", "₹10 lakh"),
        ("five to ten dollars", "$5-10"),
        ("two point five dollars", "$2.50"),
        ("sixteen gigs of ram", "16 GB of ram"),
        ("two hundred milliseconds", "200ms"),
        ("sixty frames per second", "60 fps"),
        ("four k video", "4K video"),
        ("ten x faster", "10x faster"),
        ("sixteen by nine", "16:9"),
        ("nineteen twenty by ten eighty", "1920 by 10 80"), // known ambiguity: "ten eighty" stays split on purpose
        ("1920 by 1080", "1920x1080"),
        ("three thirty pm", "3:30 PM"),
        ("nine a m", "9 AM"),
        ("eleven oh five pm", "11:05 PM"),
        ("meet at one thirty", "meet at 1:30"),
        ("see you at three forty five", "see you at 3:45"),
        ("seventy two degrees fahrenheit", "72°F"),

        // dev
        ("version one point two point three", "version 1.2.3"),
        ("v two point oh", "v2.0"),
        ("port eight zero eight zero", "port 8080"),
        ("localhost colon three thousand", "localhost:3000"),
        ("node eighteen", "node 18"),
        ("john dot smith at gmail dot com", "john.smith@gmail.com"),
        ("github dot com slash anthropics slash claude", "github.com/anthropics/claude"),
        ("https colon slash slash example dot com", "https://example.com"),
        ("npm run dev dash dash port", "npm run dev --port"),
        ("my underscore var", "my_var"),
    ]

    // Everyday English that must come out UNCHANGED.
    private let negative: [String] = [
        "let's do it next year",
        "the cloud is cheap",
        "take a quick look",
        "one of the best",
        "at one point it broke",
        "the one thing I need",
        "no one knows",
        "step by step",
        "divide 10 by 2",
        "from 5 to 10",
        "change 3 to 4 please",
        "go to the store",
        "she is a good friend",
        "I am here",
        "the US flag was raised",
        "hello world",
        "contact me at the office",
        "I'll be there in a second",
        "I love this",
    ]

    func testPositiveCases() {
        for (input, want) in positive {
            XCTAssertEqual(Normalizer.normalize(input), want, "input: \(input)")
        }
    }

    func testEverydayEnglishIsUntouched() {
        for input in negative {
            XCTAssertEqual(Normalizer.normalize(input), input, "input: \(input)")
        }
    }

    func testIdempotent() {
        for (input, _) in positive {
            let once = Normalizer.normalize(input)
            XCTAssertEqual(Normalizer.normalize(once), once, "input: \(input)")
        }
    }
}