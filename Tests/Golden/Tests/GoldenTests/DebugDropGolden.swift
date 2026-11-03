import XCTest
import SuperflowKernel
import SuperflowPorts
import SuperflowTestKit
import SuperflowTextCleanup
@testable import SuperflowGoldenTests

final class DebugDropGolden: XCTestCase {
    func testDebug() async throws {
        let fixture = try Golden.load("cleanup/cases.json") as CleanupFixture
        let config = fixture.config?.config() ?? CleanupConfig()
        for c in fixture.cases where c.name == "dropped tail falls back" {
            let service = CleanupService(cleaner: c.behavior.cleaner(), config: config)
            var settings = Golden.stageSettings()
            settings.cleanupEnabled = true
            let out = await service.clean(c.input, context: TextContext(settings: settings))
            print("STATE=\(out.state) TEXT=\(out.text) CHUNKS=\(out.chunks.count)")
        }
    }
}
