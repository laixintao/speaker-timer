import Foundation

enum OverlayTheme: String, Codable, CaseIterable, Identifiable, Sendable {
    case frostedDark
    case black
    case cream
    case blue

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .frostedDark: "Frosted Dark"
        case .black: "Black"
        case .cream: "Cream"
        case .blue: "Blue"
        }
    }
}

struct Segment: Codable, Identifiable, Equatable, Hashable, Sendable {
    var id: UUID
    var title: String
    var durationSeconds: Int

    init(id: UUID = UUID(), title: String, durationSeconds: Int) {
        self.id = id
        self.title = title
        self.durationSeconds = durationSeconds
    }
}

struct PresentationPlan: Codable, Identifiable, Equatable, Hashable, Sendable {
    var id: UUID
    var name: String
    var segments: [Segment]
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        segments: [Segment],
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.segments = segments
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var totalSeconds: Int {
        segments.reduce(0) { partial, segment in
            partial + max(0, segment.durationSeconds)
        }
    }

    var validationMessage: String? {
        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Give this plan a name."
        }
        if segments.isEmpty {
            return "Add at least one section."
        }
        if segments.contains(where: { $0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
            return "Every section needs a title."
        }
        if segments.contains(where: { $0.durationSeconds <= 0 }) {
            return "Every section needs a duration greater than zero."
        }
        return nil
    }

    static let sample = PresentationPlan(
        name: "50-minute presentation",
        segments: [
            Segment(title: "Introduction", durationSeconds: 5 * 60),
            Segment(title: "Project overview", durationSeconds: 10 * 60),
            Segment(title: "Core technical work", durationSeconds: 15 * 60),
            Segment(title: "Impact & leadership", durationSeconds: 15 * 60),
            Segment(title: "Summary", durationSeconds: 5 * 60),
        ]
    )
}

struct PlanLibrary: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1

    var schemaVersion: Int
    var plans: [PresentationPlan]

    init(schemaVersion: Int = currentSchemaVersion, plans: [PresentationPlan]) {
        self.schemaVersion = schemaVersion
        self.plans = plans
    }

    static let starter = PlanLibrary(plans: [.sample])
}

enum TimerPhase: String, Equatable, Sendable {
    case idle
    case running
    case paused
}

struct TimelineSnapshot: Equatable, Sendable {
    var elapsedSeconds: TimeInterval
    var totalSeconds: Int
    var currentSegmentIndex: Int?
    var currentTitle: String
    var nextTitle: String?
    var secondsUntilBoundary: TimeInterval
    var progress: Double
    var segmentProgress: Double
    var isOvertime: Bool
    var overtimeSeconds: TimeInterval

    static let empty = TimelineSnapshot(
        elapsedSeconds: 0,
        totalSeconds: 0,
        currentSegmentIndex: nil,
        currentTitle: "Ready",
        nextTitle: nil,
        secondsUntilBoundary: 0,
        progress: 0,
        segmentProgress: 0,
        isOvertime: false,
        overtimeSeconds: 0
    )
}

enum BoundaryEvent: Equatable, Sendable {
    case section(title: String)
    case overtime
}
