import AppKit
import Combine
import SwiftUI

private final class PassivePanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private final class OverlayButton: NSButton {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

@MainActor
private final class MoveHandleView: NSView {
    var onMouseDown: ((NSEvent) -> Void)?
    private var tracking: NSTrackingArea?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        toolTip = "Drag to move"
        setAccessibilityLabel("Drag to move")

        let image = NSImageView(image: NSImage(systemSymbolName: "line.3.horizontal", accessibilityDescription: "Drag to move")!)
        image.contentTintColor = .labelColor
        image.translatesAutoresizingMaskIntoConstraints = false
        addSubview(image)
        NSLayoutConstraint.activate([
            image.centerXAnchor.constraint(equalTo: centerXAnchor),
            image.centerYAnchor.constraint(equalTo: centerYAnchor),
            image.widthAnchor.constraint(equalToConstant: 20),
            image.heightAnchor.constraint(equalToConstant: 16),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: bounds, options: [.activeAlways, .cursorUpdate, .inVisibleRect], owner: self)
        addTrackingArea(area)
        tracking = area
    }

    override func cursorUpdate(with event: NSEvent) { NSCursor.openHand.set() }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) { onMouseDown?(event) }
}

@MainActor
private final class ResizeHandleView: NSView {
    var onBegin: (() -> Void)?
    var onDrag: ((CGPoint) -> Void)?
    var onEnd: (() -> Void)?
    private var tracking: NSTrackingArea?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        toolTip = "Drag to resize"
        setAccessibilityLabel("Drag to resize")

        let image = NSImageView(image: NSImage(systemSymbolName: "arrow.up.left.and.arrow.down.right", accessibilityDescription: "Drag to resize")!)
        image.contentTintColor = .secondaryLabelColor
        image.translatesAutoresizingMaskIntoConstraints = false
        addSubview(image)
        NSLayoutConstraint.activate([
            image.centerXAnchor.constraint(equalTo: centerXAnchor),
            image.centerYAnchor.constraint(equalTo: centerYAnchor),
            image.widthAnchor.constraint(equalToConstant: 15),
            image.heightAnchor.constraint(equalToConstant: 15),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: bounds, options: [.activeAlways, .cursorUpdate, .inVisibleRect], owner: self)
        addTrackingArea(area)
        tracking = area
    }

    override func cursorUpdate(with event: NSEvent) { NSCursor.crosshair.set() }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        guard let window else { return }
        let start = NSEvent.mouseLocation
        onBegin?()
        while true {
            guard let next = window.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) else { break }
            if next.type == .leftMouseUp { break }
            let point = NSEvent.mouseLocation
            onDrag?(CGPoint(x: point.x - start.x, y: point.y - start.y))
        }
        onEnd?()
    }
}

@MainActor
final class OverlayPanelController {
    var onShowEditor: (() -> Void)?
    var onStart: (() -> Void)?
    var onEnd: (() -> Void)?

    private let engine: TimerEngine
    private let store: PlanStore
    private let defaults: UserDefaults
    private let displayPanel: PassivePanel
    private let controlsPanel: PassivePanel
    private let resizePanel: PassivePanel
    private let moveHandle = MoveHandleView(frame: .zero)
    private let resizeHandle = ResizeHandleView(frame: .zero)
    private let playButton = OverlayButton()
    private let pinButton = OverlayButton()
    private let soundButton = OverlayButton()
    private var hoverTimer: Timer?
    private var lastHoverTime: TimeInterval = 0
    private var controlsVisible = false
    private var resizeStartFrame = CGRect.zero
    private var isMoving = false
    private var isResizing = false
    private var cancellables: Set<AnyCancellable> = []

    private let defaultSize = CGSize(width: 470, height: 172)
    private let minimumSize = CGSize(width: 330, height: 126)
    private let maximumSize = CGSize(width: 720, height: 264)
    private let controlsGap: CGFloat = 7
    private let edgeInset: CGFloat = 16

