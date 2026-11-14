import ActivityKit
import SwiftUI
import WidgetKit

private let hyseWidgetAccent = Color(red: 0.055, green: 0.549, blue: 0.549)
private let hyseWidgetSuccess = Color(red: 0.12, green: 0.54, blue: 0.32)
private let hyseActivitySurface = Color(red: 0.075, green: 0.095, blue: 0.10)

struct TrainingLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: TrainingActivityAttributes.self) { context in
            TrainingLockScreenView(context: context)
                // iOS owns the outer shape and clips it correctly for every
                // device. Painting that system surface directly avoids a
                // second rounded card whose corners can be cut off.
                .activityBackgroundTint(hyseActivitySurface)
                .activitySystemActionForegroundColor(.white)
                .widgetURL(URL(string: "hyseapp://training/active"))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.bottom) {
                    // The leading, trailing and center regions sit against the
                    // Island's concave edges. Some Home Screen presentations
                    // clip those areas more tightly than the lock-screen banner.
                    // Keep the entire expanded layout in the bottom region so it
                    // always appears as one centered, fully visible panel.
                    VStack(spacing: 10) {
                        HStack(spacing: 10) {
                            activityGlyph(for: context.state, size: 30, showsBackground: false)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(context.state.workoutName)
                                    .font(.subheadline.weight(.semibold))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.76)
                                Text(context.state.currentExercise)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.76)
                            }
                            Spacer(minLength: 8)
                            timerView(context: context, compact: false)
                                .lineLimit(1)
                                .minimumScaleFactor(0.72)
                                .frame(width: 66, alignment: .trailing)
                        }

                        HStack(spacing: 10) {
                            Text(setDetail(context.state))
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.72)
                            Spacer(minLength: 8)
                            Text(progressText(context.state))
                                .font(.caption.weight(.bold).monospacedDigit())
                                .foregroundStyle(hyseWidgetAccent)
                        }
                        .padding(.horizontal, 6)
                        WorkoutActivityProgressBar(
                            completed: context.state.completedSets,
                            total: context.state.totalSets,
                            height: 4
                        )
                        .padding(.horizontal, 6)
                    }
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } compactLeading: {
                activityGlyph(for: context.state, size: 22, showsBackground: false)
            } compactTrailing: {
                timerView(context: context, compact: true)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                    .frame(minWidth: 36, idealWidth: 44, maxWidth: 48, alignment: .trailing)
            } minimal: {
                Image(systemName: context.state.timerStatus == "finished" ? "checkmark" : "timer")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(context.state.timerStatus == "finished" ? hyseWidgetSuccess : hyseWidgetAccent)
            }
            .widgetURL(URL(string: "hyseapp://training/active"))
            .contentMargins(.horizontal, 20, for: .expanded)
            .contentMargins(.vertical, 14, for: .expanded)
        }
    }

    @ViewBuilder private func activityGlyph(
        for state: TrainingActivityAttributes.ContentState,
        size: CGFloat,
        showsBackground: Bool
    ) -> some View {
        let finished = state.completed || state.timerStatus == "finished"
        Image(systemName: finished ? "checkmark" : (state.workoutPaused ? "pause.fill" : "figure.strengthtraining.traditional"))
            .font(.system(size: size * 0.48, weight: .semibold))
            .foregroundStyle(finished ? hyseWidgetSuccess : (state.workoutPaused ? .orange : hyseWidgetAccent))
            .frame(width: size, height: size)
            .background(showsBackground ? Color.white.opacity(0.09) : .clear, in: Circle())
    }

    @ViewBuilder private func timerView(context: ActivityViewContext<TrainingActivityAttributes>, compact: Bool) -> some View {
        if context.state.completed {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(hyseWidgetSuccess)
        } else if context.state.workoutPaused {
            Image(systemName: "pause.fill").foregroundStyle(.orange)
        } else if context.state.timerStatus == "finished" || context.isStale {
            // A short state label is deliberate here: it stays intact in both
            // the compact and expanded Island instead of truncating at an edge.
            Text(WidgetLocalization.text("training.live.done"))
                .font(compact ? .caption2.bold() : .caption.bold())
                .foregroundStyle(hyseWidgetSuccess)
        } else if let end = context.state.restTimerEnd {
            Text(timerInterval: Date.now...end, countsDown: true)
                .font(compact ? .caption2.weight(.semibold).monospacedDigit() : .subheadline.bold().monospacedDigit())
                .foregroundStyle(hyseWidgetAccent)
                .multilineTextAlignment(.trailing)
        } else {
            Text(timerInterval: context.state.durationStartDate...Date.distantFuture, countsDown: false)
                .font(compact ? .caption2.weight(.semibold).monospacedDigit() : .subheadline.bold().monospacedDigit())
                .multilineTextAlignment(.trailing)
        }
    }

    private func progressText(_ state: TrainingActivityAttributes.ContentState) -> String {
        "\(state.completedSets) / \(max(state.totalSets, state.completedSets))"
    }

    private func setDetail(_ state: TrainingActivityAttributes.ContentState) -> String {
        let reps = state.repetitionsText.isEmpty ? "" : "\(state.repetitionsText) \(WidgetLocalization.text("training.live.reps"))"
        let values = ["\(WidgetLocalization.text("training.live.set")) \(state.setNumber)", state.weightText, reps].filter { !$0.isEmpty }
        return values.joined(separator: " · ")
    }
}

