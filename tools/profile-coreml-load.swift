import CoreML
import Foundation

// Run with: swift tools/profile-coreml-load.swift <installed model directory>
// Core ML owns bundle reads and specialization inside MLModel.load. Instruments
// is required to distinguish those operations; these are component load times.
guard (2...3).contains(CommandLine.arguments.count) else {
    fatalError("Usage: swift tools/profile-coreml-load.swift <installed model directory> [cpu|gpu|ane|all]")
}
let unitName = CommandLine.arguments.count == 3 ? CommandLine.arguments[2] : "gpu"
let choices: [String: MLComputeUnits] = ["cpu": .cpuOnly, "gpu": .cpuAndGPU,
                                       "ane": .cpuAndNeuralEngine, "all": .all]
guard let units = choices[unitName] else { fatalError("Unknown compute policy: \(unitName)") }
let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let configuration = MLModelConfiguration()
configuration.computeUnits = units
var models: [MLModel] = []

func report(_ stage: String, since start: ContinuousClock.Instant) {
    let elapsed = start.duration(to: .now)
    FileHandle.standardOutput.write(Data("\(unitName) \(stage): \(elapsed)\n".utf8))
}

let metadataStart = ContinuousClock.now
for name in ["metadata.json", "tokenizer.json"] {
    _ = try Data(contentsOf: root.appendingPathComponent(name))
}
report("metadata and tokenizer file reads", since: metadataStart)

for name in ["encoder", "decoder", "joint", "decoder_joint"] {
    let url = root.appendingPathComponent(name + ".mlmodelc")
    guard FileManager.default.fileExists(atPath: url.path) else { continue }
    let start = ContinuousClock.now
    let model = try await MLModel.load(contentsOf: url, configuration: configuration)
    models.append(model)
    report("\(name) initialization and specialization", since: start)
}
withExtendedLifetime(models) {}
