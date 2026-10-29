//
//  DotMatrixView.swift
//  TimezoneConverter
//

import SwiftUI

/// A 5×7 dot-matrix typeface, drawn dot by dot — the flip-disc panel look.
///
/// Every glyph is seven rows of five cells; a `Canvas` paints the lit dots
/// (with a soft halo) over the faint unlit grid, which is what makes the
/// panel read as hardware rather than as pixelated text. Monospaced by
/// construction, so tables of times align without any help.
enum DotFont {
    /// Glyph rows, top to bottom; `X` is a lit dot.
    private static let glyphs: [Character: [String]] = [
        " ": [".....", ".....", ".....", ".....", ".....", ".....", "....."],
        "0": [".XXX.", "X...X", "X..XX", "X.X.X", "XX..X", "X...X", ".XXX."],
        "1": ["..X..", ".XX..", "..X..", "..X..", "..X..", "..X..", ".XXX."],
        "2": [".XXX.", "X...X", "....X", "...X.", "..X..", ".X...", "XXXXX"],
        "3": ["XXXXX", "...X.", "..X..", "...X.", "....X", "X...X", ".XXX."],
        "4": ["...X.", "..XX.", ".X.X.", "X..X.", "XXXXX", "...X.", "...X."],
        "5": ["XXXXX", "X....", "XXXX.", "....X", "....X", "X...X", ".XXX."],
        "6": ["..XX.", ".X...", "X....", "XXXX.", "X...X", "X...X", ".XXX."],
        "7": ["XXXXX", "....X", "...X.", "..X..", ".X...", ".X...", ".X..."],
        "8": [".XXX.", "X...X", "X...X", ".XXX.", "X...X", "X...X", ".XXX."],
        "9": [".XXX.", "X...X", "X...X", ".XXXX", "....X", "...X.", ".XX.."],
        "A": ["..X..", ".X.X.", "X...X", "X...X", "XXXXX", "X...X", "X...X"],
        "B": ["XXXX.", "X...X", "X...X", "XXXX.", "X...X", "X...X", "XXXX."],
        "C": [".XXX.", "X...X", "X....", "X....", "X....", "X...X", ".XXX."],
        "D": ["XXX..", "X..X.", "X...X", "X...X", "X...X", "X..X.", "XXX.."],
        "E": ["XXXXX", "X....", "X....", "XXXX.", "X....", "X....", "XXXXX"],
        "F": ["XXXXX", "X....", "X....", "XXXX.", "X....", "X....", "X...."],
        "G": [".XXX.", "X...X", "X....", "X.XXX", "X...X", "X...X", ".XXX."],
        "H": ["X...X", "X...X", "X...X", "XXXXX", "X...X", "X...X", "X...X"],
        "I": [".XXX.", "..X..", "..X..", "..X..", "..X..", "..X..", ".XXX."],
        "J": ["..XXX", "...X.", "...X.", "...X.", "...X.", "X..X.", ".XX.."],
        "K": ["X...X", "X..X.", "X.X..", "XX...", "X.X..", "X..X.", "X...X"],
        "L": ["X....", "X....", "X....", "X....", "X....", "X....", "XXXXX"],
        "M": ["X...X", "XX.XX", "X.X.X", "X.X.X", "X...X", "X...X", "X...X"],
        "N": ["X...X", "XX..X", "X.X.X", "X..XX", "X...X", "X...X", "X...X"],
        "O": [".XXX.", "X...X", "X...X", "X...X", "X...X", "X...X", ".XXX."],
        "P": ["XXXX.", "X...X", "X...X", "XXXX.", "X....", "X....", "X...."],
        "Q": [".XXX.", "X...X", "X...X", "X...X", "X.X.X", "X..X.", ".XX.X"],
        "R": ["XXXX.", "X...X", "X...X", "XXXX.", "X.X..", "X..X.", "X...X"],
        "S": [".XXXX", "X....", "X....", ".XXX.", "....X", "....X", "XXXX."],
        "T": ["XXXXX", "..X..", "..X..", "..X..", "..X..", "..X..", "..X.."],
        "U": ["X...X", "X...X", "X...X", "X...X", "X...X", "X...X", ".XXX."],
        "V": ["X...X", "X...X", "X...X", "X...X", "X...X", ".X.X.", "..X.."],
        "W": ["X...X", "X...X", "X...X", "X.X.X", "X.X.X", "XX.XX", "X...X"],
        "X": ["X...X", "X...X", ".X.X.", "..X..", ".X.X.", "X...X", "X...X"],
        "Y": ["X...X", "X...X", ".X.X.", "..X..", "..X..", "..X..", "..X.."],
        "Z": ["XXXXX", "....X", "...X.", "..X..", ".X...", "X....", "XXXXX"],
        ":": [".....", "..X..", "..X..", ".....", "..X..", "..X..", "....."],
        ".": [".....", ".....", ".....", ".....", ".....", ".XX..", ".XX.."],
        "+": [".....", "..X..", "..X..", "XXXXX", "..X..", "..X..", "....."],
        "-": [".....", ".....", ".....", "XXXXX", ".....", ".....", "....."],
        "/": ["....X", "....X", "...X.", "..X..", ".X...", "X....", "X...."],
        "°": [".XX..", "X..X.", ".XX..", ".....", ".....", ".....", "....."],
        "±": [".....", "..X..", "XXXXX", "..X..", ".....", "XXXXX", "....."]
    ]

