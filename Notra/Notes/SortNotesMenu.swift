import SwiftUI

struct SortNotesMenu: View {
    let preference: NoteSortPreference
    let setField: (NoteSortField) -> Void
    let setDirection: (NoteSortDirection) -> Void

    var body: some View {
        Menu {
            ForEach(NoteSortField.allCases, id: \.self) { field in
                sortFieldButton(field)
            }

            Divider()

            ForEach(NoteSortDirection.allCases, id: \.self) { direction in
                sortDirectionButton(direction)
            }
        } label: {
            Image(systemName: "arrow.up.arrow.down")
        }
        .buttonStyle(.plain)
        .help("Sort Notes")
        .accessibilityLabel("Sort Notes")
    }

    private func sortFieldButton(_ field: NoteSortField) -> some View {
        Button {
            setField(field)
        } label: {
            if preference.field == field {
                Label(field.menuTitle, systemImage: "checkmark")
            } else {
                Text(field.menuTitle)
            }
        }
    }

    private func sortDirectionButton(_ direction: NoteSortDirection) -> some View {
        Button {
            setDirection(direction)
        } label: {
            if preference.direction == direction {
                Label(direction.menuTitle, systemImage: "checkmark")
            } else {
                Text(direction.menuTitle)
            }
        }
    }
}
