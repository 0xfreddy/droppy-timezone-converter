//
//  TimeQueryParser.swift
//  TimezoneConverter
//
//  Reads a typed line like "3pm New York", "tomorrow 9:30 berlin" or
//  "mon 10 utc+5:30" into a moment the converter can show.
//

import Foundation

/// What a parsed query says. The zone is optional — a query without one
/// converts in the source zone the picker already shows.
public struct ParsedTimeQuery: Equatable {
    /// 0...23.
    public let hour: Int
    /// 0...59.
    public let minute: Int
    /// Days from today in the source zone: 0 today, 1 tomorrow, up to 6 for
    /// a weekday.
    public let dayShift: Int
    /// The zone the query named, or nil to keep the picker's.
    public let zoneIdentifier: String?
}

/// Reads a typed line like "3pm New York", "tomorrow 9:30 berlin" or
/// "mon 10 utc+5:30" into a moment the converter can show. MainActor for the
/// same reason as `ZoneLibrary`: cached Regex patterns, main-actor callers.
@MainActor
enum TimeQueryParser {
    /// "9:30", "15:00", "9.30pm".
    private static let colonTime = #/\b(\d{1,2})[:.](\d{2})\s*(am|pm)?\b/#

    /// "3pm", "11 am".
    private static let meridiemTime = #/\b(\d{1,2})\s*(am|pm)\b/#

    /// A bare integer hour, when nothing more specific matched.
    private static let bareHour = #/\b(\d{1,2})\b/#

    private static let weekdays: [String: Int] = [
        "sunday": 1, "sun": 1,
        "monday": 2, "mon": 2,
        "tuesday": 3, "tue": 3, "tues": 3,
        "wednesday": 4, "wed": 4,
        "thursday": 5, "thu": 5, "thur": 5, "thurs": 5,
        "friday": 6, "fri": 6,
        "saturday": 7, "sat": 7
    ]

    /// Parses a query. `todayZone` anchors "today" and weekday names —
    /// "monday" said at 23:50 in Tokyo is already Tuesday in New York, and
    /// the answer should follow the zone the user is reading.
    static func parse(_ text: String, todayZone: TimeZone) -> ParsedTimeQuery? {
        // a.m./p.m. with periods, and European "9.30", into forms the
        // patterns below expect.
        var lowered = text.lowercased()
            .replacingOccurrences(of: "a.m.", with: "am")
            .replacingOccurrences(of: "p.m.", with: "pm")

        // Fixed offsets first, before zone words are stripped: "utc+5" is one
        // token and the word scanner would otherwise eat its "utc" half.
        var zoneIdentifier: String?
        if let fixed = ZoneLibrary.fixedOffset(in: lowered) {
            zoneIdentifier = fixed.match.identifier
            lowered = lowered.replacingOccurrences(of: fixed.matchedText, with: " ")
        }

        // Zone words out first so "new york" cannot leave a stray "york". The
        // scan works on normalized words but the remainder keeps the raw
        // ones — normalization strips ":" and ".", which the time patterns
        // still need ("9:30 berlin" must not arrive as "930").
        let rawWords = lowered.split(whereSeparator: { $0.isWhitespace || $0 == "," || $0 == "·" })
            .map(String.init)
        var normalizedWords = rawWords.map { ZoneLibrary.normalize($0) }
        if zoneIdentifier == nil {
            scan: for count in stride(from: min(3, normalizedWords.count), through: 1, by: -1) {
                for start in 0...(normalizedWords.count - count) {
                    let slice = normalizedWords[start..<(start + count)]
                    guard !slice.contains(where: { $0.isEmpty }) else { continue }
                    guard let match = ZoneLibrary.lookup(slice.joined()) else { continue }
                    zoneIdentifier = match.identifier
                    for index in start..<(start + count) { normalizedWords[index] = "" }
                    break scan
                }
            }
        }
        let remainder = zip(rawWords, normalizedWords)
            .filter { !$1.isEmpty }
            .map(\.0)
            .joined(separator: " ")

        // The time itself.
        var hour: Int?
        var minute = 0
        let tokens = Set(remainder.split(separator: " ").map(String.init))
        if let match = try? colonTime.firstMatch(in: remainder) {
            hour = Int(match.output.1)
            minute = Int(match.output.2) ?? 0
            if match.output.3 == "pm", hour! < 12 { hour! += 12 }
            if match.output.3 == "am", hour! == 12 { hour! = 0 }
        } else if let match = try? meridiemTime.firstMatch(in: remainder) {
            hour = Int(match.output.1)
            if match.output.2 == "pm", hour! < 12 { hour! += 12 }
            if match.output.2 == "am", hour! == 12 { hour! = 0 }
        } else if tokens.contains("noon") {
            hour = 12
        } else if tokens.contains("midnight") {
            hour = 0
        } else if let match = try? bareHour.firstMatch(in: remainder) {
            // A bare hour is read the way people say it: "3" in the middle of
            // a working day means the afternoon, "9" the morning. Anything
            // outside a 12-hour reading is taken literally on the 24-hour
            // clock, which is how "15" or "0" arrive.
            let bare = Int(match.output.1) ?? -1
            switch bare {
            case 1...7: hour = bare + 12
            case 8...11: hour = bare
            case 12: hour = 12
            case 0: hour = 0
            case 13...23: hour = bare
            default: return nil
            }
        }
        guard var foundHour = hour, (0...23).contains(foundHour), (0...59).contains(minute) else { return nil }

        // The day, if the query named one. Weekday tokens are matched whole so
        // "sweden" never reads as "wed"; the short and long forms of one day
        // are interchangeable, which is why either can win the scan.
        var dayShift = 0
        let mentionsNext = tokens.contains("next")
        if tokens.contains("tomorrow") || tokens.contains("tmr") || tokens.contains("tmrw") {
            dayShift = 1
        } else if !tokens.contains("today") {
            for (name, target) in weekdays where tokens.contains(name) {
                var calendar = Calendar(identifier: .gregorian)
                calendar.timeZone = todayZone
                let today = calendar.component(.weekday, from: Date())
                dayShift = (target - today + 7) % 7
                if mentionsNext && dayShift == 0 { dayShift = 7 }
                break
            }
        }

        foundHour = min(max(foundHour, 0), 23)
        return ParsedTimeQuery(hour: foundHour, minute: minute, dayShift: dayShift, zoneIdentifier: zoneIdentifier)
    }
}