private struct TrainingLockScreenView: View {
    let context: ActivityViewContext<TrainingActivityAttributes>

    var body: some View {
        VStack(spacing: 11) {
            HStack(spacing: 12) {
                stateIcon
                VStack(alignment: .leading, spacing: 2) {
                    Text(context.state.workoutName)
                        .font(.headline.weight(.bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                    Text(context.state.currentExercise)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 12)
                timer
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .frame(minWidth: 86)
                    .background(Color.white.opacity(0.09), in: Capsule())
            }

            HStack(spacing: 10) {
                Text(setDetail(context.state))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 8)
                Text("\(context.state.completedSets)/\(max(context.state.totalSets, context.state.completedSets))")
                    .font(.caption.weight(.bold).monospacedDigit())
                    .foregroundStyle(hyseWidgetAccent)
            }
            .padding(.horizontal, 6)

            WorkoutActivityProgressBar(
                completed: context.state.completedSets,
                total: context.state.totalSets,
                height: 5
            )
            .padding(.horizontal, 6)
        }
        // The background is supplied by activityBackgroundTint, so this view
        // stays full-width and only the content is inset from the system corners.
        .padding(.horizontal, 18)
        .padding(.top, 16)
        .padding(.bottom, 22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .foregroundStyle(.white)
    }

    private var stateIcon: some View {
        let finished = context.state.completed || context.state.timerStatus == "finished" || context.isStale
        return Image(systemName: finished ? "checkmark" : (context.state.workoutPaused ? "pause.fill" : "figure.strengthtraining.traditional"))
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(finished ? hyseWidgetSuccess : (context.state.workoutPaused ? .orange : hyseWidgetAccent))
            .frame(width: 40, height: 40)
            .background(Color.white.opacity(0.09), in: Circle())
    }

    @ViewBuilder private var timer: some View {
        if context.state.completed {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(hyseWidgetSuccess)
        } else if context.state.workoutPaused {
            Text(duration(context.state.pausedDurationSeconds))
                .font(.subheadline.bold().monospacedDigit())
                .foregroundStyle(.orange)
        } else if context.state.timerStatus == "finished" || context.isStale {
            Text(WidgetLocalization.text("training.live.done"))
                .font(.caption.bold())
                .foregroundStyle(hyseWidgetSuccess)
        } else if let end = context.state.restTimerEnd {
            Text(timerInterval: Date.now...end, countsDown: true)
                .font(.subheadline.bold().monospacedDigit())
                .foregroundStyle(hyseWidgetAccent)
        } else {
            Text(timerInterval: context.state.durationStartDate...Date.distantFuture, countsDown: false)
                .font(.subheadline.bold().monospacedDigit())
        }
    }

    private func duration(_ value: TimeInterval) -> String {
        let total = max(0, Int(value))
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    private func setDetail(_ state: TrainingActivityAttributes.ContentState) -> String {
        let reps = state.repetitionsText.isEmpty ? "" : "\(state.repetitionsText) \(WidgetLocalization.text("training.live.reps"))"
        return ["\(WidgetLocalization.text("training.live.set")) \(state.setNumber)", state.weightText, reps]
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }
}

private struct WorkoutActivityProgressBar: View {
    let completed: Int
    let total: Int
    let height: CGFloat

    private var progress: Double {
        min(1, max(0, Double(completed) / Double(max(1, total))))
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.12))
                if progress > 0 {
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [hyseWidgetAccent, hyseWidgetAccent.opacity(0.72)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: max(height, geometry.size.width * progress))
                }
            }
        }
        .frame(height: height)
        .accessibilityLabel(Text("\(completed) / \(max(total, completed))"))
    }
}
