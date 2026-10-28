//
//  TimezoneConverterDroplet.swift
//  TimezoneConverter
//
//  A converter for one moment in time: pick or type a time in a source zone,
//  read it in every zone you keep. One expanded surface, opened from the
//  shelf; zones and the source persist between uses.
//

import Combine
import DroppyKit
import SwiftUI

/// The class Droppy's loader instantiates, named in the bundle's
/// `NSPrincipalClass`. Keep it empty: it runs before the host is ready.
@objc(TimezoneConverterPrincipal)
public final class TimezoneConverterPrincipal: NSObject, DropletPrincipal {
    public override init() { super.init() }
    @MainActor public func makeDroplet() -> AnyObject { TimezoneConverterDroplet() }
}

/// One zone the user keeps, for the results list.
public struct ZoneEntry: Codable, Hashable, Identifiable {
    public var id: String { identifier }
    /// A TimeZone identifier, for example `"Europe/Amsterdam"`.
    public let identifier: String
    /// The label shown instead of the identifier.
    public let label: String
}

/// One row of the results list.
struct ConversionResult: Identifiable {
    var id: String { identifier }
    let identifier: String
    let label: String
    let isSource: Bool
    /// "21:00", in this zone.
    let timeText: String
    /// The local hour as a fraction — 20.5 is half past eight in the
    /// evening — which picks the row's day color.
    let localHour: Double
    /// "+1d" or "−1d" when the local date is not the source date, else "".
    let offsetBadge: String
    /// Difference from the source zone at that moment, "+8h" / "−5h30".
    let deltaText: String
}

/// Timezone Converter.
@MainActor
public final class TimezoneConverterDroplet: NSObject, ObservableObject, Droplet {
    /// Must equal `DroppyDropletID` in the bundle's Info.plist and `id` in
    /// droplet.json. The loader refuses the bundle if the three disagree.
    public nonisolated static let id: DropletID = "timezone-converter"

    private var host: DropletHost?

    // MARK: State

    /// The moment under conversion, as wall-clock components in the source
    /// zone. Wall-clock rather than a Date on purpose: when the source zone
    /// changes, 15:00 stays 15:00 — the whole point of the exercise — and
    /// only the instant it names moves. `activate` replaces these
    /// placeholder values with the user's persisted zones and now.
    @Published private(set) var wallClock: DateComponents = DateComponents()

    /// The zone the wall clock is read in.
    @Published private(set) var sourceZoneID: String = TimeZone.current.identifier

    /// The zones the results list shows.
    @Published private(set) var zones: [ZoneEntry] = TimezoneConverterDroplet.defaultZones

    /// Whether the surface is showing its zone editor. Lives here rather
    /// than in the view because the surface's height follows it.
    @Published var isEditingZones = false

    // MARK: Lifecycle

    public func activate(host: DropletHost) throws {
        self.host = host

        sourceZoneID = host.preferences.value(forKey: "sourceZone", as: String.self)
            ?? TimeZone.current.identifier
        zones = host.preferences.value(forKey: "zones", as: [ZoneEntry].self)
            ?? Self.defaultZones

        // Open on now, in the source zone: the surface is a world clock until
        // the user moves the time, which is also the most common conversion.
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = sourceTimeZone
        wallClock = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: Date())

