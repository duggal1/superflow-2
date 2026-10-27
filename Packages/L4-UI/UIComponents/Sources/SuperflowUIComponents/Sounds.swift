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
    /// Held so a short cue is not deallocated mid-playback.
    private static var active: [NSSound] = []

    /// The cue's file, when the resource bundle actually contains it.
    public static func url(for cue: SoundCue) -> URL? {
        Bundle.module.url(forResource: cue.rawValue, withExtension: "mp3", subdirectory: "Sounds")
            ?? Bundle.module.url(forResource: cue.rawValue, withExtension: "mp3")
    }

    public static func play(_ cue: SoundCue) {
        guard let url = url(for: cue), let sound = NSSound(contentsOf: url, byReference: true) else {
            return
        }
        active.removeAll { !$0.isPlaying }
        active.append(sound)
        sound.play()
    }
}
