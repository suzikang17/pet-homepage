// ios/PetHomepage/DesignSystem/ClockTimePicker.swift
import SwiftUI
import UIKit

/// A draggable analog clock face for setting a time of day. Both hands are grabbable; the
/// minute hand snaps to 5-minute marks (so landing an exact time is a coarse flick, not a
/// fiddly nudge) and the hour hand snaps to the 12 hour ticks. AM/PM lives outside the face
/// (it can't be read off a 12-hour dial) — this view preserves whichever half of the day the
/// bound `hour` already encodes.
///
/// Bindings are a 24-hour `hour` (0...23) and `minute` (0...59); the dial itself is 12-hour.
struct ClockTimePicker: View {
    @Binding var hour: Int
    @Binding var minute: Int

    /// Which hand the in-flight drag grabbed. Decided once at drag start (nearest knob) and
    /// held for the gesture, so a hand can't be "stolen" mid-drag when the hands cross.
    private enum Hand { case hour, minute }
    @State private var activeHand: Hand?

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
            let radius = side / 2
            let minuteKnob = point(center: center, radius: radius * 0.72, angleDeg: minuteAngle)
            let hourKnob = point(center: center, radius: radius * 0.48, angleDeg: hourAngle)

            // Everything is positioned in the reader's own coordinate space (the same space the
            // drag reports touches in), so the ZStack fills the reader rather than being sized
            // to the circle — otherwise hands/labels would drift when width ≠ height.
            ZStack {
                Circle()
                    .fill(Theme.card)
                    .overlay(Circle().stroke(Theme.primary.opacity(0.12), lineWidth: 2))
                    .frame(width: radius * 2, height: radius * 2)
                    .shadow(color: Theme.shadow.opacity(0.06), radius: 12, y: 4)
                    .position(center)

                hourLabels(center: center, radius: radius * 0.82)

                // Minute hand (long) then hour hand (short) on top.
                hand(from: center, to: minuteKnob, width: 5, color: Theme.primary.opacity(0.55))
                hand(from: center, to: hourKnob, width: 7, color: Theme.primary)

                knob(at: hourKnob, diameter: 34, fill: Theme.primary)
                knob(at: minuteKnob, diameter: 28, fill: Theme.primary.opacity(0.55))

                Circle().fill(Theme.primary).frame(width: 12, height: 12).position(center)
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if activeHand == nil {
                            activeHand = distance(value.location, minuteKnob)
                                <= distance(value.location, hourKnob) ? .minute : .hour
                        }
                        let deg = angleDegrees(from: center, to: value.location)
                        switch activeHand {
                        case .minute: setMinute(fromAngle: deg)
                        case .hour: setHour12(fromAngle: deg)
                        case .none: break
                        }
                    }
                    .onEnded { _ in activeHand = nil }
            )
            .accessibilityIdentifier("clockPicker")
        }
    }

    // MARK: - Hand angles (degrees, 0° at 12 o'clock, clockwise)

    private var minuteAngle: Double { Double(minute) * 6 }
    private var hourAngle: Double { Double(hour % 12) * 30 + Double(minute) * 0.5 }

    // MARK: - Drag → value

    private func setMinute(fromAngle deg: Double) {
        // Nearest 5-minute mark; 60 wraps back to 0.
        let snapped = (Int((deg / 6 / 5).rounded()) * 5) % 60
        if snapped != minute {
            minute = snapped
            tick()
        }
    }

    private func setHour12(fromAngle deg: Double) {
        var h12 = Int((deg / 30).rounded()) % 12 // 0 == 12 o'clock
        if h12 == 0 { h12 = 12 }
        let newHour = combine(h12: h12, pm: hour >= 12)
        if newHour != hour {
            hour = newHour
            tick()
        }
    }

    /// Folds a 12-hour dial reading back into 24-hour time, keeping the current AM/PM half.
    private func combine(h12: Int, pm: Bool) -> Int {
        if h12 == 12 { return pm ? 12 : 0 }
        return pm ? h12 + 12 : h12
    }

    // MARK: - Geometry helpers

    private func point(center: CGPoint, radius: CGFloat, angleDeg: Double) -> CGPoint {
        let rad = angleDeg * .pi / 180
        return CGPoint(x: center.x + radius * CGFloat(sin(rad)),
                       y: center.y - radius * CGFloat(cos(rad)))
    }

    private func angleDegrees(from center: CGPoint, to p: CGPoint) -> Double {
        let dx = Double(p.x - center.x)
        let dy = Double(p.y - center.y)
        var deg = atan2(dx, -dy) * 180 / .pi
        if deg < 0 { deg += 360 }
        return deg
    }

    private func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        hypot(a.x - b.x, a.y - b.y)
    }

    private func tick() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    // MARK: - Subviews

    private func hourLabels(center: CGPoint, radius: CGFloat) -> some View {
        ForEach(1...12, id: \.self) { h in
            let p = point(center: center, radius: radius, angleDeg: Double(h % 12) * 30)
            Text("\(h)")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.inkSoft)
                .position(p)
        }
    }

    private func hand(from a: CGPoint, to b: CGPoint, width: CGFloat, color: Color) -> some View {
        Path { p in
            p.move(to: a)
            p.addLine(to: b)
        }
        .stroke(color, style: StrokeStyle(lineWidth: width, lineCap: .round))
    }

    private func knob(at p: CGPoint, diameter: CGFloat, fill: Color) -> some View {
        Circle()
            .fill(fill)
            .frame(width: diameter, height: diameter)
            .overlay(Circle().stroke(.white.opacity(0.85), lineWidth: 2))
            .position(p)
    }
}

