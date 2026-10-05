import AppKit
import Combine
import SwiftUI

private final class PassivePanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private final class OverlayButton: NSButton {
    var surfaceColor: NSColor = .darkGray { didSet { needsDisplay = true } }
    private var isHovered = false
    private var tracking: NSTrackingArea?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: bounds, options: [.activeAlways, .mouseEnteredAndExited, .inVisibleRect], owner: self)
        addTrackingArea(area)
        tracking = area
    }

    override func mouseEntered(with event: NSEvent) { isHovered = true; needsDisplay = true }
    override func mouseExited(with event: NSEvent) { isHovered = false; needsDisplay = true }
    override func highlight(_ flag: Bool) { super.highlight(flag); needsDisplay = true }

    override func draw(_ dirtyRect: NSRect) {
        let pressed = isHighlighted
        let rect = bounds.insetBy(dx: 1, dy: 2).offsetBy(dx: 0, dy: pressed ? 1 : 0)
        let shape = NSBezierPath(roundedRect: rect, xRadius: 8, yRadius: 8)
        let fill = surfaceColor.blended(withFraction: pressed ? 0.18 : isHovered ? 0.14 : 0,
                                       of: pressed ? .black : .white) ?? surfaceColor
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(pressed ? 0.08 : 0.30)
        shadow.shadowBlurRadius = pressed ? 1 : 3
        shadow.shadowOffset = NSSize(width: 0, height: pressed ? 0 : -1)
        shadow.set()
        fill.setFill()
        shape.fill()
        NSGraphicsContext.restoreGraphicsState()
        NSColor.white.withAlphaComponent(isHovered ? 0.35 : 0.16).setStroke()
        shape.lineWidth = 0.75
        shape.stroke()
        super.draw(dirtyRect)
    }
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
    private let controlsView = NSView()
    private let resizePanel: PassivePanel
    private let resizeHandle = ResizeHandleView(frame: .zero)
    private let playButton = OverlayButton()
    private let pinButton = OverlayButton()
    private let soundButton = OverlayButton()
    private var controlsVisible = false
    private var resizeStartFrame = CGRect.zero
    private var isResizing = false
    private var cancellables: Set<AnyCancellable> = []
    private var dragMonitor: Any?
    private var interactiveRegions: [CGRect] = []

    private let defaultSize = CGSize(width: 470, height: 454)
    private let minimumSize = CGSize(width: 380, height: 374)
    private let maximumSize = CGSize(width: 720, height: 800)
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
        resizePanel = makePanel(size: CGSize(width: 26, height: 26), shadow: false)

        let hosting = NSHostingView(rootView: TimerDisplayView(engine: engine, store: store,
            onInteractiveRegionsChange: { [weak self] regions in self?.interactiveRegions = regions }))
        hosting.frame = CGRect(origin: .zero, size: defaultSize)
        hosting.autoresizingMask = [.width, .height]
        displayPanel.contentView = hosting
        displayPanel.ignoresMouseEvents = false
        displayPanel.isMovableByWindowBackground = false

        configureControls()
        hosting.addSubview(controlsView)
        configureResizeHandle()
        applyWindowLevel()

        NotificationCenter.default.publisher(for: NSWindow.didMoveNotification, object: displayPanel)
            .sink { [weak self] _ in
                self?.layoutChrome()
                self?.saveFrame()
            }.store(in: &cancellables)
        engine.$phase.receive(on: RunLoop.main).sink { [weak self] _ in self?.updateControls() }.store(in: &cancellables)
        store.$alwaysOnTop.receive(on: RunLoop.main).sink { [weak self] _ in self?.applyWindowLevel() }.store(in: &cancellables)
        store.$soundEnabled.receive(on: RunLoop.main).sink { [weak self] _ in self?.updateControls() }.store(in: &cancellables)
        store.$theme.sink { [weak self] theme in self?.updateControlColors(theme: theme) }.store(in: &cancellables)
    }

    var isVisible: Bool { displayPanel.isVisible }

    func show() {
        guard engine.activePlan != nil else { return }
        if !displayPanel.isVisible {
            restoreOrPositionFrame()
        }
        displayPanel.orderFrontRegardless()
        installDragMonitor()
        setControlsVisible(true)
        layoutChrome()
    }

    func hide() {
        if let dragMonitor { NSEvent.removeMonitor(dragMonitor) }
        dragMonitor = nil
        setControlsVisible(false)
        displayPanel.orderOut(nil)
    }

    private func installDragMonitor() {
        guard dragMonitor == nil else { return }
        dragMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            let handled = MainActor.assumeIsolated {
                guard let self, event.window === self.displayPanel,
                      self.canDragBackground(at: event.locationInWindow) else { return false }
                self.displayPanel.performDrag(with: event)
                self.keepOnScreen()
                self.saveFrame()
                return true
            }
            return handled ? nil : event
        }
    }

    /// Coordinates are in the window's base space, matching mouse events.
    func canDragBackground(at windowPoint: CGPoint) -> Bool {
        guard let content = displayPanel.contentView else { return false }
        let point = content.convert(windowPoint, from: nil)
        guard content.bounds.contains(point) else { return false }
        var hit = content.hitTest(windowPoint)
        while let view = hit, view !== content {
            if view is NSControl { return false }
            hit = view.superview
        }
        let cardPoint = CGPoint(x: point.x, y: content.isFlipped ? point.y : content.bounds.height - point.y)
        // The footer belongs to AppKit, not to off-screen rows in the scrolling agenda.
        if cardPoint.y < content.bounds.height - 74,
           interactiveRegions.contains(where: { $0.contains(cardPoint) }) { return false }
        return true
    }

    private func configureControls() {
        let background = controlsView
        background.wantsLayer = true
        background.layer?.cornerRadius = 10

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

        let stack = NSStackView(views: [playButton, reset, editor, pinButton, soundButton, end])
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
        resizePanel.level = NSWindow.Level(rawValue: level.rawValue + 1)
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
        updateControlColors(theme: store.theme)
    }

    private func updateControlColors(theme: OverlayTheme) {
        let palette = ThemePalette.palette(for: theme, overtime: engine.snapshot.isOvertime)
        let foreground = NSColor(palette.foreground)
        let accent = NSColor(palette.accent)
        controlsView.layer?.backgroundColor = NSColor.clear.cgColor
        let surface: NSColor
        switch theme {
        case .blue: surface = NSColor(calibratedRed: 0.10, green: 0.27, blue: 0.62, alpha: 1)
        case .cream: surface = NSColor(calibratedRed: 0.96, green: 0.92, blue: 0.83, alpha: 1)
        case .black, .frostedDark: surface = NSColor(calibratedWhite: 0.19, alpha: 1)
        }
        for stack in controlsView.subviews.compactMap({ $0 as? NSStackView }) {
            for view in stack.arrangedSubviews {
                if let button = view as? NSButton { button.contentTintColor = foreground }
                if let button = view as? OverlayButton { button.surfaceColor = surface }
                for image in view.subviews.compactMap({ $0 as? NSImageView }) {
                    image.contentTintColor = foreground
                }
            }
        }
        pinButton.contentTintColor = store.alwaysOnTop ? accent : foreground.withAlphaComponent(0.6)
        soundButton.contentTintColor = store.soundEnabled ? accent : foreground.withAlphaComponent(0.6)
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
            y: visible.minY + edgeInset,
            width: max(1, visible.width - edgeInset * 2 - resizePanel.frame.width - controlsGap),
            height: max(1, visible.height - edgeInset * 2)
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
            y: visible.minY + edgeInset,
            width: max(1, visible.width - edgeInset * 2 - resizePanel.frame.width - controlsGap),
            height: max(1, visible.height - edgeInset * 2)
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
        let width = min(area.width, min(maximumSize.width, max(minimumSize.width, frame.width)))
        let height = min(area.height, min(maximumSize.height, max(minimumSize.height, frame.height)))
        return CGRect(
            x: min(max(frame.minX, area.minX), area.maxX - width),
            y: min(max(frame.minY, area.minY), area.maxY - height),
            width: width,
            height: height
        )
    }

    private func layoutChrome() {
        let frame = displayPanel.frame
        let width = min(260, max(1, frame.width - 36))
        let y: CGFloat = displayPanel.contentView?.isFlipped == true ? frame.height - 60 : 14
        controlsView.frame = CGRect(x: (frame.width - width) / 2, y: y, width: width, height: 46)
        resizePanel.setFrameOrigin(CGPoint(x: frame.maxX + controlsGap, y: frame.minY))
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

    private func setControlsVisible(_ visible: Bool) {
        let shouldShow = visible && displayPanel.isVisible
        guard shouldShow != controlsVisible else { return }
        controlsVisible = shouldShow
        if shouldShow {
            layoutChrome()
            controlsView.isHidden = false
            resizePanel.orderFrontRegardless()
        } else if !isResizing {
            controlsView.isHidden = true
            resizePanel.orderOut(nil)
        }
    }
}
