import Foundation
@testable import Notra
import Testing

/// Verifies chronological membership without relying on localized sidebar headings.
struct NoteDateGroupingTests {
    @Test(arguments: [NoteSortDirection.latestFirst, .oldestFirst])
    func `groups current year months and other years`(direction: NoteSortDirection) throws {
        let calendar = try makeCalendar()
        let now = try date("2026-07-15T12:00:00Z")
        let julyLate = try note("july-late", at: "2026-07-14T12:00:00Z")
        let julyEarly = try note("july-early", at: "2026-07-01T12:00:00Z")
        let june = try note("june", at: "2026-06-20T12:00:00Z")
        let january = try note("january", at: "2026-01-10T12:00:00Z")
        let december2025 = try note("december-2025", at: "2025-12-20T12:00:00Z")
        let march2025 = try note("march-2025", at: "2025-03-10T12:00:00Z")
        let november2024 = try note("november-2024", at: "2024-11-20T12:00:00Z")
        let february2024 = try note("february-2024", at: "2024-02-10T12:00:00Z")
        let notes = [march2025, julyEarly, february2024, june, december2025, january, julyLate, november2024]
        let preference = NoteSortPreference(field: .dateEdited, direction: direction)
        let sections = NoteDateGrouping.sections(in: preference.sorted(notes), field: preference.field, now: now, calendar: calendar)
        let latestIDs = [sectionID(2026, month: 7), sectionID(2026, month: 6), sectionID(2026, month: 1), sectionID(2025), sectionID(2024)]
        let latestRows = [
            [julyLate.id, julyEarly.id], [june.id], [january.id],
            [december2025.id, march2025.id], [november2024.id, february2024.id]
        ]

        #expect(sections.map(\.id) == (direction == .latestFirst ? latestIDs : Array(latestIDs.reversed())))
        #expect(sections.map { $0.notes.map(\.id) } == (
            direction == .latestFirst ? latestRows : latestRows.reversed().map { Array($0.reversed()) }
        ))
    }

    @Test
    func `selected field moves an edited old note to its modification month`() throws {
        let calendar = try makeCalendar()
        let now = try date("2026-07-15T12:00:00Z")
        let edited = try NoteSummary(
            url: URL(fileURLWithPath: "/tmp/date-grouping-edited.textbundle"),
            previewText: "Edited",
            createdAt: date("2024-02-10T12:00:00Z"),
            modifiedAt: date("2026-07-14T12:00:00Z")
        )
        let june = try note("field-june", at: "2026-06-20T12:00:00Z")
        let notes = [june, edited]
        let editedPreference = NoteSortPreference(field: .dateEdited, direction: .latestFirst)
        let createdPreference = NoteSortPreference(field: .dateCreated, direction: .latestFirst)
        let editedSections = NoteDateGrouping.sections(
            in: editedPreference.sorted(notes), field: editedPreference.field, now: now, calendar: calendar
        )
        let createdSections = NoteDateGrouping.sections(
            in: createdPreference.sorted(notes), field: createdPreference.field, now: now, calendar: calendar
        )

        #expect(editedSections.map(\.id) == [sectionID(2026, month: 7), sectionID(2026, month: 6)])
        #expect(editedSections.map { $0.notes.map(\.id) } == [[edited.id], [june.id]])
        #expect(createdSections.map(\.id) == [sectionID(2026, month: 6), sectionID(2024)])
        #expect(createdSections.map { $0.notes.map(\.id) } == [[june.id], [edited.id]])
    }

    @Test(arguments: [NoteSortDirection.latestFirst, .oldestFirst])
    func `preserves sort tie break order within month`(direction: NoteSortDirection) throws {
        let calendar = try makeCalendar()
        let now = try date("2026-07-15T12:00:00Z")
        let alphaSecond = try note("tie-b", title: "Alpha", at: "2026-07-10T12:00:00Z")
        let beta = try note("tie-c", title: "Beta", at: "2026-07-10T12:00:00Z")
        let alphaFirst = try note("tie-a", title: "Alpha", at: "2026-07-10T12:00:00Z")
        let preference = NoteSortPreference(field: .dateEdited, direction: direction)
        let sections = NoteDateGrouping.sections(
            in: preference.sorted([beta, alphaSecond, alphaFirst]), field: preference.field, now: now, calendar: calendar
        )

        #expect(sections.map(\.id) == [sectionID(2026, month: 7)])
        #expect(sections.map { $0.notes.map(\.id) } == [[alphaFirst.id, alphaSecond.id, beta.id]])
    }

    @Test
    func `time zone determines year and month at new year`() throws {
        let utc = try makeCalendar()
        let east = try makeCalendar(secondsFromGMT: 2 * 60 * 60)
        let now = try date("2026-01-01T00:30:00Z")
        let boundary = try note("time-zone-boundary", at: "2025-12-31T23:30:00Z")
        let preference = NoteSortPreference(field: .dateEdited, direction: .latestFirst)
        let notes = preference.sorted([boundary])
        let utcSections = NoteDateGrouping.sections(in: notes, field: preference.field, now: now, calendar: utc)
        let eastSections = NoteDateGrouping.sections(in: notes, field: preference.field, now: now, calendar: east)

        #expect(utcSections.map(\.id) == [sectionID(2025)])
        #expect(eastSections.map(\.id) == [sectionID(2026, month: 1)])
        #expect(utcSections.map { $0.notes.map(\.id) } == [[boundary.id]])
        #expect(eastSections.map { $0.notes.map(\.id) } == [[boundary.id]])
    }

    @Test
    func `advancing reference year merges previous months`() throws {
        let calendar = try makeCalendar()
        let january = try note("rollover-january", at: "2027-01-01T00:00:00Z")
        let december = try note("rollover-december", at: "2026-12-15T12:00:00Z")
        let july = try note("rollover-july", at: "2026-07-15T12:00:00Z")
        let preference = NoteSortPreference(field: .dateEdited, direction: .latestFirst)
        let notes = preference.sorted([july, january, december])
        let before = try NoteDateGrouping.sections(
            in: notes, field: preference.field, now: date("2026-12-31T23:59:59Z"), calendar: calendar
        )
        let after = try NoteDateGrouping.sections(
            in: notes, field: preference.field, now: date("2027-01-01T00:00:00Z"), calendar: calendar
        )

        #expect(before.map(\.id) == [sectionID(2027), sectionID(2026, month: 12), sectionID(2026, month: 7)])
        #expect(before.map { $0.notes.map(\.id) } == [[january.id], [december.id], [july.id]])
        #expect(after.map(\.id) == [sectionID(2027, month: 1), sectionID(2026)])
        #expect(after.map { $0.notes.map(\.id) } == [[january.id], [december.id, july.id]])
    }

    @Test
    func `empty input emits no sections`() throws {
        let calendar = try makeCalendar()
        let sections = try NoteDateGrouping.sections(
            in: [], field: .dateEdited, now: date("2026-07-15T12:00:00Z"), calendar: calendar
        )

        #expect(sections.isEmpty)
    }

    @Test
    func `future non current year combines different months`() throws {
        let calendar = try makeCalendar()
        let december = try note("future-december", at: "2028-12-15T12:00:00Z")
        let january = try note("future-january", at: "2028-01-15T12:00:00Z")
        let preference = NoteSortPreference(field: .dateEdited, direction: .latestFirst)
        let sections = try NoteDateGrouping.sections(
            in: preference.sorted([january, december]), field: preference.field,
            now: date("2026-07-15T12:00:00Z"), calendar: calendar
        )

        #expect(sections.map(\.id) == [sectionID(2028)])
        #expect(sections.map { $0.notes.map(\.id) } == [[december.id, january.id]])
    }

    private func makeCalendar(secondsFromGMT: Int = 0) throws -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: secondsFromGMT))
        return calendar
    }

    private func date(_ value: String) throws -> Date {
        try #require(ISO8601DateFormatter().date(from: value))
    }

    private func note(_ name: String, title: String? = nil, at timestamp: String) throws -> NoteSummary {
        let date = try date(timestamp)
        return NoteSummary(
            url: URL(fileURLWithPath: "/tmp/date-grouping-\(name).textbundle"),
            previewText: title ?? name,
            createdAt: date,
            modifiedAt: date
        )
    }

    private func sectionID(_ year: Int, month: Int? = nil) -> DateComponents {
        var id = DateComponents(era: 1, year: year, month: month)
        if month != nil {
            id.isLeapMonth = false
        }
        return id
    }
}
