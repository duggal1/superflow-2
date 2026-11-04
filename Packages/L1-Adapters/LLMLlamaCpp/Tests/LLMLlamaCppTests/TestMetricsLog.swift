import os

enum TestMetricsLog {
    private static let logger = Logger(subsystem: "com.superflow.tests", category: "performance")

    static func record(_ message: String) {
        logger.info("\(message, privacy: .public)")
    }
}
