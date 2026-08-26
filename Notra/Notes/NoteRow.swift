import SwiftUI

struct NoteRow: View {
    let note: NoteSummary
    let sortField: NoteSortField

    private let previewLineLimit = 3

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            previewText
            Text(
                sortField == .dateCreated ? note.createdAt : note.modifiedAt,
                format: .dateTime.month().day().hour().minute()
            )
            .font(.callout)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var previewText: some View {
        if note.previewFirstLineIsHeading {
            let lines = note.previewText.components(separatedBy: .newlines)
            let remainingPreviewText = lines.dropFirst().joined(separator: "\n")
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: lines.first ?? NoteSummary.emptyPreviewText)
                    .font(.title3)
                    .fontWeight(.bold)
                    .lineLimit(1)
                    .truncationMode(.tail)
                if !remainingPreviewText.isEmpty {
                    Text(verbatim: remainingPreviewText)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .lineLimit(max(previewLineLimit - 1, 1))
                        .truncationMode(.tail)
                }
            }
        } else {
            Text(verbatim: note.previewText)
                .font(.body)
                .lineLimit(previewLineLimit)
                .truncationMode(.tail)
        }
    }
}
