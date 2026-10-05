import SwiftUI
import UniformTypeIdentifiers

struct EditorRootView: View {
    @ObservedObject var store: PlanStore
    @ObservedObject var engine: TimerEngine
    let onStart: (PresentationPlan) -> Void
    let onShowOverlay: () -> Void
    let onEndSession: () -> Void

    @State private var showingDeleteConfirmation = false

    private var isEditingDisabled: Bool { engine.phase != .idle }

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 190, ideal: 225, max: 280)
        } detail: {
            if let plan = store.selectedPlan {
                PlanDetailView(
                    plan: plan,
                    store: store,
                    engine: engine,
                    onStart: onStart,
                    onShowOverlay: onShowOverlay,
                    onEndSession: onEndSession
                )
                .id(plan.id)
            } else {
                ContentUnavailableView("No presentation selected", systemImage: "timer")
            }
        }
        .frame(minWidth: 820, minHeight: 570)
        .background(Color(nsColor: .windowBackgroundColor))
        .alert("Delete this presentation?", isPresented: $showingDeleteConfirmation) {
            Button("Delete", role: .destructive) { store.deleteSelectedPlan() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the plan from this Mac. This action cannot be undone.")
        }
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            List(selection: Binding(
                get: { store.selectedPlanID },
                set: { store.select($0) }
            )) {
                Section("Presentations") {
                    ForEach(store.plans) { plan in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(plan.name)
                                .font(.system(size: 13, weight: .medium))
                                .lineLimit(1)
                            Text("\(plan.segments.count) sections · \(DurationFormat.editor(plan.totalSeconds))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 3)
                        .tag(plan.id)
                    }
                }
            }
            .disabled(isEditingDisabled)

            Divider()
            HStack(spacing: 4) {
                Button(action: store.addPlan) {
                    Image(systemName: "plus")
                }
                .help("New presentation")
                Button(action: store.duplicateSelectedPlan) {
                    Image(systemName: "plus.square.on.square")
                }
                .help("Duplicate presentation")
                Spacer()
                Button {
                    showingDeleteConfirmation = true
                } label: {
                    Image(systemName: "trash")
                }
                .disabled(store.plans.count <= 1)
                .help("Delete presentation")
            }
            .buttonStyle(.borderless)
            .padding(.horizontal, 10)
            .frame(height: 38)
            .disabled(isEditingDisabled)
        }
    }
}

private struct PlanDetailView: View {
    let plan: PresentationPlan
    @ObservedObject var store: PlanStore
    @ObservedObject var engine: TimerEngine
    let onStart: (PresentationPlan) -> Void
    let onShowOverlay: () -> Void
    let onEndSession: () -> Void

    @State private var draggedSegmentID: UUID?

    private var editingDisabled: Bool { engine.phase != .idle }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                TimerPreviewView(plan: plan, theme: store.theme)
                sectionsCard
                appearanceCard
            }
            .padding(28)
            .frame(maxWidth: 800)
            .frame(maxWidth: .infinity)
        }
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.35))
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 5) {
                    TextField("Presentation name", text: Binding(
                        get: { plan.name },
                        set: { value in store.updateSelectedPlan { $0.name = value } }
                    ))
                    .textFieldStyle(.plain)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .disabled(editingDisabled)
                    Text("\(plan.segments.count) sections · \(DurationFormat.editor(plan.totalSeconds)) total")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                timerControls
            }
            if let validation = plan.validationMessage {
                Label(validation, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.orange)
            }
        }
    }

    @ViewBuilder
    private var timerControls: some View {
        switch engine.phase {
        case .idle:
            Button {
                onStart(plan)
            } label: {
                Label("Start", systemImage: "play.fill")
                    .frame(minWidth: 72)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(plan.validationMessage != nil)
            .keyboardShortcut(.space, modifiers: [])
        case .running:
            HStack(spacing: 8) {
                Button("Show Timer", action: onShowOverlay)
                Button {
                    engine.pause()
                } label: {
                    Label("Pause", systemImage: "pause.fill")
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.space, modifiers: [])
                Button("End", role: .destructive, action: onEndSession)
            }
            .controlSize(.large)
        case .paused:
            HStack(spacing: 8) {
                Button("Show Timer", action: onShowOverlay)
                Button {
                    engine.resume()
                } label: {
                    Label("Resume", systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.space, modifiers: [])
                Button("End", role: .destructive, action: onEndSession)
            }
            .controlSize(.large)
        }
    }

    private var sectionsCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Label("Run of show", systemImage: "list.number")
                    .font(.headline)
                Spacer()
                Text("Drag to reorder")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(16)
            Divider()

            VStack(spacing: 0) {
                ForEach(Array(plan.segments.enumerated()), id: \.element.id) { index, segment in
                    SegmentEditorRow(
                        index: index,
                        segment: segment,
                        cumulativeSeconds: plan.segments.prefix(index + 1).reduce(0) { $0 + $1.durationSeconds },
                        canDelete: plan.segments.count > 1,
                        disabled: editingDisabled,
                        onUpdate: store.updateSegment,
                        onDelete: { store.deleteSegment(segment.id) },
                        onMoveUp: index > 0 ? { store.moveSegments(from: IndexSet(integer: index), to: index - 1) } : nil,
                        onMoveDown: index + 1 < plan.segments.count ? { store.moveSegments(from: IndexSet(integer: index), to: index + 2) } : nil
                    )
                    .onDrag {
                        draggedSegmentID = segment.id
                        return NSItemProvider(object: segment.id.uuidString as NSString)
                    }
                    .onDrop(
                        of: [UTType.text],
                        delegate: SegmentDropDelegate(
                            targetID: segment.id,
                            draggedID: $draggedSegmentID,
                            plan: plan,
                            store: store
                        )
                    )
                    if index + 1 < plan.segments.count { Divider().padding(.leading, 49) }
                }
            }

            Divider()
            Button(action: store.addSegment) {
                Label("Add section", systemImage: "plus")
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.accentColor)
            .padding(16)
            .disabled(editingDisabled)
        }
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 14).strokeBorder(.separator.opacity(0.6)) }
    }

    private var appearanceCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Timer appearance", systemImage: "paintpalette")
                .font(.headline)
            HStack(spacing: 12) {
                ForEach(OverlayTheme.allCases) { theme in
                    ThemeChoice(theme: theme, selected: store.theme == theme) {
                        store.theme = theme
                    }
                }
            }
            Toggle("Play a sound at each checkpoint", isOn: $store.soundEnabled)
            Toggle("Keep the timer above other windows", isOn: $store.alwaysOnTop)
        }
        .padding(16)
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 14).strokeBorder(.separator.opacity(0.6)) }
    }
}

