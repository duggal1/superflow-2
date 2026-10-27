import Foundation
import SuperflowKernel
import SuperflowPorts
import SuperflowTestKit
import XCTest

final class StorageContractTests: XCTestCase {
    func testTranscriptRepositoryContractAgainstInMemoryFake() async throws {
        try await TranscriptRepositoryContract().verify(InMemoryRepository())
    }

    func testSettingsStoreContractAgainstInMemoryFake() async throws {
        try await SettingsStoreContract().verify(InMemorySettings())
    }

    func testModelProviderContractWhenModelsAreMissing() async throws {
        try await ModelProviderContract().verify(FakeModelProvider())
    }

    func testModelProviderContractWhenModelsExist() async throws {
        let asr = URL(fileURLWithPath: "/tmp/contract-asr")
        let llm = URL(fileURLWithPath: "/tmp/contract-llm")
        try await ModelProviderContract(asrURL: asr, llmURL: llm)
            .verify(FakeModelProvider(asrURL: asr, llmURL: llm))
    }

    func testMissingModelEnsureReportsTheProfile() async throws {
        let provider = FakeModelProvider()
        do {
            _ = try await provider.ensure(profileID: "missing", progress: { _ in })
            XCTFail("expected ensure to throw")
        } catch let error as SuperflowError {
            XCTAssertEqual(error, .modelUnavailable("missing"))
        }
    }
}