    init(engine: TimerEngine, store: PlanStore, defaults: UserDefaults = .standard) {
        self.engine = engine
        self.store = store
        self.defaults = defaults

        func makePanel(size: CGSize, shadow: Bool) -> PassivePanel {
            let panel = PassivePanel(
                contentRect: CGRect(origin: .zero, size: size),
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            panel.isFloatingPanel = true
            panel.hidesOnDeactivate = false
            panel.becomesKeyOnlyIfNeeded = true
            panel.collectionBehavior = [.canJoinAllSpaces, .canJoinAllApplications, .fullScreenAuxiliary, .ignoresCycle]
            panel.isReleasedWhenClosed = false
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = shadow
            panel.animationBehavior = .utilityWindow
            return panel
        }

        displayPanel = makePanel(size: defaultSize, shadow: true)
        controlsPanel = makePanel(size: CGSize(width: 346, height: 46), shadow: true)
        resizePanel = makePanel(size: CGSize(width: 26, height: 26), shadow: false)

        let hosting = NSHostingView(rootView: TimerDisplayView(engine: engine, store: store))
        hosting.frame = CGRect(origin: .zero, size: defaultSize)
        hosting.autoresizingMask = [.width, .height]
        displayPanel.contentView = hosting
        displayPanel.ignoresMouseEvents = true

        configureControls()
        configureResizeHandle()
        applyWindowLevel()

        moveHandle.onMouseDown = { [weak self] event in self?.beginMove(with: event) }
        engine.$phase.sink { [weak self] _ in self?.updateControls() }.store(in: &cancellables)
        store.$alwaysOnTop.sink { [weak self] _ in self?.applyWindowLevel() }.store(in: &cancellables)
        store.$soundEnabled.sink { [weak self] _ in self?.updateControls() }.store(in: &cancellables)
    }

    var isVisible: Bool { displayPanel.isVisible }

    func show() {
        guard engine.activePlan != nil else { return }
        if !displayPanel.isVisible {
            restoreOrPositionFrame()
        }
        displayPanel.orderFrontRegardless()
        startHoverTracking()
        layoutChrome()
    }

    func hide() {
        finishMove()
        setControlsVisible(false)
        stopHoverTracking()
        displayPanel.orderOut(nil)
    }

    private func configureControls() {
        let background = NSVisualEffectView()
        background.material = .hudWindow
        background.blendingMode = .behindWindow
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 12
        controlsPanel.contentView = background

        moveHandle.translatesAutoresizingMaskIntoConstraints = false
        moveHandle.widthAnchor.constraint(equalToConstant: 38).isActive = true
        moveHandle.heightAnchor.constraint(equalToConstant: 38).isActive = true

        func configure(_ button: OverlayButton, symbol: String, label: String, action: Selector) {
            button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
            button.imagePosition = .imageOnly
            button.bezelStyle = .inline
            button.isBordered = false
            button.refusesFirstResponder = true
            button.toolTip = label
            button.setAccessibilityLabel(label)
            button.target = self
            button.action = action
            button.translatesAutoresizingMaskIntoConstraints = false
            button.widthAnchor.constraint(equalToConstant: 34).isActive = true
            button.heightAnchor.constraint(equalToConstant: 34).isActive = true
        }

        configure(playButton, symbol: "play.fill", label: "Start", action: #selector(toggleRunning))
        let reset = OverlayButton()
        configure(reset, symbol: "arrow.counterclockwise", label: "Reset", action: #selector(resetTimer))
        let editor = OverlayButton()
        configure(editor, symbol: "rectangle.and.pencil.and.ellipsis", label: "Open editor", action: #selector(showEditor))
        configure(pinButton, symbol: "pin.fill", label: "Always on top", action: #selector(togglePin))
        configure(soundButton, symbol: "speaker.wave.2.fill", label: "Checkpoint sound", action: #selector(toggleSound))
        let end = OverlayButton()
        configure(end, symbol: "xmark", label: "End timer", action: #selector(endSession))

        let stack = NSStackView(views: [moveHandle, playButton, reset, editor, pinButton, soundButton, end])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 6
        stack.edgeInsets = NSEdgeInsets(top: 4, left: 7, bottom: 4, right: 7)
        stack.translatesAutoresizingMaskIntoConstraints = false
        background.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: background.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: background.trailingAnchor),
            stack.topAnchor.constraint(equalTo: background.topAnchor),
            stack.bottomAnchor.constraint(equalTo: background.bottomAnchor),
        ])
        updateControls()
    }

    private func configureResizeHandle() {
        let background = NSVisualEffectView()
        background.material = .hudWindow
        background.blendingMode = .behindWindow
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 8
        resizeHandle.frame = background.bounds
        resizeHandle.autoresizingMask = [.width, .height]
        background.addSubview(resizeHandle)
        resizePanel.contentView = background

        resizeHandle.onBegin = { [weak self] in
            guard let self else { return }
            self.finishMove()
            self.isResizing = true
            self.resizeStartFrame = self.displayPanel.frame
        }
        resizeHandle.onDrag = { [weak self] delta in self?.resize(by: delta) }
        resizeHandle.onEnd = { [weak self] in
            guard let self else { return }
            self.isResizing = false
            self.keepOnScreen()
            self.saveFrame()
        }
    }

    private func applyWindowLevel() {
        let level: NSWindow.Level = store.alwaysOnTop ? .floating : .normal
        displayPanel.level = level
        controlsPanel.level = NSWindow.Level(rawValue: level.rawValue + 1)
        resizePanel.level = controlsPanel.level
        updateControls()
    }

    private func updateControls() {
        let playSymbol: String
        let playLabel: String
        switch engine.phase {
        case .idle, .paused:
            playSymbol = "play.fill"
            playLabel = engine.phase == .idle ? "Start" : "Resume"
        case .running:
            playSymbol = "pause.fill"
            playLabel = "Pause"
        }
        playButton.image = NSImage(systemSymbolName: playSymbol, accessibilityDescription: playLabel)
        playButton.toolTip = playLabel
        playButton.setAccessibilityLabel(playLabel)

        let pinSymbol = store.alwaysOnTop ? "pin.fill" : "pin.slash"
        pinButton.image = NSImage(systemSymbolName: pinSymbol, accessibilityDescription: "Always on top")
        pinButton.contentTintColor = store.alwaysOnTop ? .controlAccentColor : .secondaryLabelColor
        let soundSymbol = store.soundEnabled ? "speaker.wave.2.fill" : "speaker.slash.fill"
        soundButton.image = NSImage(systemSymbolName: soundSymbol, accessibilityDescription: "Checkpoint sound")
        soundButton.contentTintColor = store.soundEnabled ? .controlAccentColor : .secondaryLabelColor
    }

    @objc private func toggleRunning() {
        switch engine.phase {
        case .idle: onStart?()
        case .running: engine.pause()
        case .paused: engine.resume()
        }
    }

    @objc private func resetTimer() { engine.reset() }
    @objc private func showEditor() { onShowEditor?() }
    @objc private func togglePin() { store.alwaysOnTop.toggle() }
    @objc private func toggleSound() { store.soundEnabled.toggle() }
    @objc private func endSession() { onEnd?() }

    private var contentArea: CGRect {
        let visible = (displayPanel.screen ?? NSScreen.main)?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1280, height: 800)
        return CGRect(
            x: visible.minX + edgeInset,
            y: visible.minY + edgeInset + controlsPanel.frame.height + controlsGap,
            width: max(1, visible.width - edgeInset * 2 - resizePanel.frame.width - controlsGap),
            height: max(1, visible.height - edgeInset * 2 - controlsPanel.frame.height - controlsGap)
        )
    }

    private func restoreOrPositionFrame() {
        let saved = defaults.string(forKey: "overlayFrame").map(NSRectFromString)
        let screen = saved.flatMap { frame in
            NSScreen.screens.first { $0.frame.contains(CGPoint(x: frame.midX, y: frame.midY)) }
        } ?? NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1280, height: 800)
        let area = CGRect(
            x: visible.minX + edgeInset,
            y: visible.minY + edgeInset + controlsPanel.frame.height + controlsGap,
            width: max(1, visible.width - edgeInset * 2 - resizePanel.frame.width - controlsGap),
            height: max(1, visible.height - edgeInset * 2 - controlsPanel.frame.height - controlsGap)
        )
        let candidate = saved ?? CGRect(
            x: area.maxX - defaultSize.width,
            y: area.maxY - defaultSize.height,
            width: defaultSize.width,
            height: defaultSize.height
        )
        displayPanel.setFrame(constrained(candidate, to: area), display: false)
        layoutChrome()
    }

    private func constrained(_ frame: CGRect, to area: CGRect) -> CGRect {
        let width = min(maximumSize.width, max(minimumSize.width, min(frame.width, area.width)))
        let height = min(maximumSize.height, max(minimumSize.height, min(frame.height, area.height)))
        return CGRect(
            x: min(max(frame.minX, area.minX), area.maxX - width),
            y: min(max(frame.minY, area.minY), area.maxY - height),
            width: width,
            height: height
        )
    }

    private func layoutChrome() {
        guard !isMoving else { return }
        let frame = displayPanel.frame
        let screen = (displayPanel.screen ?? NSScreen.main)?.visibleFrame.insetBy(dx: edgeInset, dy: edgeInset)
            ?? CGRect(x: 16, y: 16, width: 1248, height: 768)
        let controlsX = min(max(frame.midX - controlsPanel.frame.width / 2, screen.minX), screen.maxX - controlsPanel.frame.width)
        controlsPanel.setFrameOrigin(CGPoint(x: controlsX, y: frame.minY - controlsPanel.frame.height - controlsGap))
        resizePanel.setFrameOrigin(CGPoint(x: frame.maxX + controlsGap, y: frame.minY))
    }

    private func beginMove(with event: NSEvent) {
        guard displayPanel.isVisible, controlsVisible, !isMoving, !isResizing else { return }
        isMoving = true
        controlsPanel.addChildWindow(displayPanel, ordered: .below)
        controlsPanel.addChildWindow(resizePanel, ordered: .above)
        controlsPanel.performDrag(with: event)
        if NSEvent.pressedMouseButtons & 1 == 0 { finishMove() }
    }

    private func finishMove() {
        guard isMoving else { return }
        controlsPanel.removeChildWindow(displayPanel)
        controlsPanel.removeChildWindow(resizePanel)
        isMoving = false
        keepOnScreen()
        saveFrame()
    }

    private func resize(by delta: CGPoint) {
        let ratio = defaultSize.width / defaultSize.height
        let horizontal = delta.x
        let vertical = -delta.y * ratio
        let change = abs(horizontal) >= abs(vertical) ? horizontal : vertical
        let width = min(maximumSize.width, max(minimumSize.width, resizeStartFrame.width + change))
        let height = min(maximumSize.height, max(minimumSize.height, width / ratio))
        let frame = CGRect(
            x: resizeStartFrame.minX,
            y: resizeStartFrame.maxY - height,
            width: width,
            height: height
        )
        displayPanel.setFrame(constrained(frame, to: contentArea), display: true)
        layoutChrome()
    }

    private func keepOnScreen() {
        displayPanel.setFrame(constrained(displayPanel.frame, to: contentArea), display: true)
        layoutChrome()
    }

    private func saveFrame() {
        defaults.set(NSStringFromRect(displayPanel.frame), forKey: "overlayFrame")
    }

    private func startHoverTracking() {
        guard hoverTimer == nil else { return }
        let timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] timer in
            guard let self else {
                timer.invalidate()
                return
            }
            MainActor.assumeIsolated { self.updateHover(at: NSEvent.mouseLocation) }
        }
        timer.tolerance = 0.015
        RunLoop.main.add(timer, forMode: .common)
        hoverTimer = timer
        updateHover(at: NSEvent.mouseLocation)
    }