        host.log.info("Timezone Converter activated: \(zones.count) zone\(zones.count == 1 ? "" : "s"), source \(sourceZoneID)")
    }

    public func deactivate() {
        // Everything activate() started is torn down here. This droplet
        // starts nothing ongoing — no timer runs while the surface is closed.
        host = nil
    }

    public static let defaultZones: [ZoneEntry] = [
        ZoneEntry(identifier: "Europe/London", label: "London"),
        ZoneEntry(identifier: "Europe/Amsterdam", label: "Amsterdam"),
        ZoneEntry(identifier: "America/New_York", label: "New York"),
        ZoneEntry(identifier: "Asia/Tokyo", label: "Tokyo")
    ]

    // MARK: Mutations

    /// Changes the source zone, keeping the wall clock as it reads: 15:00 in
    /// New York becomes 15:00 in Tokyo, and every result moves.
    public func setSource(_ identifier: String) {
        guard TimeZone(identifier: identifier) != nil else { return }
        sourceZoneID = identifier
        host?.preferences.setValue(identifier, forKey: "sourceZone")
    }

    /// Back to now, in the source zone.
    public func resetToNow() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = sourceTimeZone
        wallClock = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: Date())
    }

    /// Moves the selected date whole days in the source zone, keeping the
    /// time of day — the stepper around the rulers.
    public func shiftDay(_ delta: Int) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = sourceTimeZone
        var components = wallClock
        components.timeZone = sourceTimeZone
        guard let date = calendar.date(from: components),
              let shifted = calendar.date(byAdding: .day, value: delta, to: date) else { return }
        let day = calendar.dateComponents([.year, .month, .day], from: shifted)
        wallClock.year = day.year
        wallClock.month = day.month
        wallClock.day = day.day
    }

    /// Applies a parsed query: its zone (if any) becomes the source, and its
    /// time is set relative to today in that zone.
    public func apply(_ query: ParsedTimeQuery) {
        if let identifier = query.zoneIdentifier {
            setSource(identifier)
        }
        wallClock = resolvedComponents(for: query)
    }

    /// The wall clock a parsed query names, without touching state: today in
    /// the query's zone (the source zone when it names none) plus the query's
    /// day shift, with its hour and minute.
    ///
    /// The same math answers the preview line and the apply, so what the
    /// preview promises is what apply does.
    func resolvedComponents(for query: ParsedTimeQuery) -> DateComponents {
        let zone = TimeZone(identifier: query.zoneIdentifier ?? sourceZoneID) ?? sourceTimeZone
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        var components = calendar.dateComponents([.year, .month, .day], from: Date())
        if let base = calendar.date(from: components),
           let day = calendar.date(byAdding: .day, value: query.dayShift, to: base) {
            let shifted = calendar.dateComponents([.year, .month, .day], from: day)
            components.year = shifted.year
            components.month = shifted.month
            components.day = shifted.day
        }
        components.hour = query.hour
        components.minute = query.minute
        return components
    }

    /// The preview line for a parsed query, e.g.
    /// "Wed 28 Oct, 15:00 — New York · press ↩ to apply".
    func previewText(for query: ParsedTimeQuery) -> String {
        let zone = TimeZone(identifier: query.zoneIdentifier ?? sourceZoneID) ?? sourceTimeZone
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let dayText = calendar.date(from: resolvedComponents(for: query))
            .map { Format.day(in: zone).string(from: $0) } ?? ""
        let zoneName = label(for: query.zoneIdentifier ?? sourceZoneID)
        return "\(dayText), \(String(format: "%02d:%02d", query.hour, query.minute)) — \(zoneName) · press ↩ to apply"
    }

    public func addZone(identifier: String) {
        guard TimeZone(identifier: identifier) != nil else { return }
        guard !zones.contains(where: { $0.identifier == identifier }) else { return }
        let label = label(for: identifier)
        zones.append(ZoneEntry(identifier: identifier, label: label))
        host?.preferences.setValue(zones, forKey: "zones")
        host?.log.debug("added zone \(identifier)")
    }

    public func removeZone(_ identifier: String) {
        zones.removeAll { $0.identifier == identifier }
        host?.preferences.setValue(zones, forKey: "zones")
    }

    // MARK: Derived

    public var sourceTimeZone: TimeZone {
        TimeZone(identifier: sourceZoneID) ?? .current
    }

    /// The instant the wall clock names, resolved through the source zone.
    var instant: Date? {
        var components = wallClock
        components.timeZone = sourceTimeZone
        return Calendar(identifier: .gregorian).date(from: components)
    }

    /// The results list: the source zone first, then every kept zone except
    /// a repeat of the source.
    var results: [ConversionResult] {
        guard let instant else { return [] }
        let source = sourceTimeZone
        var rows = [result(for: sourceZoneID, label: label(for: sourceZoneID), isSource: true, instant: instant, source: source)]
        for entry in zones where entry.identifier != sourceZoneID {
            rows.append(result(for: entry.identifier, label: entry.label, isSource: false, instant: instant, source: source))
        }
        return rows
    }

    /// Two-way bindings for the ruler pickers, read and written through the
    /// source zone's wall clock.
    var hourBinding: Binding<Int> {
        Binding(
            get: { self.wallClock.hour ?? 0 },
            set: { self.wallClock.hour = min(max($0, 0), 23) }
        )
    }

    var minuteBinding: Binding<Int> {
        Binding(
            get: { self.wallClock.minute ?? 0 },
            set: { self.wallClock.minute = min(max($0, 0), 59) }
        )
    }

    /// The selected date as the stepper shows it, in the source zone.
    var dayText: String {
        instant.map { Format.day(in: sourceTimeZone).string(from: $0) } ?? ""
    }

    /// The neutral step cue, one per ruler block.
    func playTick() {
        host?.feedback.play(.tick)
    }

    /// The display label for an identifier: the city for IANA zones, a
    /// readable offset for the fixed zones the parser mints.
    func label(for identifier: String) -> String {
        if ZoneLibrary.isFixedOffset(identifier) {
            return ZoneLibrary.label(forFixedOffsetIdentifier: identifier)
        }
        return ZoneLibrary.label(for: identifier)
    }

    private func result(
        for identifier: String,
        label: String,
        isSource: Bool,
        instant: Date,
        source: TimeZone
    ) -> ConversionResult {
        let timeZone = TimeZone(identifier: identifier) ?? source
        let formatter = Format.time(in: timeZone)

        // The day difference is calendar days between midnights, not the raw
        // offset: 23:30 in New York is already the next date in Tokyo even
        // though the offset never crossed a boundary.
        var sourceCalendar = Calendar(identifier: .gregorian)
        sourceCalendar.timeZone = source
        var targetCalendar = Calendar(identifier: .gregorian)
        targetCalendar.timeZone = timeZone
        let sourceDay = sourceCalendar.startOfDay(for: instant)
        let targetDay = targetCalendar.startOfDay(for: instant)
        let dayDelta = sourceCalendar.dateComponents([.day], from: sourceDay, to: targetDay).day ?? 0

        let seconds = timeZone.secondsFromGMT(for: instant) - source.secondsFromGMT(for: instant)
        let clock = targetCalendar.dateComponents([.hour, .minute], from: instant)
        let localHour = Double(clock.hour ?? 0) + Double(clock.minute ?? 0) / 60
        return ConversionResult(
            identifier: identifier,
            label: label,
            isSource: isSource,
            timeText: formatter.string(from: instant),
            localHour: localHour,
            offsetBadge: dayDelta == 0 ? "" : (dayDelta > 0 ? "+\(dayDelta)d" : "\(dayDelta)d"),
            deltaText: Format.delta(seconds)
        )
    }
}

