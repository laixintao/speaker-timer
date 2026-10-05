import AppKit
import Combine
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let store = PlanStore()
    private let engine = TimerEngine()
    private var overlay: OverlayPanelController!
    private var editorWindow: NSWindow?
    private var cancellables: Set<AnyCancellable> = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        configureApplicationMenu()
        configureOverlay()
        observePlanSelection()
        if let plan = store.selectedPlan { engine.load(plan) }
        showEditor()

        if let message = store.startupMessage {
            DispatchQueue.main.async { [weak self] in self?.showStartupWarning(message) }
        }
    }

    private func configureOverlay() {
        overlay = OverlayPanelController(engine: engine, store: store)
        overlay.onShowEditor = { [weak self] in self?.showEditor() }
        overlay.onStart = { [weak self] in
            guard let self, let plan = self.store.selectedPlan, plan.validationMessage == nil else { return }
            self.start(plan)
        }
        overlay.onEnd = { [weak self] in self?.endSession() }
        engine.onBoundary = { [weak self] _ in
            guard let self, self.store.soundEnabled else { return }
            if let sound = NSSound(named: NSSound.Name("Glass")) {
                sound.play()
            } else {
                NSSound.beep()
            }
        }
    }

    private func observePlanSelection() {
        store.$selectedPlanID
            .combineLatest(store.$library)
            .sink { [weak self] _, _ in
                guard let self, self.engine.phase == .idle, let plan = self.store.selectedPlan else { return }
                self.engine.load(plan)
            }
            .store(in: &cancellables)
    }

    private func makeEditorWindow() -> NSWindow {
        let root = EditorRootView(
            store: store,
            engine: engine,
            onStart: { [weak self] plan in self?.start(plan) },
            onShowOverlay: { [weak self] in self?.overlay.show() },
            onEndSession: { [weak self] in self?.endSession() }
        )
        let controller = NSHostingController(rootView: root)
        let window = NSWindow(contentViewController: controller)
        window.title = "Speaker Timer"
        window.setContentSize(CGSize(width: 980, height: 680))
        window.minSize = CGSize(width: 820, height: 570)
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.tabbingMode = .disallowed
        window.isReleasedWhenClosed = false
        window.center()
        window.delegate = self
        window.setFrameAutosaveName("SpeakerTimerEditor")
        return window
    }

    private func start(_ plan: PresentationPlan) {
        guard plan.validationMessage == nil else { return }
        if engine.phase == .idle { engine.load(plan) }
        engine.start()
        overlay.show()
    }

    private func endSession() {
        engine.endSession()
        overlay.hide()
        if let plan = store.selectedPlan { engine.load(plan) }
        showEditor()
    }

    @objc private func showEditor() {
        if editorWindow == nil { editorWindow = makeEditorWindow() }
        guard let editorWindow else { return }
        NSApp.activate(ignoringOtherApps: true)
        editorWindow.makeKeyAndOrderFront(nil)
    }

    @objc private func showTimer() { overlay.show() }

    @objc private func toggleTimer() {
        switch engine.phase {
        case .idle:
            guard let plan = store.selectedPlan, plan.validationMessage == nil else { return }
            start(plan)
        case .running:
            engine.pause()
        case .paused:
            engine.resume()
        }
    }

    @objc private func resetTimer() {
        guard engine.activePlan != nil else { return }
        engine.reset()
        overlay.show()
    }

    @objc private func endTimer() { endSession() }
    @objc private func newPlan() { if engine.phase == .idle { store.addPlan() } }
    @objc private func duplicatePlan() { if engine.phase == .idle { store.duplicateSelectedPlan() } }
    @objc private func openProjectHomepage() {
        NSWorkspace.shared.open(URL(string: "https://github.com/laixintao/speaker-timer")!)
    }

    private func configureApplicationMenu() {
        let main = NSMenu()
        NSApp.mainMenu = main

        let appItem = NSMenuItem()
        main.addItem(appItem)
        let appMenu = NSMenu()
        appItem.submenu = appMenu
        appMenu.addItem(withTitle: "About Speaker Timer", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Speaker Timer on GitHub", action: #selector(openProjectHomepage), keyEquivalent: "")
        appMenu.addItem(.separator())
        let hide = appMenu.addItem(withTitle: "Hide Speaker Timer", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        hide.keyEquivalentModifierMask = [.command]
        appMenu.addItem(withTitle: "Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h").keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(withTitle: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit Speaker Timer", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q").keyEquivalentModifierMask = [.command]

        let fileItem = NSMenuItem()
        main.addItem(fileItem)
        let fileMenu = NSMenu(title: "File")
        fileItem.submenu = fileMenu
        fileMenu.addItem(withTitle: "New Presentation", action: #selector(newPlan), keyEquivalent: "n").keyEquivalentModifierMask = [.command]
        fileMenu.addItem(withTitle: "Duplicate Presentation", action: #selector(duplicatePlan), keyEquivalent: "d").keyEquivalentModifierMask = [.command, .shift]
        fileMenu.addItem(.separator())
        fileMenu.addItem(withTitle: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w").keyEquivalentModifierMask = [.command]

        let editItem = NSMenuItem()
        main.addItem(editItem)
        let editMenu = NSMenu(title: "Edit")
        editItem.submenu = editMenu
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z").keyEquivalentModifierMask = [.command]
        editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z").keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x").keyEquivalentModifierMask = [.command]
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c").keyEquivalentModifierMask = [.command]
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v").keyEquivalentModifierMask = [.command]
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a").keyEquivalentModifierMask = [.command]

        let timerItem = NSMenuItem()
        main.addItem(timerItem)
        let timerMenu = NSMenu(title: "Timer")
        timerItem.submenu = timerMenu
        let toggle = timerMenu.addItem(withTitle: "Start / Pause / Resume", action: #selector(toggleTimer), keyEquivalent: " ")
        toggle.keyEquivalentModifierMask = []
        timerMenu.addItem(withTitle: "Reset", action: #selector(resetTimer), keyEquivalent: "r").keyEquivalentModifierMask = [.command]
        timerMenu.addItem(withTitle: "End Session", action: #selector(endTimer), keyEquivalent: ".").keyEquivalentModifierMask = [.command]

        let windowItem = NSMenuItem()
        main.addItem(windowItem)
        let windowMenu = NSMenu(title: "Window")
        windowItem.submenu = windowMenu
        windowMenu.addItem(withTitle: "Show Editor", action: #selector(showEditor), keyEquivalent: "1").keyEquivalentModifierMask = [.command]
        windowMenu.addItem(withTitle: "Show Timer", action: #selector(showTimer), keyEquivalent: "2").keyEquivalentModifierMask = [.command]
        windowMenu.addItem(.separator())
        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m").keyEquivalentModifierMask = [.command]
    }

    private func showStartupWarning(_ message: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Plan library recovered"
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showEditor()
        return true
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard engine.phase != .idle else { return .terminateNow }
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "A timer is still active."
        alert.informativeText = "Quitting Speaker Timer will end this session."
        alert.addButton(withTitle: "Quit")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn ? .terminateNow : .terminateCancel
    }
}
