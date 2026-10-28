//
//  DayPalette.swift
//  TimezoneConverter
//

import SwiftUI

/// The day's color language: deep blue night, soft orange morning, dark
/// yellow midday, soft purple evening, blended progressively between them.
///
/// One palette answers both places the day is shown: the hour ruler's ticks
/// (each tick painted for its hour, so the strip itself becomes the
/// gradient) and each result row's time, so a glance says where in the day
/// every city sits. The values are tuned for the notch's dark surface — the
/// hues keep their identity without going black.
enum DayPalette {
    private struct RGB {
        let red: Double
        let green: Double
        let blue: Double

        var color: Color { Color(red: red, green: green, blue: blue) }
    }

    /// Deep blue.
    private static let night = RGB(red: 0.30, green: 0.45, blue: 0.95)
    /// Soft orange.
    private static let morning = RGB(red: 1.00, green: 0.68, blue: 0.32)
    /// Dark yellow, lifted to golden so it survives the dark surface.
    private static let midday = RGB(red: 1.00, green: 0.80, blue: 0.22)
    /// Soft purple.
    private static let evening = RGB(red: 0.74, green: 0.62, blue: 1.00)

    /// (hour, color) across 0–24; the space between stops interpolates. Each
    /// part of the day holds its color, with short ramps between — night
    /// 21–4.5, dawn into morning 6.5–9.5, midday 11–14.5, evening 16.5–19.
    private static let stops: [(hour: Double, rgb: RGB)] = [
        (0.0, night),
        (4.5, night),
        (6.5, morning),
        (9.5, morning),
        (11.0, midday),
        (14.5, midday),
        (16.5, evening),
        (19.0, evening),
        (21.0, night),
        (24.0, night)
    ]

    /// The color of a moment in the day. Fractional hours welcome — 6.25 is
    /// a quarter into the dawn ramp.
    static func color(atHour hour: Double) -> Color {
        let h = hour.truncatingRemainder(dividingBy: 24) < 0
            ? hour.truncatingRemainder(dividingBy: 24) + 24
            : hour.truncatingRemainder(dividingBy: 24)

        guard stops.count > 1 else { return night.color }
        for index in 0..<(stops.count - 1) {
            let stop = stops[index]
            let next = stops[index + 1]
            if h >= stop.hour && h <= next.hour {
                let span = next.hour - stop.hour
                let t = span > 0 ? min(max((h - stop.hour) / span, 0), 1) : 0
                return RGB(
                    red: stop.rgb.red + (next.rgb.red - stop.rgb.red) * t,
                    green: stop.rgb.green + (next.rgb.green - stop.rgb.green) * t,
                    blue: stop.rgb.blue + (next.rgb.blue - stop.rgb.blue) * t
                ).color
            }
        }
        return night.color
    }
}
