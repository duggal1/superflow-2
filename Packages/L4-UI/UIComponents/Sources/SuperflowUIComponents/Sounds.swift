import AppKit
import Foundation

/// The two short UI cues the app ships. Nothing else plays a sound: the
/// onboarding primary button clicks, and Escape during a dictation cancels it.
public enum SoundCue: String, Sendable, CaseIterable {
    case clickSoft = "click-soft"
    case transcriptionCancel = "transcription-cancel"
}

/// Plays a bundled cue through AppKit, which honours the system output device
/// and the user's alert volume without touching the microphone pipeline.
@MainActor
public enum Sounds {
    /// Kept alive and reused, so a repeated click retriggers instead of stacking.
    private static var cache: [SoundCue: NSSound] = [:]

    /// The cue's file, when the resource bundle actually contains it.
    public static func url(for cue: SoundCue) -> URL? {
        Bundle.module.url(forResource: cue.rawValue, withExtension: "mp3", subdirectory: "Sounds")
            ?? Bundle.module.url(forResource: cue.rawValue, withExtension: "mp3")
    }

    public static func play(_ cue: SoundCue, volume: Float = 0.5) {
        guard let sound = sound(for: cue) else { return }
        sound.stop()
        sound.volume = volume
        sound.play()
    }

    private static func sound(for cue: SoundCue) -> NSSound? {
        if let cached = cache[cue] { return cached }
        guard let url = url(for: cue), let sound = NSSound(contentsOf: url, byReference: true) else {
            return nil
        }
        cache[cue] = sound
        return sound
    }
}
