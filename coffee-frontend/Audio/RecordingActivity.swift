import ActivityKit
import Foundation

// MARK: - Recording Live Activity
// Shared between main app and widget extension.
// Shows recording status on Dynamic Island and Lock Screen.

struct RecordingAttributes: ActivityAttributes {
    /// Static data — set once when activity starts
    let disciplineName: String

    /// Dynamic data — updated during recording
    struct ContentState: Codable, Hashable {
        var elapsedSeconds: Int
        var status: String  // "recording", "paused", "uploading", "processing"
    }
}
