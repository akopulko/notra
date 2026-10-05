import Foundation

/// A chronological sidebar bucket, identified by calendar components rather than its localized heading.
struct NoteDateSection: Identifiable, Sendable {
    let id: DateComponents
    /// The first note's grouping date, used only to format the heading.
    let date: Date
    var notes: [NoteSummary]

    // Explicit isolation is required with the app's MainActor default.
    // swiftformat:disable redundantMemberwiseInit
    // swiftlint:disable:next unneeded_synthesized_initializer
    nonisolated init(id: DateComponents, date: Date, notes: [NoteSummary]) {
        self.id = id
        self.date = date
        self.notes = notes
    }
    // swiftformat:enable redundantMemberwiseInit
}

/// Projects already sorted, unpinned notes into months of the current year and years otherwise.
enum NoteDateGrouping {
    private nonisolated static let monthComponents: Set<Calendar.Component> = [.era, .year, .month, .isLeapMonth]
    private nonisolated static let yearComponents: Set<Calendar.Component> = [.era, .year]

    nonisolated static func sections(
        in notes: [NoteSummary],
        field: NoteSortField,
        now: Date,
        calendar: Calendar
    ) -> [NoteDateSection] {
        var sections: [NoteDateSection] = []

        for note in notes {
            let date = field == .dateEdited ? note.modifiedAt : note.createdAt
            let components = calendar.isDate(date, equalTo: now, toGranularity: .year)
                ? monthComponents
                : yearComponents
            let id = calendar.dateComponents(components, from: date)

            if sections.last?.id == id {
                sections[sections.count - 1].notes.append(note)
            } else {
                sections.append(NoteDateSection(id: id, date: date, notes: [note]))
            }
        }

        return sections
    }
}
