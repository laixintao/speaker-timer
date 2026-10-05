import AppKit
import Foundation
import SwiftUI

final class FakeTimeSource: MonotonicTimeSource {
    var now: TimeInterval = 1_000
    func advance(_ seconds: TimeInterval) { now += seconds }
}

@main
@MainActor
struct SmokeTests {
    private static var failures = 0

    static func main() {
        NSApplication.shared.setActivationPolicy(.prohibited)
        testDurationFormatting()
        testTimelineTransitions()
        testPauseAndResume()
        testSkippedBoundariesDoNotBurst()
        testPlanPersistenceAndRecovery()
        renderThemeSnapshots()

        if failures > 0 {
            fputs("FAIL: \(failures) assertion(s) failed\n", stderr)
            exit(1)
        }
        print("PASS: model, persistence, timeline, and visual smoke tests")
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() {
            failures += 1
            fputs("FAIL: \(message)\n", stderr)
        }
    }

    private static func testDurationFormatting() {
        expect(DurationFormat.parse("5") == 300, "plain number should mean minutes")
        expect(DurationFormat.parse("5:30") == 330, "minutes and seconds should parse")
        expect(DurationFormat.parse("1:05:09") == 3_909, "hours should parse")
        expect(DurationFormat.parse("1:60") == nil, "seconds must be less than 60")
        expect(DurationFormat.parse("0") == nil, "zero duration is invalid")
        expect(DurationFormat.editor(3_909) == "1:05:09", "editor formatter should preserve hours")
        expect(DurationFormat.clock(759.9) == "12:39", "clock should floor elapsed seconds")
        expect(DurationFormat.remaining(60.1) == "01:01", "remaining time should round up")
    }

    private static func testTimelineTransitions() {
        let clock = FakeTimeSource()
        let engine = TimerEngine(timeSource: clock)
        let plan = PresentationPlan(name: "Test", segments: [
            Segment(title: "Opening", durationSeconds: 60),
            Segment(title: "Demo", durationSeconds: 120),
        ])
        var events: [BoundaryEvent] = []
        engine.onBoundary = { events.append($0) }
        engine.load(plan)
        expect(engine.snapshot.currentTitle == "Opening", "first section should be current before start")
        engine.start()
        clock.advance(59.2)
        engine.refresh()
        expect(engine.snapshot.currentSegmentIndex == 0, "first section should remain active before boundary")
        clock.advance(0.8)
        engine.refresh()
        expect(engine.snapshot.currentTitle == "Demo", "exact boundary should enter next section")
        expect(events == [.section(title: "Demo")], "section boundary should alert exactly once")
        clock.advance(120)
        engine.refresh()
        expect(engine.snapshot.isOvertime, "total duration should enter overtime")
        expect(abs(engine.snapshot.overtimeSeconds) < 0.001, "overtime should start at zero")
        expect(events.last == .overtime, "overtime should alert")
        engine.endSession()
    }

    private static func testPauseAndResume() {
        let clock = FakeTimeSource()
        let engine = TimerEngine(timeSource: clock)
        let plan = PresentationPlan(name: "Pause", segments: [Segment(title: "One", durationSeconds: 300)])
        engine.start(plan)
        clock.advance(20)
        engine.pause()
        let paused = engine.snapshot.elapsedSeconds
        clock.advance(50)
        engine.refresh()
        expect(abs(engine.snapshot.elapsedSeconds - paused) < 0.001, "paused timer must not advance")
        engine.resume()
        clock.advance(10)
        engine.refresh()
        expect(abs(engine.snapshot.elapsedSeconds - 30) < 0.001, "resume should continue from accumulated time")
        engine.endSession()
    }

