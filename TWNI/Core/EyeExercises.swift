import Foundation

/// A prompt shown during an eye break. Every prompt is a variation of the same
/// evidence-backed idea (look far away, relax focus, blink fully) so each break
/// is still a 20-20-20 break. No medical claims.
struct EyeExercise: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let instruction: String
    let systemImage: String
}

enum EyeExerciseLibrary {
    static let all: [EyeExercise] = [
        EyeExercise(
            id: "farthest",
            title: "Find the farthest thing you can see",
            instruction: "Look across the room or out a window, at least 6 m (20 ft) away. Let your eyes relax on it.",
            systemImage: "mountain.2"
        ),
        EyeExercise(
            id: "window",
            title: "Look out the window",
            instruction: "Pick one far detail, like a tree, a roof or a cloud, and keep your eyes on it.",
            systemImage: "cloud.sun"
        ),
        EyeExercise(
            id: "trace",
            title: "Trace something far away",
            instruction: "Slowly follow the outline of a distant object with your eyes.",
            systemImage: "scribble"
        ),
        EyeExercise(
            id: "count",
            title: "Count five things far away",
            instruction: "Look at least 6 m (20 ft) away and find five things you can name.",
            systemImage: "binoculars"
        ),
    ]

    /// Shown in the last seconds of every break.
    static let blinkCue = EyeExercise(
        id: "blink",
        title: "Now blink slowly",
        instruction: "Close your eyes fully a few times, then open them gently.",
        systemImage: "eye"
    )

    /// Seconds before the end of a break when the blink cue takes over.
    static let blinkCueSeconds: TimeInterval = 5

    /// Rotates through the prompts so consecutive breaks feel different.
    static func exercise(forBreakNumber number: Int) -> EyeExercise {
        let index = ((number % all.count) + all.count) % all.count
        return all[index]
    }

    /// The prompt to show right now, switching to the blink cue near the end.
    static func prompt(for exercise: EyeExercise, restRemaining: TimeInterval, breakDuration: TimeInterval) -> EyeExercise {
        // Short breaks keep the main prompt; the blink cue needs time to land.
        guard breakDuration >= blinkCueSeconds * 3 else { return exercise }
        return restRemaining <= blinkCueSeconds ? blinkCue : exercise
    }
}