private struct SegmentDropDelegate: DropDelegate {
    let targetID: UUID
    @Binding var draggedID: UUID?
    let plan: PresentationPlan
    let store: PlanStore

    func dropEntered(info: DropInfo) {
        guard let draggedID,
              draggedID != targetID,
              let from = plan.segments.firstIndex(where: { $0.id == draggedID }),
              let to = plan.segments.firstIndex(where: { $0.id == targetID }) else { return }
        store.moveSegments(from: IndexSet(integer: from), to: to > from ? to + 1 : to)
    }

    func performDrop(info: DropInfo) -> Bool {
        draggedID = nil
        return true
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }
}

private struct SegmentEditorRow: View {
    let index: Int
    let segment: Segment
    let cumulativeSeconds: Int
    let canDelete: Bool
    let disabled: Bool
    let onUpdate: (Segment) -> Void
    let onDelete: () -> Void
    let onMoveUp: (() -> Void)?
    let onMoveDown: (() -> Void)?

    @State private var durationText: String

    init(
        index: Int,
        segment: Segment,
        cumulativeSeconds: Int,
        canDelete: Bool,
        disabled: Bool,
        onUpdate: @escaping (Segment) -> Void,
        onDelete: @escaping () -> Void,
        onMoveUp: (() -> Void)?,
        onMoveDown: (() -> Void)?
    ) {
        self.index = index
        self.segment = segment
        self.cumulativeSeconds = cumulativeSeconds
        self.canDelete = canDelete
        self.disabled = disabled
        self.onUpdate = onUpdate
        self.onDelete = onDelete
        self.onMoveUp = onMoveUp
        self.onMoveDown = onMoveDown
        _durationText = State(initialValue: DurationFormat.editor(segment.durationSeconds))
    }

    var body: some View {
        HStack(spacing: 12) {
            Text("\(index + 1)")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(.secondary)
                .frame(width: 24, height: 24)
                .background(Color.secondary.opacity(0.10))
                .clipShape(Circle())

            TextField("Section title", text: Binding(
                get: { segment.title },
                set: { value in
                    var updated = segment
                    updated.title = value
                    onUpdate(updated)
                }
            ))
            .textFieldStyle(.plain)
            .font(.system(size: 14, weight: .medium))

            Text("at \(DurationFormat.editor(cumulativeSeconds))")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.tertiary)
                .frame(width: 70, alignment: .trailing)

            TextField("5:00", text: $durationText)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 13, design: .monospaced))
                .frame(width: 76)
                .onChange(of: durationText) { _, value in
                    guard let seconds = DurationFormat.parse(value) else { return }
                    var updated = segment
                    updated.durationSeconds = seconds
                    onUpdate(updated)
                }
                .overlay {
                    if DurationFormat.parse(durationText) == nil {
                        RoundedRectangle(cornerRadius: 5).stroke(Color.orange, lineWidth: 1)
                    }
                }

            Menu {
                if let onMoveUp { Button("Move up", action: onMoveUp) }
                if let onMoveDown { Button("Move down", action: onMoveDown) }
                Divider()
                Button("Delete", role: .destructive, action: onDelete)
                    .disabled(!canDelete)
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .frame(width: 26)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .disabled(disabled)
        .onChange(of: segment.durationSeconds) { _, value in
            let formatted = DurationFormat.editor(value)
            if DurationFormat.parse(durationText) != value { durationText = formatted }
        }
    }
}

private struct ThemeChoice: View {
    let theme: OverlayTheme
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 7) {
                ZStack {
                    TimerCardBackground(theme: theme, overtime: false)
                    Text("12:34")
                        .font(.system(size: 15, weight: .bold, design: .monospaced))
                        .foregroundStyle(ThemePalette.palette(for: theme).foreground)
                }
                .frame(height: 42)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(selected ? Color.accentColor : Color.secondary.opacity(0.25), lineWidth: selected ? 2 : 1)
                }
                Text(theme.displayName)
                    .font(.caption)
                    .foregroundStyle(selected ? Color.primary : Color.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(theme.displayName)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
