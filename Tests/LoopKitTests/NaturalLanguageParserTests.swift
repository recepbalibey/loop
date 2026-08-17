import Testing
@testable import LoopKit
import Foundation

struct NaturalLanguageParserTests {

    @Test func plainTitleWithNoDateOrTag() {
        let result = NaturalLanguageParser.parse("Call mom")
        #expect(result.cleanTitle == "Call mom")
        #expect(result.date == nil)
        #expect(result.tag == nil)
    }

    @Test func tomorrowKeyword() throws {
        let result = NaturalLanguageParser.parse("Buy milk tomorrow")
        #expect(result.cleanTitle == "Buy milk")
        let date = try #require(result.date)
        #expect(Calendar.current.isDateInTomorrow(date))
    }

    @Test func trailingAtLocationBecomesTag() throws {
        let result = NaturalLanguageParser.parse("Record a video for X before end of day at home")
        #expect(result.cleanTitle == "Record a video for X")
        #expect(result.tag == "home")
        let date = try #require(result.date)
        #expect(Calendar.current.isDateInToday(date))
    }

    @Test func beforeEndOfDayResolvesToToday() throws {
        let result = NaturalLanguageParser.parse("Finish the report before end of day")
        let date = try #require(result.date)
        #expect(Calendar.current.isDateInToday(date))
        #expect(result.cleanTitle == "Finish the report")
    }

    @Test func eodAbbreviationResolvesToToday() throws {
        let result = NaturalLanguageParser.parse("Ship the build eod")
        let date = try #require(result.date)
        #expect(Calendar.current.isDateInToday(date))
    }

    @Test func tonightResolvesToEveningToday() throws {
        let result = NaturalLanguageParser.parse("Watch the game tonight")
        let date = try #require(result.date)
        #expect(Calendar.current.isDateInToday(date))
        #expect(Calendar.current.component(.hour, from: date) == 20)
    }

    @Test func danglingPrepositionIsStrippedAfterDateRemoval() {
        // "Friday at 10am" is consumed by the date detector, "at office" by the tag
        // pattern — that leaves "Submit invoices on" and the trailing "on" should
        // also be cleaned up.
        let result = NaturalLanguageParser.parse("Submit invoices on Friday at 10am at office")
        #expect(result.cleanTitle == "Submit invoices")
        #expect(result.tag == "office")
        #expect(result.date != nil)
    }

    @Test func whenDateAndTagConsumeEverythingTitleFallsBackToRawInput() {
        // Degenerate case: nothing is left over to use as a title, so parsing
        // should never hand back an empty task title.
        let result = NaturalLanguageParser.parse("tomorrow at home")
        #expect(!result.cleanTitle.isEmpty)
    }

    @Test func dateChipLabelToday() {
        #expect(NaturalLanguageParser.dateChipLabel(for: .now) == "Today")
    }

    @Test func dateChipLabelTomorrow() {
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: .now)!
        #expect(NaturalLanguageParser.dateChipLabel(for: tomorrow) == "Tomorrow")
    }

    @Test func dueLabelOmitsTimeAtMidnight() {
        let midnight = Calendar.current.startOfDay(for: .now)
        #expect(NaturalLanguageParser.dueLabel(for: midnight) == "Today")
    }

    @Test func dueLabelIncludesTimeWhenPresent() {
        let withTime = Calendar.current.date(bySettingHour: 14, minute: 30, second: 0, of: .now)!
        #expect(NaturalLanguageParser.dueLabel(for: withTime) == "Today 14:30")
    }

    // MARK: - Robustness edge cases

    @Test func whitespaceOnlyInputDoesNotCrash() {
        // There's genuinely nothing to salvage as a title here — callers (the add bar)
        // already guard against this before ever calling parse(), but parse() itself
        // must not crash or hang on it.
        let result = NaturalLanguageParser.parse("   ")
        #expect(result.cleanTitle.isEmpty)
        #expect(result.date == nil)
        #expect(result.tag == nil)
    }

    @Test func singleCharacterInput() {
        let result = NaturalLanguageParser.parse("x")
        #expect(result.cleanTitle == "x")
    }

    @Test func unicodeAndEmojiTitleIsPreservedUnmodified() {
        let result = NaturalLanguageParser.parse("Buy 🥛 milk at café")
        #expect(result.cleanTitle == "Buy 🥛 milk")
        #expect(result.tag == "café")
    }

    @Test func veryLongTitleIsNotTruncated() {
        let longTitle = String(repeating: "word ", count: 200).trimmingCharacters(in: .whitespaces)
        let result = NaturalLanguageParser.parse(longTitle)
        #expect(result.cleanTitle == longTitle)
    }
}
