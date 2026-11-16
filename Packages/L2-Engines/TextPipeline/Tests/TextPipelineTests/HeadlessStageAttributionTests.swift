import XCTest
import SuperflowKernel
import SuperflowPorts
@testable import SuperflowTextPipeline

/// Headless raw-vs-cleaned attribution. Feeds the exact raw ASR strings from
/// the acoustic probe through every production stage and records which stage,
/// if any, changes the text. Enable with SUPERFLOW_STAGE_PROBE=1.
final class HeadlessStageAttributionTests: XCTestCase {
    func testStageByStageAttribution() async throws {
        guard ProcessInfo.processInfo.environment["SUPERFLOW_STAGE_PROBE"] == "1" else { return }
        let output = ProcessInfo.processInfo.environment["SUPERFLOW_STAGE_OUT"]
            ?? "/private/var/folders/ct/cwpf7vpn059fkp932tq9zm4m0000gn/T/opencode/stage-probe.txt"
        let rawASR = [
            "The rediscache and validation is broken",
            "Check the Open Telemetry Traces before the release",
            "We deploy to Kubernetes every afternoon",
            "Off two point zero returned a five hundred three error",
            "The CICD pipeline failed on the last commit",
            "Time to first token matters more than tokens per second",
            "The intermittent failures are in the metal GPU path",
            "Evaluate metal GPU utilization and model accuracy",
            "Why did the queue stall during token generation",
            "Please ensure the dashboard shows the right number",
        ]
        var settings = AppSettings.default
        settings.cleanupEnabled = false
        let pipeline = TextPipelineBuilder.make(settings: settings)
        let context = TextContext(settings: settings)
        var report = "stages=\(pipeline.stages.map(\.id).joined(separator: " > "))\n\n"

        for raw in rawASR {
            report += "RAW: \(raw)\n"
            var draft = TranscriptDraft(text: raw)
            for stage in pipeline.stages {
                let before = draft.text
                draft = await stage.apply(draft, context: context)
                if draft.text != before {
                    report += "  \(stage.id): \(before)  ->  \(draft.text)\n"
                }
            }
            report += "FINAL: \(draft.text)\n\n"
        }

        report += "== S1-mini list outputs through downstream stages ==\n"
        for cleaned in [
            "For the trip, we need to pack:\n- Sunscreen\n- A first aid kit\n- Chargers for everything",
            "Here are the steps:\n1. Open the app.\n2. Press record.\n3. Copy the text.",
            "Hey Sarah,\n\nJust wanted to follow up on the proposal.\n\nThanks,\nJohn",
        ] {
            report += "S1: \(cleaned)\n"
            var draft = TranscriptDraft(text: cleaned)
            for stage in pipeline.stages {
                let before = draft.text
                draft = await stage.apply(draft, context: context)
                if draft.text != before { report += "  \(stage.id): \(before) -> \(draft.text)\n" }
            }
            report += "FINAL: \(draft.text)\n\n"
        }

        // Counterfactual: can any deterministic stage invent the reported
        // meaning-changing substitutions from correctly recognized words?
        for raw in ["The intermittent failures", "Please ensure the GPU is ready",
                    "evaluate Metal GPU", "model accuracy", "Why did it stall",
                    "tokens per second"] {
            var draft = TranscriptDraft(text: raw)
            for stage in pipeline.stages { draft = await stage.apply(draft, context: context) }
            report += "CHECK: \(raw)  ->  \(draft.text)\n"
        }
        try report.write(to: URL(fileURLWithPath: output), atomically: true, encoding: .utf8)
    }
}
