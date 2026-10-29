//
//  ConverterSurfaceView.swift
//  TimezoneConverter
//

import DroppyKit
import SwiftUI

/// The converter: answers first, controls under them.
///
/// The results list takes the middle; the day stepper, the two rulers and
/// the query field sit at the bottom where the hand already is. The root
/// fills the rectangle the host hands it and the whole surface is forced
/// dark — it draws on the notch shelf, and the native controls (menus,
/// text fields) would otherwise follow the system scheme and land
/// light-on-light.
struct ConverterSurfaceView: View {
    @ObservedObject var droplet: TimezoneConverterDroplet
    let context: ExpandedSurfaceContext

    @State private var queryText = ""
    @State private var addZoneText = ""
    @FocusState private var queryFocused: Bool

    /// The parse of `queryText` as it stands, for the preview line. nil with
    /// text means "could not read it", nil without text means "nothing to say".
    private var liveParse: ParsedTimeQuery? {
        queryText.trimmingCharacters(in: .whitespaces).isEmpty
            ? nil
            : TimeQueryParser.parse(queryText, todayZone: droplet.sourceTimeZone)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DroppySpacing.md) {
            header

            Divider().overlay(AdaptiveColors.notchSurfaceCardFill)

            results

            if droplet.isEditingZones {
                ZoneEditorView(droplet: droplet, addZoneText: $addZoneText)
            }

            Spacer(minLength: 0)

            timeSelection

            Divider().overlay(AdaptiveColors.notchSurfaceCardFill)

            queryField

            previewLine
        }
        .padding(DroppySpacing.lg)
        .frame(
            width: context.availableSize.width,
            height: context.availableSize.height,
            alignment: .topLeading
        )
        .environment(\.colorScheme, .dark)
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: DroppySpacing.xsm) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 12, weight: .medium))
            if droplet.isDotMatrix {
                DotMatrixText(text: "Timezone Converter", pitch: 1.7)
                    .fixedSize()
            } else {
                Text("Timezone Converter")
                    .font(.system(size: 12, weight: .semibold))
            }
            Spacer(minLength: 0)
            Button {
                droplet.toggleTheme()
            } label: {
                Image(systemName: droplet.isDotMatrix ? "circle.grid.3x3.fill" : "circle.grid.3x3")
            }
            .buttonStyle(DroppyCircleButtonStyle(size: 20))
            .help(droplet.isDotMatrix ? "System type" : "Dot-matrix theme")
            .accessibilityLabel(droplet.isDotMatrix ? "Switch to system type" : "Switch to dot-matrix theme")
            Button("Now") {
                droplet.resetToNow()
                queryText = ""
            }
            .buttonStyle(DroppyQuietButtonStyle(size: .small))
            .help("Reset to the current time")
        }
        .foregroundStyle(AdaptiveColors.notchSurfaceSecondaryText)
    }

    // MARK: Results

    private var results: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(droplet.results) { row in
                    ResultRowView(row: row, dotMatrix: droplet.isDotMatrix)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: Time selection

    /// The day stepper and the two rulers. A scrubbed hour and minute read
    /// faster than a popover calendar, and the day rarely needs more
    /// than ‹ ›.
    private var timeSelection: some View {
        VStack(spacing: DroppySpacing.xsm) {
            HStack(spacing: DroppySpacing.xsm) {
                Button {
                    droplet.shiftDay(-1)
                } label: {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(DroppyCircleButtonStyle(size: 18))
                .help("Previous day")
                .accessibilityLabel("Previous day")

                Text(droplet.dayText)
                    .font(.system(size: 13, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(AdaptiveColors.notchSurfacePrimaryText)
                    .opacity(droplet.isDotMatrix ? 0 : 1)
                    .overlay {
                        if droplet.isDotMatrix {
                            DotMatrixText(text: droplet.dayText, color: .white, pitch: 1.8)
                                .fixedSize()
                        }
                    }
                    .frame(maxWidth: .infinity)

                Button {
                    droplet.shiftDay(1)
                } label: {
                    Image(systemName: "chevron.right")
                }
                .buttonStyle(DroppyCircleButtonStyle(size: 18))
                .help("Next day")
                .accessibilityLabel("Next day")
            }

            RulerPicker(
                range: 0...23,
                labelEvery: 3,
                majorEvery: 3,
                selection: droplet.hourBinding,
                pxPerTick: 16,
                palette: { hour in DayPalette.color(atHour: Double(hour)) },
                dotLabels: droplet.isDotMatrix,
                onStep: playTick
            )

            RulerPicker(
                range: 0...59,
                labelEvery: 15,
                majorEvery: 15,
                snapStep: 15,
                selection: droplet.minuteBinding,
                pxPerTick: 8,
                dotLabels: droplet.isDotMatrix,
                onStep: playTick
            )
        }
    }

    private func playTick() {
        guard !context.isPreview else { return }
        droplet.playTick()
    }

    // MARK: Query

    private var queryField: some View {
        HStack(spacing: DroppySpacing.sm) {
            HStack(spacing: DroppySpacing.xsm) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(AdaptiveColors.notchSurfaceTertiaryText)
                TextField("3pm New York · tomorrow 9:30 Berlin · mon 10 utc+5", text: $queryText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .foregroundStyle(AdaptiveColors.notchSurfacePrimaryText)
                    .focused($queryFocused)
                    .onSubmit(applyQuery)
                if !queryText.isEmpty {
                    Button {
                        queryText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(AdaptiveColors.notchSurfaceTertiaryText)
                    .help("Clear")
                    .accessibilityLabel("Clear query")
                }
            }
            .padding(.horizontal, DroppySpacing.sm)
            .padding(.vertical, DroppySpacing.xsm)
            .background(
                RoundedRectangle(cornerRadius: DroppyRadius.medium, style: .continuous)
                    .fill(AdaptiveColors.notchSurfaceCardFill)
            )

            Button(droplet.isEditingZones ? "Done" : "Edit") {
                droplet.isEditingZones.toggle()
                addZoneText = ""
            }
            .buttonStyle(DroppyQuietButtonStyle(size: .small))
            .help(droplet.isEditingZones ? "Close the zone editor" : "Edit your zone list")
        }
    }

    private func applyQuery() {
        guard let parsed = liveParse else { return }
        droplet.apply(parsed)
    }

    /// One line under the field saying how the query reads — the difference
    /// between a converter and a slot machine.
    @ViewBuilder
    private var previewLine: some View {
        let text = queryText.trimmingCharacters(in: .whitespaces)
        if text.isEmpty {
            EmptyView()
        } else if let parsed = liveParse {
            HStack(spacing: DroppySpacing.xsm) {
                Image(systemName: "arrow.turn.down.right")
                    .font(.system(size: 9, weight: .semibold))
                Text(droplet.previewText(for: parsed))
            }
            .font(.system(size: 11))
            .foregroundStyle(AdaptiveColors.notchSurfaceTertiaryText)
        } else {
            Text("Couldn't read that — try “9:30 Berlin” or “3pm New York”")
                .font(.system(size: 11))
                .foregroundStyle(AdaptiveColors.notchSurfaceTertiaryText)
        }
    }
}

// MARK: - One result

/// Label on the left, the answer on the right: the offset difference reads
/// as large as the time, because for a meeting the difference is the
/// question. In the dot theme the whole row is a flip-disc panel — labels
/// and deltas in amber, each city's time glowing in its part of the day.
private struct ResultRowView: View {
    let row: ConversionResult
    let dotMatrix: Bool

    var body: some View {
        HStack(spacing: DroppySpacing.sm) {
            Group {
                if dotMatrix {
                    DotMatrixText(text: row.label, pitch: 1.7).fixedSize()
                } else {
                    Text(row.label)
                        .font(.system(size: 14))
                        .foregroundStyle(AdaptiveColors.notchSurfaceSecondaryText)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: DroppySpacing.sm)

            if !row.offsetBadge.isEmpty {
                Group {
                    if dotMatrix {
                        DotMatrixText(text: row.offsetBadge, pitch: 1.1).fixedSize()
                    } else {
                        Text(row.offsetBadge)
                            .font(.system(size: 11, weight: .semibold))
                            .monospacedDigit()
                            .foregroundStyle(AdaptiveColors.notchSurfacePrimaryText)
                    }
                }
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(
                    Capsule().fill(AdaptiveColors.notchSurfaceCardFill)
                )
                .help("Local date differs from the source date")
            }

            Group {
                if dotMatrix {
                    DotMatrixText(
                        text: row.deltaText,
                        color: DotMatrixText.amber.opacity(row.isSource ? 0.55 : 0.85),
                        pitch: 1.5
                    ).fixedSize()
                } else {
                    Text(row.deltaText)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(row.isSource ? AdaptiveColors.notchSurfaceTertiaryText : AdaptiveColors.notchSurfaceSecondaryText)
                }
            }
            .frame(minWidth: 48, alignment: .trailing)

            Group {
                if dotMatrix {
                    DotMatrixText(
                        text: row.timeText,
                        color: DayPalette.color(atHour: row.localHour),
                        pitch: 2.2
                    ).fixedSize()
                } else {
                    Text(row.timeText)
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(DayPalette.color(atHour: row.localHour))
                        .frame(minWidth: 56, alignment: .trailing)
                }
            }
        }
        .padding(.vertical, DroppySpacing.xsm)
        .contentShape(Rectangle())
        .help("\(row.label): \(row.timeText) (\(row.deltaText) from source)")
    }
}

// MARK: - Zone editor

private struct ZoneEditorView: View {
    @ObservedObject var droplet: TimezoneConverterDroplet
    @Binding var addZoneText: String
    @FocusState private var addFocused: Bool

    private var suggestions: [ZoneLibrary.Match] {
        ZoneLibrary.suggestions(for: addZoneText)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DroppySpacing.sm) {
            Text("Your zones")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(AdaptiveColors.notchSurfaceTertiaryText)

            ForEach(droplet.zones) { zone in
                HStack(spacing: DroppySpacing.sm) {
                    Button {
                        droplet.removeZone(zone.identifier)
                    } label: {
                        Image(systemName: "minus.circle.fill")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(AdaptiveColors.notchSurfaceTertiaryText)
                    .help("Remove \(zone.label)")
                    .accessibilityLabel("Remove \(zone.label)")

                    Text(zone.label)
                        .font(.system(size: 13))
                        .foregroundStyle(AdaptiveColors.notchSurfaceSecondaryText)

                    Spacer(minLength: 0)

                    Text(droplet.results.first(where: { $0.identifier == zone.identifier })?.timeText ?? "")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(AdaptiveColors.notchSurfaceTertiaryText)
                }
            }

            HStack(spacing: DroppySpacing.xsm) {
                Image(systemName: "plus")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(AdaptiveColors.notchSurfaceTertiaryText)
                TextField("Add a city — Amsterdam, NYC, UTC+5:30…", text: $addZoneText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .foregroundStyle(AdaptiveColors.notchSurfacePrimaryText)
                    .focused($addFocused)
                    .onSubmit(applyFirstSuggestion)
            }
            .padding(.horizontal, DroppySpacing.sm)
            .padding(.vertical, DroppySpacing.xsm)
            .background(
                RoundedRectangle(cornerRadius: DroppyRadius.medium, style: .continuous)
                    .fill(AdaptiveColors.notchSurfaceCardFill)
            )

            if !addZoneText.trimmingCharacters(in: .whitespaces).isEmpty {
                if suggestions.isEmpty {
                    Text("No zone by that name — IANA cities, common aliases, and UTC offsets all work.")
                        .font(.system(size: 11))
                        .foregroundStyle(AdaptiveColors.notchSurfaceTertiaryText)
                } else {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(suggestions) { match in
                            Button {
                                droplet.addZone(identifier: match.identifier)
                                addZoneText = ""
                            } label: {
                                HStack {
                                    Text(match.label)
                                        .font(.system(size: 12))
                                        .foregroundStyle(AdaptiveColors.notchSurfacePrimaryText)
                                    Spacer(minLength: 0)
                                    Text(match.identifier)
                                        .font(.system(size: 10))
                                        .foregroundStyle(AdaptiveColors.notchSurfaceTertiaryText)
                                }
                                .padding(.vertical, DroppySpacing.xsm)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .padding(DroppySpacing.md)
        .background(
            RoundedRectangle(cornerRadius: DroppyRadius.medium, style: .continuous)
                .fill(AdaptiveColors.notchSurfaceCardFill.opacity(0.5))
        )
        .onAppear { addFocused = true }
    }

    private func applyFirstSuggestion() {
        guard let first = suggestions.first else { return }
        droplet.addZone(identifier: first.identifier)
        addZoneText = ""
    }
}
