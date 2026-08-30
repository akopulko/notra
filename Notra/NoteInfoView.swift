import SwiftUI

/// Displays the derived note statistics and storage details in the attachment inspector.
struct NoteInfoView: View {
    let info: NoteInfo

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            infoGroup(title: "Statistics") {
                infoRow("Words") {
                    numberValue(info.statistics.wordCount)
                }
                infoRow("Characters") {
                    numberValue(info.statistics.characterCount)
                }
                infoRow("Lines") {
                    numberValue(info.statistics.lineCount)
                }
                infoRow("Reading Time") {
                    valueText("\(info.statistics.readingTimeMinutes.formatted(.number)) min")
                }
            }

            infoGroup(title: "Dates") {
                infoRow("Created") {
                    dateValue(info.createdAt)
                }
                infoRow("Modified") {
                    dateValue(info.modifiedAt)
                }
            }

            infoGroup(title: "File") {
                infoRow("Where") {
                    valueText(info.location)
                }
                infoRow("File") {
                    valueText(info.filename)
                }
                infoRow("Size") {
                    valueText(ByteCountFormatter.string(
                        fromByteCount: info.byteCount,
                        countStyle: .file
                    ))
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func infoGroup(
        title: LocalizedStringKey,
        @ViewBuilder content: () -> some View
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            content()
        }
    }

    private func infoRow(
        _ title: LocalizedStringKey,
        @ViewBuilder value: () -> some View
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title)
                .font(.body)
            Spacer(minLength: 12)
            value()
        }
    }

    private func numberValue(_ value: Int) -> some View {
        valueText(value.formatted(.number))
            .monospacedDigit()
    }

    private func dateValue(_ value: Date) -> some View {
        Text(value, format: .dateTime.day().month(.abbreviated).year().hour().minute())
            .font(.body)
            .foregroundStyle(.secondary)
            .lineLimit(1)
    }

    private func valueText(_ value: String) -> some View {
        Text(value)
            .font(.body)
            .foregroundStyle(.secondary)
            .lineLimit(1)
    }
}
