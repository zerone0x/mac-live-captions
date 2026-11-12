import Testing
@testable import LiveCaptionsCore

@Suite("Caption line breaker")
struct CaptionLineBreakerTests {
    @Test("wraps greedily at word boundaries")
    func greedyWrap() {
        #expect(CaptionLineBreaker.wrap("the quick brown fox jumps", maxLineLength: 10)
            == ["the quick", "brown fox", "jumps"])
    }

    @Test("a line may be exactly the budget, never longer")
    func exactFit() {
        let text = String(repeating: "a", count: 20) + " " + String(repeating: "b", count: 21) + " c"
        let lines = CaptionLineBreaker.wrap(text, maxLineLength: 42)
        #expect(lines.map(\.count) == [42, 1])
    }

    @Test("collapses runs of whitespace and newlines")
    func normalisesWhitespace() {
        #expect(CaptionLineBreaker.wrap("  hello \n\t world  ", maxLineLength: 42) == ["hello world"])
        #expect(CaptionLineBreaker.wrap(" \n ", maxLineLength: 42).isEmpty)
    }

    @Test("cuts words longer than a line")
    func longWords() {
        let pieces = CaptionLineBreaker.pieces(of: "ab abcdefghij", maxLineLength: 4)
        #expect(pieces == ["ab", "abcd", "efgh", "ij"])
        #expect(CaptionLineBreaker.wrap("ab abcdefghij", maxLineLength: 4) == ["ab", "abcd", "efgh", "ij"])
    }

    @Test("counts characters, not bytes")
    func graphemes() {
        // "café" is 4 characters but 5 UTF-8 bytes.
        #expect(CaptionLineBreaker.wrap("café café", maxLineLength: 9) == ["café café"])
    }

    @Test("appending words never moves earlier line breaks (prefix stability)")
    func prefixStable() throws {
        let words = (0..<120).map { index in String(repeating: "w", count: 1 + (index * 7) % 11) }
        let full = CaptionLineBreaker.lines(of: words, maxLineLength: 42)
        for count in 1...words.count {
            let prefix = CaptionLineBreaker.lines(of: Array(words.prefix(count)), maxLineLength: 42)
            // All lines but the last are identical; the last is a prefix of its counterpart.
            #expect(Array(prefix.dropLast()) == Array(full.prefix(prefix.count - 1)))
            let last = try #require(prefix.last)
            #expect(full[prefix.count - 1].lowerBound == last.lowerBound)
        }
    }
}
