import Foundation
import SuperflowKernel

/// Kept name for the assembly entry point; the implementation lives in
/// `OrderedStitcher`, which adds overlap-aware seam dedupe on top of the
/// single-word rule this shim provided.
public enum SeamRepair {
    /// Legacy stitching without planner overlap metadata (retry halves,
    /// hand-stitched pieces). See `OrderedStitcher` for the full rules.
    public static func stitch(_ pieces: [String]) -> String {
        OrderedStitcher.stitch(pieces)
    }
}
