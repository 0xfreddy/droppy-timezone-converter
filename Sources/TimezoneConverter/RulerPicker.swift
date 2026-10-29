//
//  RulerPicker.swift
//  TimezoneConverter
//
//  A horizontal tick ruler the user drags, scrolls or taps to pick a value —
//  the shape timer droplets use for durations: fixed needle at the centre,
//  ticks sliding under it, snapping in blocks, edges fading out.
//

import DroppyKit
import SwiftUI

/// A scrubbing ruler for integer values in a range.
///
/// The needle is fixed and centred; the strip moves under it. Ticks track
/// the pointer continuously, and each `snapStep * pxPerTick` of travel steps
/// the selection exactly one block — the strip never drifts out of alignment
/// with the needle. A drag that never moved is a tap, and jumps to the
/// nearest block. Trackpad scrolls feed the same travel, so dragging and
/// scrolling feel identical.
struct RulerPicker: View {
    /// Inclusive tick range, one minor tick per integer.
    let range: ClosedRange<Int>
    /// Label (and make taller) every value divisible by this.
    let labelEvery: Int
    /// Additional taller ticks between labels.
    let majorEvery: Int
    /// The selection moves in blocks of this many units.
    var snapStep: Int = 1
    @Binding var selection: Int
    /// Points of travel per unit.
    var pxPerTick: CGFloat
    /// When set, each tick is painted with this per-value color — the hour
    /// ruler's day gradient. Nil leaves the neutral surface tones.
    var palette: ((Int) -> Color)?
    /// Render the tick labels in the dot-matrix panel face (the theme's
    /// display font) instead of system type.
    var dotLabels = false
    /// Fired once per block the user moves the selection — the caller's cue
    /// to tick.
    var onStep: (() -> Void)?

    /// Travel since the last completed step, so ticks follow the pointer
    /// between steps. Positive: the strip is dragged to the right.
    @State private var travel: CGFloat = 0
    /// DragGesture reports cumulative translation, not increments; the
    /// previous report is what turns it into one.
    @State private var lastTranslation: CGFloat = 0
    /// The ruler's frame in SwiftUI's window space, for deciding whether a
    /// scroll event belongs to this ruler.
    @State private var frameInWindow: CGRect = .zero
    @State private var scrollMonitor: Any?