    private func stopHoverTracking() {
        hoverTimer?.invalidate()
        hoverTimer = nil
    }

    private func updateHover(at point: CGPoint) {
        guard displayPanel.isVisible else { return }
        let now = ProcessInfo.processInfo.systemUptime
        if isMoving {
            if NSEvent.pressedMouseButtons & 1 == 0 { finishMove() }
            lastHoverTime = now
            return
        }
        let displayContains = displayPanel.frame.insetBy(dx: -3, dy: -3).contains(point)
        let chromeContains = controlsVisible && (
            controlsPanel.frame.contains(point)
                || resizePanel.frame.contains(point)
                || hoverBridge.contains(point)
        )
        if displayContains || chromeContains || isMoving || isResizing {
            lastHoverTime = now
            setControlsVisible(true)
        } else if now - lastHoverTime > 0.28 {
            setControlsVisible(false)
        }
    }

    private var hoverBridge: CGRect {
        let display = displayPanel.frame
        let controls = controlsPanel.frame
        let left = max(display.minX, controls.minX)
        let right = min(display.maxX, controls.maxX)
        return CGRect(x: left, y: controls.maxY, width: max(0, right - left), height: controlsGap)
    }

    private func setControlsVisible(_ visible: Bool) {
        let shouldShow = visible && displayPanel.isVisible
        guard shouldShow != controlsVisible else { return }
        controlsVisible = shouldShow
        if shouldShow {
            layoutChrome()
            controlsPanel.orderFrontRegardless()
            resizePanel.orderFrontRegardless()
        } else if !isMoving && !isResizing {
            controlsPanel.orderOut(nil)
            resizePanel.orderOut(nil)
        }
    }
}
