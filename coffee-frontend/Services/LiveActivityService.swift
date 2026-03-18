import ActivityKit
import Foundation

// MARK: - Live Activity Service
// Manages the recording Live Activity (start, update, end).
// Used by RecordingFlowView to show recording status on Dynamic Island + Lock Screen.

enum LiveActivityService {

    private static var currentActivity: Activity<RecordingAttributes>?

    /// Start a new Live Activity for recording
    static func startRecording(disciplineName: String) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        let attributes = RecordingAttributes(disciplineName: disciplineName)
        let state = RecordingAttributes.ContentState(
            elapsedSeconds: 0,
            status: "recording"
        )

        do {
            let activity = try Activity.request(
                attributes: attributes,
                content: .init(state: state, staleDate: nil),
                pushType: nil
            )
            currentActivity = activity
        } catch {
            print("[LiveActivity] Failed to start: \(error)")
        }
    }

    /// Update the timer and status
    static func update(elapsedSeconds: Int, status: String = "recording") {
        guard let activity = currentActivity else { return }

        let state = RecordingAttributes.ContentState(
            elapsedSeconds: elapsedSeconds,
            status: status
        )

        Task {
            await activity.update(.init(state: state, staleDate: nil))
        }
    }

    /// End the Live Activity
    static func end(status: String = "processing") {
        guard let activity = currentActivity else { return }

        let finalState = RecordingAttributes.ContentState(
            elapsedSeconds: 0,
            status: status
        )

        Task {
            await activity.end(.init(state: finalState, staleDate: nil), dismissalPolicy: .after(.now + 5))
            currentActivity = nil
        }
    }

    /// Check if a Live Activity is currently active
    static var isActive: Bool {
        currentActivity != nil
    }
}