    private static func testSkippedBoundariesDoNotBurst() {
        let clock = FakeTimeSource()
        let engine = TimerEngine(timeSource: clock)
        let plan = PresentationPlan(name: "Jump", segments: [
            Segment(title: "A", durationSeconds: 10),
            Segment(title: "B", durationSeconds: 10),
            Segment(title: "C", durationSeconds: 10),
        ])
        var events: [BoundaryEvent] = []
        engine.onBoundary = { events.append($0) }
        engine.start(plan)
        clock.advance(25)
        engine.refresh()
        expect(engine.snapshot.currentTitle == "C", "large time jump should land in latest section")
        expect(events == [.section(title: "C")], "large time jump should produce one useful alert")
        engine.endSession()
    }

    private static func testPlanPersistenceAndRecovery() {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("speaker-timer-tests-\(UUID().uuidString)")
        let suiteName = "io.xbin.speaker-timer.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            try? FileManager.default.removeItem(at: root)
            defaults.removePersistentDomain(forName: suiteName)
        }

        let store = PlanStore(applicationSupportRoot: root, defaults: defaults)
        store.addPlan()
        let count = store.plans.count
        store.updateSelectedPlan { plan in
            plan.name = "Persisted plan"
            plan.segments[0].durationSeconds = 420
        }
        let reloaded = PlanStore(applicationSupportRoot: root, defaults: defaults)
        expect(reloaded.plans.count == count, "all plans should reload")
        expect(reloaded.selectedPlan?.name == "Persisted plan", "selected plan should persist")
        expect(reloaded.selectedPlan?.segments[0].durationSeconds == 420, "segment duration should persist")

