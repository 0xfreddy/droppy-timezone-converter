//
//  ZoneLibrary.swift
//  TimezoneConverter
//
//  The catalogue of zones a query or the add-zone field can name, and how
//  plain text finds its way into it.
//

import Foundation

/// Zone lookup: every IANA identifier by its last path component, plus the
/// city names and short forms people actually type that are not components
/// ("beijing" is not a zone; "nyc" is not anything).
///
/// MainActor because the cached Regex patterns are not Sendable, and every
/// caller — the droplet and its views — is on the main actor anyway.
@MainActor
enum ZoneLibrary {
    /// One resolvable place.
    struct Match: Hashable, Identifiable {
        let identifier: String
        let label: String
        var id: String { identifier }
    }

    /// Normalized alias → identifier. Keys are lowercase ASCII letters and
    /// digits only, spaces removed, so "New York" and "newyork" are the same
    /// key as "NEW YORK".
    private static let aliases: [String: String] = [
        // United States
        "nyc": "America/New_York",
        "newyork": "America/New_York",
        "manhattan": "America/New_York",
        "boston": "America/New_York",
        "philadelphia": "America/New_York",
        "atlanta": "America/New_York",
        "miami": "America/New_York",
        "detroit": "America/New_York",
        "pittsburgh": "America/New_York",
        "dc": "America/New_York",
        "washingtondc": "America/New_York",
        "la": "America/Los_Angeles",
        "lax": "America/Los_Angeles",
        "losangeles": "America/Los_Angeles",
        "sanfrancisco": "America/Los_Angeles",
        "sf": "America/Los_Angeles",
        "bayarea": "America/Los_Angeles",
        "seattle": "America/Los_Angeles",
        "portland": "America/Los_Angeles",
        "vegas": "America/Los_Angeles",
        "lasvegas": "America/Los_Angeles",
        "austin": "America/Chicago",
        "dallas": "America/Chicago",
        "houston": "America/Chicago",
        "nashville": "America/Chicago",
        "saltlakecity": "America/Denver",
        "slc": "America/Denver",
        "boise": "America/Boise",
        "calgary": "America/Edmonton",
        // Canada
        "montreal": "America/Toronto",
        "quebec": "America/Toronto",
        // Latin America
        "rio": "America/Sao_Paulo",
        "riodejaneiro": "America/Sao_Paulo",
        "rj": "America/Sao_Paulo",
        "cdmx": "America/Mexico_City",
        "mexicocity": "America/Mexico_City",
        // Europe
        "munich": "Europe/Berlin",
        "frankfurt": "Europe/Berlin",
        "bern": "Europe/Zurich",
        "geneva": "Europe/Zurich",
        "lausanne": "Europe/Zurich",
        "capetown": "Africa/Johannesburg",
        "joburg": "Africa/Johannesburg",
        "kiev": "Europe/Kyiv",
        // Middle East & South Asia
        "telaviv": "Asia/Jerusalem",
        "doha": "Asia/Qatar",
        "mumbai": "Asia/Kolkata",
        "bombay": "Asia/Kolkata",
        "delhi": "Asia/Kolkata",
        "newdelhi": "Asia/Kolkata",
        "bangalore": "Asia/Kolkata",
        "bengaluru": "Asia/Kolkata",
        "pune": "Asia/Kolkata",
        "islamabad": "Asia/Karachi",
        // East Asia
        "beijing": "Asia/Shanghai",
        "shenzhen": "Asia/Shanghai",
        "hangzhou": "Asia/Shanghai",
        "hk": "Asia/Hong_Kong",
        "hongkong": "Asia/Hong_Kong",
        "kl": "Asia/Kuala_Lumpur",
        "kualalumpur": "Asia/Kuala_Lumpur",
        "saigon": "Asia/Ho_Chi_Minh",
        "hanoi": "Asia/Ho_Chi_Minh",
        "osaka": "Asia/Tokyo",
        "kyoto": "Asia/Tokyo",
        // Oceania
        "nz": "Pacific/Auckland",
        "wellington": "Pacific/Auckland",
        "christchurch": "Pacific/Auckland",
        // Fixed standards
        "utc": "UTC",
        "gmt": "UTC",
        "ut": "UTC",
        "z": "UTC",
        "zulu": "UTC"
    ]

    /// Normalized last path component → identifier. Built once; collisions
    /// (there are a few, buried regional identifiers) keep the first, which
    /// `knownTimeZoneIdentifiers` orders canonically.
    private static let byComponent: [String: String] = {
        var map: [String: String] = [:]
        for identifier in TimeZone.knownTimeZoneIdentifiers {
            let key = normalize(identifier.split(separator: "/").last.map(String.init) ?? identifier)
            if map[key] == nil { map[key] = identifier }
        }
        return map
    }()

    /// Every alias key, for suggestions.
    private static let aliasKeys: [String] = Array(aliases.keys)
    /// Every component key, for suggestions.
    private static let componentKeys: [String] = Array(byComponent.keys)