// MARK: - Expanded surface

extension TimezoneConverterDroplet: ExpandedSurfaceProviding {
    public var expandedSurfaces: [ExpandedSurfaceDescriptor] {
        [
            ExpandedSurfaceDescriptor(
                id: "convert",
                title: "Timezone Converter",
                systemImage: "clock.arrow.circlepath",
                // shelfWidgets: the form replaces the widget row while it is
                // up. autoCollapse: the user is often mid-typing, and a
                // pointer-outside timer collapsing the shelf under a focused
                // field would eat the query.
                suppresses: [.shelfWidgets, .autoCollapse]
            )
        ]
    }

    public func makeExpandedSurfaceView(_ id: ExpandedSurfaceID, context: ExpandedSurfaceContext) -> AnyView {
        AnyView(ConverterSurfaceView(droplet: self, context: context))
    }

    public func expandedSurfaceSize(_ id: ExpandedSurfaceID, fitting proposal: ExpandedSurfaceSizeProposal) -> CGSize? {
        // Content area, which the host then clamps: header, the results list
        // that takes the slack, the day stepper and two rulers, the query row
        // and its preview, and the editor when it is open.
        let rows = CGFloat(results.count)
        let editing = isEditingZones ? 176.0 : 0
        let height = 268 + rows * 34 + editing
        return CGSize(
            width: proposal.standardSize.width,
            height: min(max(height, 320), proposal.maximumSize.height)
        )
    }

    public func expandedSurfaceDidDismiss(
        _ id: ExpandedSurfaceID,
        presentation: ExpandedSurfacePresentation,
        reason: ExpandedSurfaceDismissalReason
    ) {
        // Close the editor with the surface, so a reopened converter starts
        // on the results, which is what it is for.
        isEditingZones = false
        host?.log.debug("surface dismissed: \(reason)")
    }
}

extension TimezoneConverterDroplet: ExpandedSurfaceHosting {
    /// The droplet is its own provider: one object, one surface.
    public var expandedSurfaceProvider: (any ExpandedSurfaceProviding)? { self }
}

// MARK: - Formatting

/// Formatters, cached per zone: building a DateFormatter is expensive enough
/// that a results list rebuild on every keystroke would feel it.
@MainActor
enum Format {
    private static var timeFormatters: [String: DateFormatter] = [:]
    private static var dayFormatters: [String: DateFormatter] = [:]

    static func time(in timeZone: TimeZone) -> DateFormatter {
        if let cached = timeFormatters[timeZone.identifier] { return cached }
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        formatter.timeZone = timeZone
        timeFormatters[timeZone.identifier] = formatter
        return formatter
    }

    static func day(in timeZone: TimeZone) -> DateFormatter {
        if let cached = dayFormatters[timeZone.identifier] { return cached }
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE d MMM"
        formatter.timeZone = timeZone
        dayFormatters[timeZone.identifier] = formatter
        return formatter
    }

    /// "+8h", "−5h30", "+30m" for a GMT-seconds difference. The minus sign is
    /// ASCII on purpose: this string is also what lands on the pasteboard.
    static func delta(_ seconds: Int) -> String {
        if seconds == 0 { return "±0" }
        let sign = seconds > 0 ? "+" : "-"
        let magnitude = abs(seconds)
        let hours = magnitude / 3600
        let minutes = (magnitude % 3600) / 60
        if hours == 0 { return "\(sign)\(minutes)m" }
        if minutes == 0 { return "\(sign)\(hours)h" }
        return "\(sign)\(hours)h\(minutes)"
    }
}
