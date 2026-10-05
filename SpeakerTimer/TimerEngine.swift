import Darwin
import Foundation

protocol MonotonicTimeSource: AnyObject {
    var now: TimeInterval { get }
}

final class SystemContinuousTimeSource: MonotonicTimeSource, @unchecked Sendable {
    private let scale: Double

    init() {
        var information = mach_timebase_info_data_t()
        mach_timebase_info(&information)
        scale = Double(information.numer) / Double(information.denom) / 1_000_000_000
    }

    var now: TimeInterval {
        Double(mach_continuous_time()) * scale
    }
}

@MainActor
final class TimerEngine: ObservableObject {
    @Published private(set) var phase: TimerPhase = .idle
    @Published private(set) var snapshot: TimelineSnapshot = .empty
    @Published private(set) var transitionMessage: String?

    var onBoundary: ((BoundaryEvent) -> Void)?

    private let timeSource: MonotonicTimeSource
    private var plan: PresentationPlan?
    private var accumulatedSeconds: TimeInterval = 0
    private var runningSince: TimeInterval?
    private var refreshTimer: Timer?
    private var lastPosition: TimelinePosition = .none
    private var noticeWorkItem: DispatchWorkItem?

    init(timeSource: MonotonicTimeSource = SystemContinuousTimeSource()) {
        self.timeSource = timeSource
    }

    var activePlan: PresentationPlan? { plan }

    func load(_ plan: PresentationPlan) {
        guard phase == .idle else { return }
        self.plan = plan
        accumulatedSeconds = 0
        runningSince = nil
        lastPosition = .none
        update(triggerEvents: false)
    }

    func start(_ newPlan: PresentationPlan? = nil) {
        if let newPlan, phase == .idle {
            load(newPlan)
        }
        guard let plan, plan.validationMessage == nil, phase != .running else { return }
        runningSince = timeSource.now
        phase = .running
        update(triggerEvents: false)
        scheduleRefreshTimer()
    }

    func pause() {
        guard phase == .running, let runningSince else { return }
        accumulatedSeconds += max(0, timeSource.now - runningSince)
        self.runningSince = nil
        phase = .paused
        invalidateRefreshTimer()
        update(triggerEvents: true)
    }

    func resume() {
        guard phase == .paused, plan != nil else { return }
        runningSince = timeSource.now
        phase = .running
        scheduleRefreshTimer()
        update(triggerEvents: false)
    }

    func toggleRunning() {
        switch phase {
        case .idle: start()
        case .running: pause()
        case .paused: resume()
        }
    }

    func reset() {
        accumulatedSeconds = 0
        runningSince = nil
        phase = .idle
        lastPosition = .none
        invalidateRefreshTimer()
        clearTransitionMessage()
        update(triggerEvents: false)
    }

    func endSession() {
        invalidateRefreshTimer()
        noticeWorkItem?.cancel()
        noticeWorkItem = nil
        plan = nil
        accumulatedSeconds = 0
        runningSince = nil
        phase = .idle
        lastPosition = .none
        transitionMessage = nil
        snapshot = .empty
    }

    /// Exposed for deterministic native tests and immediate wake/resume updates.
    func refresh() {
        update(triggerEvents: true)
    }

    private var elapsedSeconds: TimeInterval {
        guard phase == .running, let runningSince else { return accumulatedSeconds }
        return accumulatedSeconds + max(0, timeSource.now - runningSince)
    }

    private func scheduleRefreshTimer() {
        invalidateRefreshTimer()
        let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] timer in
            guard let self else {
                timer.invalidate()
                return
            }
            MainActor.assumeIsolated {
                self.update(triggerEvents: true)
            }
        }
        timer.tolerance = 0.02
        RunLoop.main.add(timer, forMode: .common)
        refreshTimer = timer
    }

    private func invalidateRefreshTimer() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    private func update(triggerEvents: Bool) {
        guard let plan, !plan.segments.isEmpty, plan.totalSeconds > 0 else {
            snapshot = .empty
            return
        }

        let elapsed = max(0, elapsedSeconds)
        let total = plan.totalSeconds
        var cumulative = 0
        var start = 0
        var currentIndex: Int?

        for (index, segment) in plan.segments.enumerated() {
            let end = cumulative + segment.durationSeconds
            if elapsed < TimeInterval(end) {
                currentIndex = index
                start = cumulative
                cumulative = end
                break
            }
            cumulative = end
        }

        let position: TimelinePosition
        if elapsed >= TimeInterval(total) {
            position = .overtime
            snapshot = TimelineSnapshot(
                elapsedSeconds: elapsed,
                totalSeconds: total,
                currentSegmentIndex: nil,
                currentTitle: "Overtime",
                nextTitle: nil,
                secondsUntilBoundary: 0,
                progress: 1,
                segmentProgress: 1,
                isOvertime: true,
                overtimeSeconds: elapsed - TimeInterval(total)
            )
        } else if let currentIndex {
            let segment = plan.segments[currentIndex]
            let segmentElapsed = elapsed - TimeInterval(start)
            let segmentProgress = min(1, max(0, segmentElapsed / TimeInterval(segment.durationSeconds)))
            position = .segment(currentIndex)
            snapshot = TimelineSnapshot(
                elapsedSeconds: elapsed,
                totalSeconds: total,
                currentSegmentIndex: currentIndex,
                currentTitle: segment.title,
                nextTitle: currentIndex + 1 < plan.segments.count ? plan.segments[currentIndex + 1].title : nil,
                secondsUntilBoundary: max(0, TimeInterval(cumulative) - elapsed),
                progress: min(1, elapsed / TimeInterval(total)),
                segmentProgress: segmentProgress,
                isOvertime: false,
                overtimeSeconds: 0
            )
        } else {
            position = .none
            snapshot = .empty
        }

        if triggerEvents, lastPosition != .none, position != lastPosition {
            switch position {
            case let .segment(index):
                announce(.section(title: plan.segments[index].title))
            case .overtime:
                announce(.overtime)
            case .none:
                break
            }
        }
        lastPosition = position
    }

    private func announce(_ event: BoundaryEvent) {
        let message: String
        switch event {
        case let .section(title): message = "Now: \(title)"
        case .overtime: message = "Time is up"
        }
        transitionMessage = message
        onBoundary?(event)
        noticeWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                self?.transitionMessage = nil
            }
        }
        noticeWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: work)
    }

    private func clearTransitionMessage() {
        noticeWorkItem?.cancel()
        noticeWorkItem = nil
        transitionMessage = nil
    }

    private enum TimelinePosition: Equatable {
        case none
        case segment(Int)
        case overtime
    }
}