    static func glyph(for character: Character) -> [String]? {
        glyphs[character] ?? glyphs[Character(character.uppercased())]
    }
}

/// Text rendered as a dot-matrix panel.
///
/// `pitch` is the cell size in points: a glyph is five cells wide plus one
/// blank column, seven cells tall. Pick pitch ≈ desired point size ÷ 6.
struct DotMatrixText: View {
    let text: String
    var color: Color = DotMatrixText.amber
    var pitch: CGFloat = 2

    /// The classic warm amber of flip-disc panels.
    static let amber = Color(red: 1.00, green: 0.62, blue: 0.16)

    /// Ideal size of the panel, for callers that frame it.
    var size: CGSize {
        CGSize(width: CGFloat(text.count * 6) * pitch, height: 7 * pitch)
    }

    var body: some View {
        Canvas { context, _ in
            let characters = Array(text.uppercased())
            let dot = pitch * 0.72

            for (charIndex, character) in characters.enumerated() {
                guard let glyph = DotFont.glyph(for: character) else { continue }
                let originX = CGFloat(charIndex * 6) * pitch

                // The unlit grid first, five by seven: the panel, not the
                // glyphs, is what sells the effect.
                for row in 0..<7 {
                    for column in 0..<5 {
                        let center = CGPoint(
                            x: originX + (CGFloat(column) + 0.5) * pitch,
                            y: (CGFloat(row) + 0.5) * pitch
                        )
                        let unlit = CGRect(x: center.x - dot / 2, y: center.y - dot / 2, width: dot, height: dot)
                        context.fill(Path(ellipseIn: unlit), with: .color(.white.opacity(0.055)))
                    }
                }

                for (rowIndex, row) in glyph.enumerated() {
                    for (columnIndex, cell) in row.enumerated() where cell == "X" {
                        let center = CGPoint(
                            x: originX + (CGFloat(columnIndex) + 0.5) * pitch,
                            y: (CGFloat(rowIndex) + 0.5) * pitch
                        )

                        // A halo pass then the core: two fills, no shadows,
                        // so a full results list stays one cheap draw pass.
                        let halo = CGRect(x: center.x - dot, y: center.y - dot, width: dot * 2, height: dot * 2)
                        context.fill(Path(ellipseIn: halo), with: .color(color.opacity(0.16)))
                        let core = CGRect(x: center.x - dot / 2, y: center.y - dot / 2, width: dot, height: dot)
                        context.fill(Path(ellipseIn: core), with: .color(color))
                    }
                }
            }
        }
        .frame(width: size.width, height: size.height)
        .accessibilityLabel(text)
    }
}