/// The modal that hosts the analog clock for a "done at" time: gradient header, a live digital
/// readout, the dial, and an AM/PM toggle. Returns the chosen (hour, minute) — the caller pins
/// it to the right day.
struct ClockTimeSheet: View {
    let title: String
    var systemImage: String = "clock"
    let subtitle: String
    /// The day the time is pinned to; used only to clamp against `clampTo`.
    let day: Date
    /// When set (a today completion), a chosen time later than this is pulled back to it — you
    /// can't have done something in the future. nil (past days) leaves any time selectable.
    var clampTo: Date? = nil
    let onSave: (_ hour: Int, _ minute: Int) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var hour: Int
    @State private var minute: Int

    private let calendar = Calendar.current

    init(title: String, systemImage: String = "clock", subtitle: String, day: Date,
         initialHour: Int, initialMinute: Int, clampTo: Date? = nil,
         onSave: @escaping (Int, Int) -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.subtitle = subtitle
        self.day = day
        self.clampTo = clampTo
        self.onSave = onSave
        _hour = State(initialValue: initialHour)
        // Snap the starting minute to the same 5-minute grid the dial uses.
        _minute = State(initialValue: (Int((Double(initialMinute) / 5).rounded()) * 5) % 60)
    }

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: title, systemImage: systemImage, confirmTitle: "Save",
                        onCancel: { dismiss() }, onConfirm: save)
            ScrollView {
                VStack(spacing: 22) {
                    Text(subtitle)
                        .font(.footnote).foregroundStyle(Theme.inkSoft)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Text(readout)
                        .font(.system(size: 40, weight: .heavy, design: .rounded))
                        .foregroundStyle(Theme.ink)
                        .monospacedDigit()
                        .accessibilityIdentifier("clockReadout")

                    ClockTimePicker(hour: $hour, minute: $minute)
                        .frame(height: 300)

                    Picker("", selection: amPM) {
                        Text("AM").tag(false)
                        Text("PM").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("clockAMPM")
                }
                .padding(.horizontal, 22)
                .padding(.vertical, 20)
            }
        }
        .background(Theme.bg)
        .tint(Theme.primary)
        .ignoresSafeArea(edges: .top)
        .presentationDragIndicator(.hidden)
    }

    /// AM/PM as a Bool binding that flips the 24-hour `hour` across the noon line.
    private var amPM: Binding<Bool> {
        Binding(get: { hour >= 12 }, set: { pm in
            if pm != (hour >= 12) { hour = (hour + 12) % 24 }
        })
    }

    private var readout: String {
        let base = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
        return base.formatted(.dateTime.hour().minute())
    }

    private func save() {
        var h = hour, m = minute
        if let clampTo,
           let chosen = calendar.date(bySettingHour: h, minute: m, second: 0, of: day),
           chosen > clampTo {
            h = calendar.component(.hour, from: clampTo)
            m = calendar.component(.minute, from: clampTo)
        }
        onSave(h, m)
        dismiss()
    }
}
