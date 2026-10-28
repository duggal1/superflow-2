import Foundation
import SuperflowKernel
import SuperflowPorts

extension SessionEngine {
    /// Drains capture into the journal, the archive and the recognizer. The
    /// archive is the only addition: the same buffers are copied, never decoded.
    func consumeAudio(_ samples: AsyncStream<AudioChunk>, writer: (any AudioJournalWriter)?,
                      archive: (any AudioArchiveWriter)?,
                      stream: any RecognitionStream) async {
        for await chunk in samples {
            await archive?.append(chunk)
            if let writer {
                await writer.append(chunk)
                // Journaling can stop mid-session (disk full / IO error). Keep
                // transcribing, but tell the user crash recovery is now off.
                if !journalWarned, await writer.isDegraded {
                    journalWarned = true
                    emit(.notice("Audio journal stopped (disk). Transcription continues, crash recovery is off."))
                }
            }
            await stream.feed(chunk)
            levelCounter += 1
            if levelCounter % 4 == 0 {
                emit(.level(Self.rms(chunk.samples)))
            }
        }
    }

    func consumeAudioEvents(_ events: AsyncStream<AudioEvent>) async {
        for await event in events {
            switch event {
            case .routeChanged: emit(.notice("Audio route changed; capture rebuilt."))
            case .failed(let message): emit(.notice("Audio problem: \(message)"))
            case .permissionRevoked: emit(.notice("Microphone permission was revoked. Stopping safely."))
            case .stopped: break
            }
        }
    }

    static func rms(_ samples: [Float]) -> Float {
        guard !samples.isEmpty else { return 0 }
        var sum: Float = 0
        for sample in samples { sum += sample * sample }
        return min(1, (sum / Float(samples.count)).squareRoot() * 6)
    }

    /// Opens the archive lane for a session. A failure is reported instead of being
    /// swallowed: `try?` here is how a whole session's clip went missing silently.
    func openArchive(for session: SessionID) async -> (any AudioArchiveWriter)? {
        guard settings.keepAudio, !settings.noTranscriptStorage, let archive else { return nil }
        do {
            return try await archive.makeWriter(session: session)
        } catch {
            emit(.notice("Audio could not be archived for this session: \(error.localizedDescription)"))
            return nil
        }
    }

    /// A degraded lane still records and transcribes; only crash recovery is off.
    /// Say so in the notice channel the Island already renders.
    func reportJournalIfDegraded(_ journalWriter: any AudioJournalWriter) async {
        guard !journalWarned, await journalWriter.isDegraded else { return }
        journalWarned = true
        emit(.notice("Crash recovery is off: not enough free disk space for the audio journal. Dictation keeps working and your transcript is still saved."))
    }
}