    /// Lowercase ASCII letters and digits only — the form every lookup key
    /// and every query word is reduced to before comparison.
    static func normalize(_ text: String) -> String {
        String(text.lowercased().unicodeScalars.filter { ("a"..."z").contains($0) || ("0"..."9").contains($0) }.map(Character.init))
    }

    /// The last path component of an identifier, underscores as spaces.
    static func label(for identifier: String) -> String {
        let last = identifier.split(separator: "/").last.map(String.init) ?? identifier
        return last.replacingOccurrences(of: "_", with: " ")
    }

    /// Exact lookup for one normalized token or joined phrase.
    static func lookup(_ normalized: String) -> Match? {
        guard !normalized.isEmpty else { return nil }
        guard let identifier = aliases[normalized] ?? byComponent[normalized] else { return nil }
        return Match(identifier: identifier, label: label(for: identifier))
    }

    /// True when the identifier is one of the fixed offsets the parser mints
    /// for "utc+5:30" style input, whose labels need their own formatting.
    static func isFixedOffset(_ identifier: String) -> Bool {
        identifier.hasPrefix("GMT+") || identifier.hasPrefix("GMT-")
    }

    /// "utc+5:30", "gmt-3" — the fixed-offset mentions a query can carry.
    private static let offsetPattern = #/(?:utc|gmt)\s*([+-])\s*(\d{1,2})(?::(\d{2}))?/#

    /// "GMT+5:30" for a fixed offset — the identifier form ICU accepts and
    /// reconstructs on its own — or nil for offsets outside ±24h.
    static func fixedOffsetIdentifier(seconds: Int) -> String? {
        guard abs(seconds) < 24 * 3600 else { return nil }
        let sign = seconds < 0 ? "-" : "+"
        let magnitude = abs(seconds)
        let hours = magnitude / 3600
        let minutes = (magnitude % 3600) / 60
        let minutesPart = minutes == 0 ? "" : String(format: ":%02d", minutes)
        return "GMT\(sign)\(hours)\(minutesPart)"
    }

    /// A display label for a fixed offset, whose identifier would otherwise
    /// read as "GMT+0530" next to city names.
    static func label(forFixedOffsetIdentifier identifier: String) -> String {
        guard let match = try? offsetPattern.firstMatch(in: identifier.lowercased()) else {
            return identifier
        }
        let sign = match.output.1 == "-" ? "-" : "+"
        let hours = Int(match.output.2) ?? 0
        let minutes = Int(match.output.3 ?? "0") ?? 0
        let minutesPart = minutes == 0 ? "" : String(format: ":%02d", minutes)
        return "UTC\(sign)\(hours)\(minutesPart)"
    }

    /// The fixed offset a piece of text names, if any, and the text it used.
    /// Both the query field ("3pm utc+5") and the add-zone field ("UTC+5:30")
    /// go through here.
    static func fixedOffset(in text: String) -> (match: Match, matchedText: String)? {
        guard let found = try? offsetPattern.firstMatch(in: text.lowercased())
        else { return nil }
        let sign = found.output.1 == "-" ? -1 : 1
        let hours = Int(found.output.2) ?? 0
        let minutes = Int(found.output.3 ?? "0") ?? 0
        let identifier = fixedOffsetIdentifier(seconds: sign * (hours * 3600 + minutes * 60))
        guard let identifier, TimeZone(identifier: identifier) != nil else { return nil }
        let label = label(forFixedOffsetIdentifier: identifier)
        return (Match(identifier: identifier, label: label), String(found.output.0))
    }

    /// Add-zone suggestions for a partial query: a typed fixed offset first,
    /// then prefixes, then substrings once the query is long enough to be
    /// selective.
    static func suggestions(for text: String, limit: Int = 5) -> [Match] {
        let query = normalize(text)
        guard query.count >= 2 else { return [] }

        var matches: [Match] = []
        if let fixed = fixedOffset(in: text), !fixed.matchedText.trimmingCharacters(in: .whitespaces).isEmpty {
            matches.append(fixed.match)
        }

        var seen = Set(matches.map(\.identifier))
        var prefixes: [Match] = []
        var contains: [Match] = []

        for key in aliasKeys {
            guard let identifier = aliases[key], !seen.contains(identifier) else { continue }
            let match = Match(identifier: identifier, label: label(for: identifier))
            if key.hasPrefix(query) {
                prefixes.append(match)
                seen.insert(identifier)
            } else if query.count >= 2 && key.contains(query) {
                contains.append(match)
                seen.insert(identifier)
            }
        }
        for key in componentKeys {
            guard let identifier = byComponent[key], !seen.contains(identifier) else { continue }
            let match = Match(identifier: identifier, label: label(for: identifier))
            if key.hasPrefix(query) {
                prefixes.append(match)
                seen.insert(identifier)
            } else if query.count >= 2 && key.contains(query) {
                contains.append(match)
                seen.insert(identifier)
            }
        }

        func sortedByLabel(_ list: [Match]) -> [Match] {
            list.sorted { $0.label.localizedCaseInsensitiveCompare($1.label) == .orderedAscending }
        }
        matches.append(contentsOf: sortedByLabel(prefixes) + sortedByLabel(contains))
        return Array(matches.prefix(limit))
    }
}
