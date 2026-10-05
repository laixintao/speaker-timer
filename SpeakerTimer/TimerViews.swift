import SwiftUI

struct ThemePalette {
    let foreground: Color
    let secondary: Color
    let accent: Color
    let track: Color

    static func palette(for theme: OverlayTheme, overtime: Bool = false) -> ThemePalette {
        if overtime {
            return ThemePalette(
                foreground: .white,
                secondary: Color.white.opacity(0.78),
                accent: Color(red: 1, green: 0.28, blue: 0.25),
                track: Color.white.opacity(0.15)
            )
        }
        switch theme {
        case .frostedDark:
            return ThemePalette(
                foreground: .white,
                secondary: Color.white.opacity(0.68),
                accent: Color(red: 0.30, green: 0.68, blue: 1.0),
                track: Color.white.opacity(0.14)
            )
        case .black:
            return ThemePalette(
                foreground: .white,
                secondary: Color.white.opacity(0.65),
                accent: Color(red: 0.40, green: 0.84, blue: 0.62),
                track: Color.white.opacity(0.14)
            )
        case .cream:
            return ThemePalette(
                foreground: Color(red: 0.12, green: 0.10, blue: 0.08),
                secondary: Color(red: 0.12, green: 0.10, blue: 0.08).opacity(0.62),
                accent: Color(red: 0.92, green: 0.38, blue: 0.16),
                track: Color.black.opacity(0.11)
            )
        case .blue:
            return ThemePalette(
                foreground: .white,
                secondary: Color.white.opacity(0.72),
                accent: Color(red: 0.55, green: 0.88, blue: 1.0),
                track: Color.white.opacity(0.17)
            )
        }
    }
}

struct TimerCardBackground: View {
    let theme: OverlayTheme
    let overtime: Bool

