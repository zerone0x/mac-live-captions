import Foundation

/// Greedy, left-to-right word wrapping to a character budget.
///
/// Greedy wrapping is prefix-stable: where a line breaks depends only on the
/// words before the break. Appending words (a new volatile tail, or newly
/// finalized text) never moves words that are already laid out. The caption
/// overlay relies on this so that finalized text never jumps.
public enum CaptionLineBreaker {
    /// Splits `text` into words on whitespace. Words longer than
    /// `maxLineLength` are cut into pieces of at most `maxLineLength`
    /// characters, so every piece fits on a line.
    public static func pieces(of text: String, maxLineLength: Int) -> [String] {
        precondition(maxLineLength > 0, "maxLineLength must be positive")
        var result: [String] = []
        for word in text.split(whereSeparator: \.isWhitespace) {
            var rest = Substring(word)
            while rest.count > maxLineLength {
                let cut = rest.index(rest.startIndex, offsetBy: maxLineLength)
                result.append(String(rest[..<cut]))
                rest = rest[cut...]
            }
            if !rest.isEmpty {
                result.append(String(rest))
            }
        }
        return result
    }

    /// Packs `pieces` into lines of at most `maxLineLength` characters
    /// (pieces joined by one space) and returns the index range of each line.
    ///
    /// A piece longer than the budget gets a line of its own; use
    /// `pieces(of:maxLineLength:)` to avoid that.
    public static func lines(of pieces: [String], maxLineLength: Int) -> [Range<Int>] {
        precondition(maxLineLength > 0, "maxLineLength must be positive")
        var lines: [Range<Int>] = []
        var start = 0
        var length = 0
        for (index, piece) in pieces.enumerated() {
            if index == start {
                length = piece.count
            } else if length + 1 + piece.count <= maxLineLength {
                length += 1 + piece.count
            } else {
                lines.append(start..<index)
                start = index
                length = piece.count
            }
        }
        if start < pieces.count {
            lines.append(start..<pieces.count)
        }
        return lines
    }

    /// Wraps `text` and returns the lines as strings.
    public static func wrap(_ text: String, maxLineLength: Int) -> [String] {
        let pieces = pieces(of: text, maxLineLength: maxLineLength)
        return lines(of: pieces, maxLineLength: maxLineLength).map {
            pieces[$0].joined(separator: " ")
        }
    }
}