    var body: some View {
        GeometryReader { proxy in
            let centre = proxy.size.width / 2
            ZStack(alignment: .topLeading) {
                ForEach(range, id: \.self) { value in
                    tick(value, centre: centre)
                }

                // The needle: fixed, centred, the one element that neither
                // fades nor moves. It points up at the selected tick from
                // below the labels.
                Image(systemName: "arrowtriangle.up.fill")
                    .font(.system(size: 8))
                    .foregroundStyle(AdaptiveColors.notchSurfacePrimaryText)
                    .position(x: centre, y: 35)
            }
            .gesture(dragGesture(centre: proxy.size.width / 2))
        }
        .frame(height: 42)
        .contentShape(Rectangle())
        .background(
            // The frame the scroll monitor tests against. SwiftUI's .global
            // is the window's content space with y measured downward, which
            // is how the monitor converts the event location.
            GeometryReader { proxy in
                Color.clear
                    .onChange(of: proxy.frame(in: .global)) { _, frame in frameInWindow = frame }
                    .onAppear { frameInWindow = proxy.frame(in: .global) }
            }
        )
        .onAppear(perform: installScrollMonitor)
        .onDisappear(perform: removeScrollMonitor)
        .mask(
            // Ticks and labels dissolve at the ends so the strip reads as
            // running past the surface's edges.
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .black, location: 0.10),
                    .init(color: .black, location: 0.90),
                    .init(color: .clear, location: 1)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Value")
        .accessibilityValue("\(selection)")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: step(to: selection + snapStep)
            case .decrement: step(to: selection - snapStep)
            @unknown default: break
            }
        }
    }

    // MARK: Pieces

    private func isMajor(_ value: Int) -> Bool {
        value % labelEvery == 0 || value % majorEvery == 0
    }

    private func isLabeled(_ value: Int) -> Bool {
        value % labelEvery == 0
    }

    private func tick(_ value: Int, centre: CGFloat) -> some View {
        let isSelected = nearestBlock(to: value) == selection
        let falloff = max(0.35, 1 - Double(abs(value - selection)) * 0.12 / Double(max(snapStep, 1)))
        let paint = palette?(value) ?? AdaptiveColors.notchSurfaceSecondaryText

        return ZStack(alignment: .top) {
            Rectangle()
                .fill(paint.opacity(isSelected ? 1 : falloff))
                .frame(width: 1.5, height: isMajor(value) ? 17 : 10)

            if isLabeled(value) {
                Group {
                    if dotLabels {
                        DotMatrixText(
                            text: String(format: "%02d", value),
                            color: isSelected
                                ? (palette?(value) ?? DotMatrixText.amber)
                                : DotMatrixText.amber.opacity(isSelected ? 1 : 0.55),
                            pitch: 1.15
                        )
                    } else {
                        Text(String(format: "%02d", value))
                            .font(.system(size: 9, weight: isSelected ? .semibold : .regular))
                            .monospacedDigit()
                            .foregroundStyle(
                                isSelected
                                    ? AdaptiveColors.notchSurfacePrimaryText
                                    : AdaptiveColors.notchSurfaceTertiaryText.opacity(falloff)
                            )
                    }
                }
                .fixedSize()
                .offset(y: 21)
            }
        }
        .frame(width: 14, height: 32, alignment: .top)
        .position(
            x: centre + (CGFloat(value - selection) * pxPerTick) + travel,
            y: 16
        )
    }

    // MARK: Stepping

    /// The block boundary nearest a value, clamped to the range.
    private func nearestBlock(to value: Int) -> Int {
        let stepped = (Double(value) / Double(snapStep)).rounded() * Double(snapStep)
        return min(max(Int(stepped), range.lowerBound), range.upperBound)
    }

    /// Converts accumulated travel into steps. Shared by dragging and
    /// scrolling so both snap and tick identically.
    private func settleTravel() {
        let block = CGFloat(snapStep) * pxPerTick
        while travel >= block {
            let before = selection
            step(to: selection - snapStep)
            travel -= block
            if selection == before { travel = 0 } // clamped at the end: stop, don't bank travel
        }
        while travel <= -block {
            let before = selection
            step(to: selection + snapStep)
            travel += block
            if selection == before { travel = 0 }
        }
        clampTravelAtEnds()
    }

    /// The strip cannot slip past its last tick: at an end, travel that
    /// would drag the strip further off the span (and leave the needle
    /// hanging in blank space between steps) is dropped on arrival rather
    /// than banked and snapped back later.
    private func clampTravelAtEnds() {
        if selection == range.lowerBound, travel > 0 { travel = 0 }
        if selection == range.upperBound, travel < 0 { travel = 0 }
    }

    private func step(to value: Int) {
        let clamped = min(max(value, range.lowerBound), range.upperBound)
        guard clamped != selection else { return }
        selection = clamped
        onStep?()
    }

    // MARK: Drag

    private func dragGesture(centre: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let previous = lastTranslation
                lastTranslation = value.translation.width
                travel += value.translation.width - previous
                settleTravel()
            }
            .onEnded { value in
                travel = 0
                lastTranslation = 0

                // A drag that never moved is a tap: jump to the block under
                // the pointer.
                if abs(value.translation.width) < 2 {
                    let tapped = Int((CGFloat(selection) + (value.location.x - centre) / pxPerTick).rounded())
                    let block = nearestBlock(to: tapped)
                    if block != selection {
                        selection = block
                        onStep?()
                    }
                }
            }
    }

    // MARK: Trackpad scroll

    /// A local scroll monitor, rather than SwiftUI scroll modifiers: the
    /// package targets macOS 14, one version before `onScrollGeometryChanged`
    /// exists. The monitor sees every scroll event in the app; the ones over
    /// this ruler's frame are consumed here, everything else passes through
    /// untouched.
    private func installScrollMonitor() {
        guard scrollMonitor == nil else { return }
        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
            guard let content = event.window?.contentView,
                  frameInWindow.width > 0 else { return event }

            // AppKit location is bottom-left origin; the stored frame is
            // SwiftUI's window space, top-left origin. Flip, then test.
            let location = event.locationInWindow
            let flipped = CGPoint(x: location.x, y: content.frame.height - location.y)
            guard frameInWindow.contains(flipped) else { return event }

            // Vertical scrolls dominate, but a horizontal ruler invites
            // sideways two-finger drags; whichever axis the user commits to
            // wins, with the sign matching the drag direction.
            let deltaX = event.scrollingDeltaX
            let deltaY = event.scrollingDeltaY
            guard deltaX != 0 || deltaY != 0 else { return event }
            let delta = abs(deltaX) > abs(deltaY) ? -deltaX : deltaY

            travel += delta
            settleTravel()
            return nil
        }
    }

    private func removeScrollMonitor() {
        if let monitor = scrollMonitor {
            NSEvent.removeMonitor(monitor)
        }
        scrollMonitor = nil
    }
}