    var body: some View {
        Group {
            if overtime {
                LinearGradient(
                    colors: [Color(red: 0.45, green: 0.04, blue: 0.05), Color(red: 0.18, green: 0.015, blue: 0.02)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            } else {
                switch theme {
                case .frostedDark:
                    Rectangle()
                        .fill(.ultraThinMaterial)
                        .overlay(Color.black.opacity(0.43))
                case .black:
                    LinearGradient(colors: [.black, Color(red: 0.075, green: 0.075, blue: 0.085)], startPoint: .top, endPoint: .bottom)
                case .cream:
                    LinearGradient(
                        colors: [Color(red: 1.0, green: 0.975, blue: 0.90), Color(red: 0.94, green: 0.89, blue: 0.78)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                case .blue:
                    LinearGradient(
                        colors: [Color(red: 0.03, green: 0.54, blue: 0.96), Color(red: 0.06, green: 0.22, blue: 0.78)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                }
            }
        }
    }
}

struct SegmentedProgressBar: View {
    let plan: PresentationPlan
    let elapsedSeconds: TimeInterval
    let theme: OverlayTheme
    let overtime: Bool

    private let gap: CGFloat = 3

    var body: some View {
        GeometryReader { geometry in
            let count = plan.segments.count
            let available = max(0, geometry.size.width - CGFloat(max(0, count - 1)) * gap)
            let total = max(1, plan.totalSeconds)
            HStack(spacing: gap) {
                ForEach(Array(plan.segments.enumerated()), id: \.element.id) { index, segment in
                    let width = max(2, available * CGFloat(segment.durationSeconds) / CGFloat(total))
                    let fill = fillFraction(for: index)
                    ZStack(alignment: .leading) {
                        Capsule().fill(ThemePalette.palette(for: theme, overtime: overtime).track)
                        Capsule()
                            .fill(ThemePalette.palette(for: theme, overtime: overtime).accent)
                            .frame(width: width * fill)
                    }
                    .frame(width: width)
                    .accessibilityLabel("\(segment.title), \(DurationFormat.editor(segment.durationSeconds))")
                    .accessibilityValue("\(Int((fill * 100).rounded())) percent")
                }
            }
        }
    }

    private func fillFraction(for targetIndex: Int) -> CGFloat {
        if overtime { return 1 }
        var start = 0
        for (index, segment) in plan.segments.enumerated() {
            let end = start + segment.durationSeconds
            if index == targetIndex {
                return CGFloat(min(1, max(0, (elapsedSeconds - TimeInterval(start)) / TimeInterval(max(1, segment.durationSeconds)))))
            }
            start = end
        }
        return 0
    }
}

private struct AgendaHitRegions: PreferenceKey {
    static var defaultValue: [CGRect] { [] }
    static func reduce(value: inout [CGRect], nextValue: () -> [CGRect]) {
        value.append(contentsOf: nextValue())
    }
}

struct TimerDisplayView: View {
    @ObservedObject var engine: TimerEngine
    @ObservedObject var store: PlanStore
    var onInteractiveRegionsChange: ([CGRect]) -> Void = { _ in }
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geometry in
            let snapshot = engine.snapshot
            let palette = ThemePalette.palette(for: store.theme, overtime: snapshot.isOvertime)
            let radius = min(24, max(16, geometry.size.height * 0.12))
            ZStack(alignment: .topTrailing) {
                TimerCardBackground(theme: store.theme, overtime: snapshot.isOvertime)
                content(snapshot: snapshot, palette: palette, size: geometry.size)
                    .padding(.horizontal, max(18, geometry.size.width * 0.045))
                    .padding(.vertical, 20)
                    .padding(.bottom, 54)

                if let message = engine.transitionMessage {
                    HStack(spacing: 8) {
                        Image(systemName: snapshot.isOvertime ? "exclamationmark.circle.fill" : "arrow.right.circle.fill")
                            .foregroundStyle(snapshot.isOvertime ? Color.white : Color.yellow)
                        Text(message)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .background(snapshot.isOvertime
                            ? Color(red: 0.65, green: 0.04, blue: 0.06)
                            : Color(red: 0.035, green: 0.055, blue: 0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(snapshot.isOvertime ? Color.white : Color.yellow, lineWidth: 1.5)
                        }
                        .shadow(color: .black.opacity(0.35), radius: 8, y: 3)
                        .padding(12)
                        .transition(reduceMotion ? .opacity : .scale.combined(with: .opacity))
                        .accessibilityAddTraits(.isStaticText)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(Color.white.opacity(store.theme == .cream ? 0.28 : 0.13), lineWidth: 1)
            }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.22), value: engine.transitionMessage)
        }
        .coordinateSpace(name: "timerCard")
        .onPreferenceChange(AgendaHitRegions.self, perform: onInteractiveRegionsChange)
        .preferredColorScheme(store.theme == .cream ? .light : .dark)
    }

    @ViewBuilder
    private func content(snapshot: TimelineSnapshot, palette: ThemePalette, size: CGSize) -> some View {
        let fontSize = min(82, max(43, size.width * 0.155))
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(DurationFormat.clock(snapshot.elapsedSeconds))
                    .font(.system(size: fontSize, weight: .medium, design: .rounded).monospacedDigit())
                    .tracking(-2)
                    .foregroundStyle(palette.foreground)
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
                    .accessibilityLabel("Elapsed time")
                    .accessibilityValue(DurationFormat.clock(snapshot.elapsedSeconds))
                Spacer(minLength: 6)
                if snapshot.isOvertime {
                    Text("+" + DurationFormat.clock(snapshot.overtimeSeconds))
                        .font(.system(size: max(12, fontSize * 0.22), weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(Color.red.opacity(0.78))
                        .clipShape(Capsule())
                }
            }

            HStack(alignment: .center, spacing: 8) {
                Circle()
                    .fill(snapshot.isOvertime ? Color.red : palette.accent)
                    .frame(width: 8, height: 8)
                Text(snapshot.currentTitle)
                    .font(.system(size: max(14, min(22, size.width * 0.045)), weight: .semibold, design: .rounded))
                    .foregroundStyle(palette.foreground)
                    .lineLimit(1)
                Spacer(minLength: 8)
                if !snapshot.isOvertime {
                    Text(nextText(snapshot))
                        .font(.system(size: max(11, min(14, size.width * 0.03)), weight: .medium, design: .rounded).monospacedDigit())
                        .foregroundStyle(palette.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                } else {
                    Text("OVERTIME")
                        .font(.system(size: 11, weight: .heavy, design: .rounded))
                        .tracking(1.3)
                        .foregroundStyle(palette.secondary)
                }
            }

            if let plan = engine.activePlan {
                SegmentedProgressBar(
                    plan: plan,
                    elapsedSeconds: snapshot.elapsedSeconds,
                    theme: store.theme,
                    overtime: snapshot.isOvertime
                )
                .frame(height: max(8, min(12, size.height * 0.075)))

                HStack {
                    Text("AGENDA")
                        .tracking(2)
                    Spacer()
                    Text(DurationFormat.editor(plan.totalSeconds) + " TOTAL")
                }
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(palette.secondary)
                .padding(.top, 4)

                ScrollView {
                    VStack(spacing: 4) {
                        ForEach(Array(plan.segments.enumerated()), id: \.element.id) { index, segment in
                            let start = plan.segments.prefix(index).reduce(0) { $0 + $1.durationSeconds }
                            let current = snapshot.currentSegmentIndex == index && !snapshot.isOvertime
                            let completed = snapshot.elapsedSeconds >= Double(start + segment.durationSeconds)
                            Button {
                                engine.jump(toSegment: segment.id)
                            } label: {
                              HStack(spacing: 10) {
                                Image(systemName: completed ? "checkmark.circle.fill" : current ? "play.circle.fill" : "circle")
                                    .foregroundStyle(current || completed ? palette.accent : palette.secondary)
                                    .frame(width: 16)
                                Text(segment.title)
                                    .fontWeight(current ? .semibold : .regular)
                                    .fixedSize(horizontal: false, vertical: true)
                                Spacer(minLength: 8)
                                Text(DurationFormat.clock(Double(start)) + " – " + DurationFormat.clock(Double(start + segment.durationSeconds)))
                                    .font(.system(size: 11, weight: .medium, design: .rounded).monospacedDigit())
                                    .foregroundStyle(palette.secondary)
                            }
                            .font(.system(size: 13, design: .rounded))
                            .foregroundStyle(palette.foreground)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(current ? palette.track : Color.clear)
                            .clipShape(RoundedRectangle(cornerRadius: 9))
                            .contentShape(Rectangle())
                            }
                            .buttonStyle(AgendaButtonStyle(tint: palette.foreground))
                            .background {
                                GeometryReader { row in
                                    Color.clear.preference(key: AgendaHitRegions.self,
                                                           value: [row.frame(in: .named("timerCard"))])
                                }
                            }
                            .help("Jump to \(segment.title) at \(DurationFormat.clock(Double(start)))")
                            .accessibilityLabel("Jump to \(segment.title)")
                            .accessibilityValue(current ? "Current section" : DurationFormat.clock(Double(start)))
                        }
                    }
                }
            }
        }
    }

    private func nextText(_ snapshot: TimelineSnapshot) -> String {
        let time = DurationFormat.remaining(snapshot.secondsUntilBoundary)
        if let next = snapshot.nextTitle {
            return "Next: \(next) in \(time)"
        }
        return "Ends in \(time)"
    }
}

private struct AgendaButtonStyle: ButtonStyle {
    let tint: Color
    @State private var hovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(tint.opacity(configuration.isPressed ? 0.20 : hovered ? 0.10 : 0))
            .clipShape(RoundedRectangle(cornerRadius: 9))
            .overlay {
                RoundedRectangle(cornerRadius: 9)
                    .strokeBorder(tint.opacity(hovered ? 0.22 : 0), lineWidth: 1)
            }
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .onHover { hovered = $0 }
    }
}

struct TimerPreviewView: View {
    let plan: PresentationPlan
    let theme: OverlayTheme

    var body: some View {
        let palette = ThemePalette.palette(for: theme)
        ZStack {
            TimerCardBackground(theme: theme, overtime: false)
            VStack(alignment: .leading, spacing: 9) {
                Text("12:37")
                    .font(.system(size: 48, weight: .medium, design: .rounded).monospacedDigit())
                    .tracking(-1.5)
                    .foregroundStyle(palette.foreground)
                HStack {
                    Circle().fill(palette.accent).frame(width: 7, height: 7)
                    Text(plan.segments.first?.title ?? "Ready")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(palette.foreground)
                        .lineLimit(1)
                    Spacer()
                    Text("Next checkpoint")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(palette.secondary)
                }
                SegmentedProgressBar(plan: plan, elapsedSeconds: min(757, TimeInterval(plan.totalSeconds)), theme: theme, overtime: false)
                    .frame(height: 8)
            }
            .padding(18)
        }
        .frame(height: 144)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: .black.opacity(0.16), radius: 18, y: 8)
    }
}
