import ActivityKit
import WidgetKit
import SwiftUI

// MARK: - Recording Live Activity Widget
// Shows on Dynamic Island (compact, expanded, minimal) and Lock Screen.

struct RecordingLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RecordingAttributes.self) { context in
            // LOCK SCREEN presentation
            lockScreenView(context: context)
        } dynamicIsland: { context in
            DynamicIsland {
                // EXPANDED Dynamic Island
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 6) {
                        recordingDot(status: context.state.status)
                        Text(statusLabel(context.state.status))
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.8))
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(formatTime(context.state.elapsedSeconds))
                        .font(.system(size: 20, weight: .bold).monospacedDigit())
                        .foregroundStyle(.white)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack(spacing: 6) {
                        Image(systemName: "book.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.5))
                        Text(context.attributes.disciplineName)
                            .font(.system(size: 13))
                            .foregroundStyle(.white.opacity(0.7))
                            .lineLimit(1)
                    }
                }
            } compactLeading: {
                // COMPACT Dynamic Island — left side
                HStack(spacing: 4) {
                    recordingDot(status: context.state.status)
                    Text(formatTimeShort(context.state.elapsedSeconds))
                        .font(.system(size: 12, weight: .semibold).monospacedDigit())
                        .foregroundStyle(.white)
                }
            } compactTrailing: {
                // COMPACT Dynamic Island — right side
                Image(systemName: context.state.status == "paused" ? "pause.fill" : "waveform")
                    .font(.system(size: 12))
                    .foregroundStyle(context.state.status == "paused" ? .yellow : .red)
            } minimal: {
                // MINIMAL Dynamic Island (when another activity is also running)
                Image(systemName: "waveform")
                    .font(.system(size: 12))
                    .foregroundStyle(.red)
            }
        }
    }

    // MARK: - Lock Screen View

    @ViewBuilder
    private func lockScreenView(context: ActivityViewContext<RecordingAttributes>) -> some View {
        HStack(spacing: 16) {
            // Left: status indicator
            VStack(spacing: 4) {
                recordingDot(status: context.state.status)
                    .frame(width: 12, height: 12)
                Text(statusLabel(context.state.status))
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
            }

            // Center: discipline + timer
            VStack(alignment: .leading, spacing: 4) {
                Text(context.attributes.disciplineName)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(formatTime(context.state.elapsedSeconds))
                    .font(.system(size: 28, weight: .bold).monospacedDigit())
                    .foregroundStyle(.primary)
            }

            Spacer()

            // Right: waveform icon
            Image(systemName: "waveform")
                .font(.system(size: 24))
                .foregroundStyle(context.state.status == "paused" ? .yellow : .red)
        }
        .padding(16)
        .activityBackgroundTint(Color(red: 0.12, green: 0.09, blue: 0.07)) // coffee dark
    }

    // MARK: - Helpers

    @ViewBuilder
    private func recordingDot(status: String) -> some View {
        Circle()
            .fill(status == "paused" ? Color.yellow : Color.red)
            .frame(width: 8, height: 8)
    }

    private func statusLabel(_ status: String) -> String {
        switch status {
        case "recording": return "Gravando"
        case "paused": return "Pausado"
        case "uploading": return "Enviando"
        case "processing": return "Processando"
        default: return "Gravando"
        }
    }

    private func formatTime(_ seconds: Int) -> String {
        String(format: "%02d:%02d:%02d", seconds / 3600, (seconds % 3600) / 60, seconds % 60)
    }

    private func formatTimeShort(_ seconds: Int) -> String {
        let m = seconds / 60
        let s = seconds % 60
        return String(format: "%d:%02d", m, s)
    }
}
