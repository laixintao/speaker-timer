import Foundation

@MainActor
final class PlanStore: ObservableObject {
    @Published private(set) var library: PlanLibrary
    @Published var selectedPlanID: UUID? {
        didSet {
            defaults.set(selectedPlanID?.uuidString, forKey: Keys.selectedPlanID)
        }
    }
    @Published var theme: OverlayTheme {
        didSet { defaults.set(theme.rawValue, forKey: Keys.theme) }
    }
    @Published var soundEnabled: Bool {
        didSet { defaults.set(soundEnabled, forKey: Keys.soundEnabled) }
    }
    @Published var alwaysOnTop: Bool {
        didSet { defaults.set(alwaysOnTop, forKey: Keys.alwaysOnTop) }
    }

    private(set) var startupMessage: String?

    private let defaults: UserDefaults
    private let fileURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(applicationSupportRoot: URL? = nil, defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let root = applicationSupportRoot ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let plansFileURL = root.appendingPathComponent("Speaker Timer", isDirectory: true)
            .appendingPathComponent("plans.json", isDirectory: false)
        fileURL = plansFileURL

        let configuredEncoder = JSONEncoder()
        configuredEncoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        configuredEncoder.dateEncodingStrategy = .iso8601
        encoder = configuredEncoder
        let configuredDecoder = JSONDecoder()
        configuredDecoder.dateDecodingStrategy = .iso8601
        decoder = configuredDecoder

        var recoveryMessage: String?
        let initialLibrary: PlanLibrary
        if let data = try? Data(contentsOf: plansFileURL),
           let decoded = try? configuredDecoder.decode(PlanLibrary.self, from: data),
           decoded.schemaVersion == PlanLibrary.currentSchemaVersion,
           !decoded.plans.isEmpty {
            initialLibrary = decoded
        } else {
            initialLibrary = .starter
            if FileManager.default.fileExists(atPath: plansFileURL.path) {
                let formatter = DateFormatter()
                formatter.dateFormat = "yyyyMMdd-HHmmss"
                let backup = plansFileURL.deletingLastPathComponent()
                    .appendingPathComponent("plans.corrupt-\(formatter.string(from: Date())).json")
                try? FileManager.default.createDirectory(at: plansFileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                do {
                    try FileManager.default.moveItem(at: plansFileURL, to: backup)
                    recoveryMessage = "Your plan library could not be read. The original file was preserved as \(backup.lastPathComponent)."
                } catch {
                    recoveryMessage = "Your plan library could not be read. A starter plan has been loaded."
                }
            }
        }
        library = initialLibrary

        theme = defaults.string(forKey: Keys.theme).flatMap(OverlayTheme.init(rawValue:)) ?? .frostedDark
        soundEnabled = defaults.object(forKey: Keys.soundEnabled) as? Bool ?? true
        alwaysOnTop = defaults.object(forKey: Keys.alwaysOnTop) as? Bool ?? true

        if let raw = defaults.string(forKey: Keys.selectedPlanID),
           let identifier = UUID(uuidString: raw),
           initialLibrary.plans.contains(where: { $0.id == identifier }) {
            selectedPlanID = identifier
        } else {
            selectedPlanID = initialLibrary.plans.first?.id
        }
        startupMessage = recoveryMessage

        if !FileManager.default.fileExists(atPath: plansFileURL.path) {
            save()
        }
    }

    var plans: [PresentationPlan] { library.plans }

    var selectedPlan: PresentationPlan? {
        guard let selectedPlanID else { return library.plans.first }
        return library.plans.first(where: { $0.id == selectedPlanID })
    }

    func select(_ identifier: UUID?) {
        guard let identifier, library.plans.contains(where: { $0.id == identifier }) else { return }
        selectedPlanID = identifier
    }

    func addPlan() {
        let plan = PresentationPlan(
            name: "Untitled presentation",
            segments: [Segment(title: "Introduction", durationSeconds: 5 * 60)]
        )
        library.plans.append(plan)
        selectedPlanID = plan.id
        save()
    }

    func duplicateSelectedPlan() {
        guard let selectedPlan else { return }
        let copy = PresentationPlan(
            name: selectedPlan.name + " copy",
            segments: selectedPlan.segments.map { Segment(title: $0.title, durationSeconds: $0.durationSeconds) }
        )
        library.plans.append(copy)
        selectedPlanID = copy.id
        save()
    }

    func deleteSelectedPlan() {
        guard library.plans.count > 1, let selectedPlanID,
              let index = library.plans.firstIndex(where: { $0.id == selectedPlanID }) else { return }
        library.plans.remove(at: index)
        self.selectedPlanID = library.plans[min(index, library.plans.count - 1)].id
        save()
    }

    func updateSelectedPlan(_ transform: (inout PresentationPlan) -> Void) {
        guard let selectedPlanID,
              let index = library.plans.firstIndex(where: { $0.id == selectedPlanID }) else { return }
        transform(&library.plans[index])
        library.plans[index].updatedAt = Date()
        library = PlanLibrary(schemaVersion: library.schemaVersion, plans: library.plans)
        save()
    }

    func addSegment() {
        updateSelectedPlan { plan in
            plan.segments.append(Segment(title: "New section", durationSeconds: 5 * 60))
        }
    }

    func updateSegment(_ segment: Segment) {
        updateSelectedPlan { plan in
            guard let index = plan.segments.firstIndex(where: { $0.id == segment.id }) else { return }
            plan.segments[index] = segment
        }
    }

    func deleteSegment(_ identifier: UUID) {
        updateSelectedPlan { plan in
            guard plan.segments.count > 1 else { return }
            plan.segments.removeAll { $0.id == identifier }
        }
    }

    func moveSegments(from offsets: IndexSet, to destination: Int) {
        updateSelectedPlan { plan in
            plan.segments.move(fromOffsets: offsets, toOffset: destination)
        }
    }

    func save() {
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try encoder.encode(library)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            startupMessage = "Speaker Timer could not save your plan library: \(error.localizedDescription)"
        }
    }

    private enum Keys {
        static let selectedPlanID = "selectedPlanID"
        static let theme = "overlayTheme"
        static let soundEnabled = "soundEnabled"
        static let alwaysOnTop = "alwaysOnTop"
    }
}
