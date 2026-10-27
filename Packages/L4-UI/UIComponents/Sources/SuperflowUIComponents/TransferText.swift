import Foundation
import SuperflowKernel

/// One line for a running download: the fraction the transfer layer reports,
/// plus the rate and byte count measured from the wire. Rates are decimal MB/s,
/// the same unit network throughput is quoted in.
public enum TransferText {
    public static func rate(_ bytesPerSecond: Double) -> String {
        guard bytesPerSecond > 0 else { return "" }
        let megabytes = bytesPerSecond / 1_000_000
        if megabytes < 10 { return String(format: "%.1f MB/s", megabytes) }
        return String(format: "%.0f MB/s", megabytes)
    }

    public static func bytes(_ bytes: Int64) -> String {
        guard bytes > 0 else { return "0 MB" }
        if bytes >= 1_000_000_000 {
            return String(format: "%.2f GB", Double(bytes) / 1_000_000_000)
        }
        let megabytes = Double(bytes) / 1_000_000
        if megabytes < 10 { return String(format: "%.1f MB", megabytes) }
        return String(format: "%.0f MB", megabytes)
    }

    /// `"42% · 38 MB/s · 212 MB of 512 MB"`. Falls back to the bare fraction
    /// until the first speed sample lands, and omits the total when the server
    /// did not report one (the FluidAudio caches do not).
    public static func progress(_ fraction: Double, transfer: TransferSnapshot?) -> String {
        let percent = "\(Int((min(1, max(0, fraction)) * 100).rounded()))%"
        guard let transfer, transfer.bytesPerSecond > 0 else { return percent }
        var parts = [percent, rate(transfer.bytesPerSecond), bytes(transfer.receivedBytes)]
        if let total = transfer.totalBytes {
            parts[2] += " of " + bytes(total)
        }
        return parts.joined(separator: " · ")
    }
}
