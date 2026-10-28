import CoreML
import XCTest
@testable import SuperflowASRFluidAudio

/// Pins the locked compute-units policy. Owner decision 2026-10-29: GPU
/// (`.cpuAndGPU`, the Core ML GPU runtime) is the product default for the
/// always-hot dictation path; the alias table and the fallback must never
/// silently drift.
final class FluidAudioEngineFactoryTests: XCTestCase {
    func testDefaultComputeUnitsAreGPU() {
        XCTAssertEqual(FluidAudioEngineLoader.computeUnits(nil), .cpuAndGPU)
        XCTAssertEqual(FluidAudioEngineLoader.computeUnits(""), .cpuAndGPU)
    }

    func testOverrideAliasesKeepTheirMeaning() {
        XCTAssertEqual(FluidAudioEngineLoader.computeUnits("cpu"), .cpuOnly)
        XCTAssertEqual(FluidAudioEngineLoader.computeUnits("CPU"), .cpuOnly)
        XCTAssertEqual(FluidAudioEngineLoader.computeUnits("gpu"), .cpuAndGPU)
        XCTAssertEqual(FluidAudioEngineLoader.computeUnits("ane"), .cpuAndNeuralEngine)
        XCTAssertEqual(FluidAudioEngineLoader.computeUnits("all"), .all)
    }

    func testUnknownOverrideFallsBackToGPU() {
        XCTAssertEqual(FluidAudioEngineLoader.computeUnits("bogus"), .cpuAndGPU)
    }
}