        let file = root.appendingPathComponent("Speaker Timer/plans.json")
        try? Data("not json".utf8).write(to: file)
        let recovered = PlanStore(applicationSupportRoot: root, defaults: defaults)
        expect(recovered.startupMessage != nil, "corrupt library should report recovery")
        expect(recovered.plans.count == 1, "corrupt library should load starter plan")
        let backups = (try? FileManager.default.contentsOfDirectory(atPath: file.deletingLastPathComponent().path)) ?? []
        expect(backups.contains(where: { $0.hasPrefix("plans.corrupt-") }), "corrupt library should be preserved")
    }

    private static func renderThemeSnapshots() {
        let output = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("build/qa", isDirectory: true)
        try? FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

        for theme in OverlayTheme.allCases {
            let root = FileManager.default.temporaryDirectory.appendingPathComponent("speaker-timer-render-\(UUID().uuidString)")
            let suite = "io.xbin.speaker-timer.render.\(UUID().uuidString)"
            let defaults = UserDefaults(suiteName: suite)!
            let store = PlanStore(applicationSupportRoot: root, defaults: defaults)
            store.theme = theme
            let clock = FakeTimeSource()
            let engine = TimerEngine(timeSource: clock)
            engine.start(store.selectedPlan!)
            clock.advance(757)
            engine.refresh()
            render(
                TimerDisplayView(engine: engine, store: store),
                size: CGSize(width: 470, height: 400),
                to: output.appendingPathComponent("timer-\(theme.rawValue).png")
            )
            if theme == .blue {
                renderOverlay(engine: engine, store: store, defaults: defaults,
                              to: output.appendingPathComponent("speaker-timer.png"))
            }
            engine.endSession()
            try? FileManager.default.removeItem(at: root)
            defaults.removePersistentDomain(forName: suite)
        }

        let editorRoot = FileManager.default.temporaryDirectory.appendingPathComponent("speaker-timer-editor-\(UUID().uuidString)")
        let editorSuite = "io.xbin.speaker-timer.editor.\(UUID().uuidString)"
        let editorDefaults = UserDefaults(suiteName: editorSuite)!
        let editorStore = PlanStore(applicationSupportRoot: editorRoot, defaults: editorDefaults)
        let editorEngine = TimerEngine(timeSource: FakeTimeSource())
        editorEngine.load(editorStore.selectedPlan!)
        render(
            EditorRootView(
                store: editorStore,
                engine: editorEngine,
                onStart: { _ in },
                onShowOverlay: {},
                onEndSession: {}
            ),
            size: CGSize(width: 980, height: 680),
            to: output.appendingPathComponent("editor.png")
        )
        try? FileManager.default.removeItem(at: editorRoot)
        editorDefaults.removePersistentDomain(forName: editorSuite)

        let root = FileManager.default.temporaryDirectory.appendingPathComponent("speaker-timer-overtime-\(UUID().uuidString)")
        let suite = "io.xbin.speaker-timer.overtime.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let store = PlanStore(applicationSupportRoot: root, defaults: defaults)
        let clock = FakeTimeSource()
        let engine = TimerEngine(timeSource: clock)
        engine.start(store.selectedPlan!)
        clock.advance(TimeInterval(store.selectedPlan!.totalSeconds + 73))
        engine.refresh()
        render(
            TimerDisplayView(engine: engine, store: store),
            size: CGSize(width: 470, height: 400),
            to: output.appendingPathComponent("timer-overtime.png")
        )
        engine.endSession()
        try? FileManager.default.removeItem(at: root)
        defaults.removePersistentDomain(forName: suite)

        let expected = OverlayTheme.allCases.map { "timer-\($0.rawValue).png" } + ["timer-overtime.png", "editor.png"]
        for name in expected {
            let file = output.appendingPathComponent(name)
            let size = (try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            expect(size > 5_000, "visual snapshot \(name) should be a non-empty PNG")
        }
    }

    private static func renderOverlay(engine: TimerEngine, store: PlanStore, defaults: UserDefaults, to output: URL) {
        let existing = Set(NSApp.windows.map(\.windowNumber))
        let overlay = OverlayPanelController(engine: engine, store: store, defaults: defaults)
        overlay.show()
        RunLoop.main.run(until: Date().addingTimeInterval(0.4))
        let windows = NSApp.windows.filter { !existing.contains($0.windowNumber) && $0.isVisible }
        expect(windows.count == 3, "display, controls, and resize handle should remain visible without hover")
        guard let first = windows.first else { overlay.hide(); return }
        let bounds = windows.reduce(first.frame) { $0.union($1.frame) }.insetBy(dx: -24, dy: -24)
        let image = NSImage(size: bounds.size)
        image.lockFocus()
        NSColor(calibratedRed: 0.10, green: 0.12, blue: 0.17, alpha: 1).setFill()
        NSBezierPath(rect: CGRect(origin: .zero, size: bounds.size)).fill()
        for window in windows {
            guard let view = window.contentView else { continue }
            view.layoutSubtreeIfNeeded()
            guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { continue }
            view.cacheDisplay(in: view.bounds, to: bitmap)
            let rect = window.frame.offsetBy(dx: -bounds.minX, dy: -bounds.minY)
            let radius: CGFloat = rect.height > 100 ? 24 : rect.height > 30 ? 12 : 8
            NSGraphicsContext.saveGraphicsState()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).addClip()
            bitmap.draw(in: rect)
            NSGraphicsContext.restoreGraphicsState()
        }
        image.unlockFocus()
        if let tiff = image.tiffRepresentation,
           let bitmap = NSBitmapImageRep(data: tiff),
           let png = bitmap.representation(using: .png, properties: [:]) {
            try? png.write(to: output)
        } else {
            expect(false, "could not render complete overlay screenshot")
        }
        overlay.hide()
        expect(windows.allSatisfy { !$0.isVisible }, "ending overlay should hide all three panels")
    }

    private static func render<V: View>(_ view: V, size: CGSize, to output: URL) {
        let host = NSHostingView(rootView: view)
        host.frame = CGRect(origin: .zero, size: size)
        let window = NSWindow(
            contentRect: host.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.contentView = host
        window.displayIfNeeded()
        host.layoutSubtreeIfNeeded()
        guard let representation = host.bitmapImageRepForCachingDisplay(in: host.bounds) else {
            expect(false, "could not allocate visual snapshot")
            return
        }
        host.cacheDisplay(in: host.bounds, to: representation)
        guard let data = representation.representation(using: .png, properties: [:]) else {
            expect(false, "could not encode visual snapshot")
            return
        }
        do {
            try data.write(to: output, options: .atomic)
        } catch {
            expect(false, "could not write visual snapshot: \(error)")
        }
    }
}
