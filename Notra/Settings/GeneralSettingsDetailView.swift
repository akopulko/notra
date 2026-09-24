import SwiftUI

#if os(macOS)
import AppKit
#endif

/// Contains general storage, attachment, and behavior preferences.
struct GeneralSettingsDetailView: View {
    @Bindable var store: NotesStore
    @Binding var startNewNoteWith: String
    @Binding var maximumAttachmentSizeMB: Int
    @Binding var showsNotePreview: Bool
    let showsHeader: Bool

    @State private var libraryByteCount: Int64?
    @State private var isLoadingLibraryByteCount = true

    var body: some View {
        Form {
            if showsHeader {
                SettingsHeaderView(category: .general)
                    .settingsHeaderFormRow()
            }

            Section {
                Picker("Notes Location", selection: storageLocationBinding) {
                    ForEach(NoteStorageLocation.allCases) { location in
                        Text(location.title)
                            .tag(location)
                            .disabled(location == .iCloud && !store.isICloudStorageAvailable)
                    }
                }
                .disabled(store.isChangingStorage)
                #if os(macOS)
                .pickerStyle(.menu)
                #else
                .pickerStyle(.navigationLink)
                #endif

                LabeledContent {
                    Text(store.notes.count, format: .number)
                } label: {
                    Text("Notes", comment: "Settings row showing the number of notes in the active library.")
                }

                LabeledContent {
                    if isLoadingLibraryByteCount {
                        ProgressView()
                    } else if let libraryByteCount {
                        Text(ByteCountFormatter.string(fromByteCount: libraryByteCount, countStyle: .file))
                    } else {
                        Text("Unavailable", comment: "Settings value shown when the library size cannot be read.")
                    }
                } label: {
                    Text("Library Size", comment: "Settings row showing the total size of the active notes library.")
                }

                #if os(macOS)
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([store.libraryURL])
                } label: {
                    Label {
                        Text("Open Library Location", comment: "Button that reveals the active notes library in Finder.")
                    } icon: {
                        Image(systemName: "folder")
                    }
                }
                .disabled(store.isChangingStorage)
                #else
                LabeledContent {
                    Text(store.storageDescription)
                } label: {
                    Text("Library Location", comment: "Settings row showing where the active notes library appears in Files.")
                }
                #endif
            } header: {
                Text("Notes")
            } footer: {
                VStack(alignment: .leading) {
                    Text("Choose where notes are stored. Changing location does not move existing notes.")
                    #if os(iOS)
                    Text(
                        "The library is available in the Files app.",
                        comment: "Explains where iOS users can find the active notes library."
                    )
                    #endif
                }
            }

            Section {
                Picker("Start New Note With", selection: $startNewNoteWith) {
                    ForEach(NoteStartContent.allCases) { option in
                        Text(option.title)
                            .tag(option.rawValue)
                    }
                }
                #if os(macOS)
                .pickerStyle(.menu)
                #else
                .pickerStyle(.navigationLink)
                #endif
            } footer: {
                Text("Choose whether new notes begin with a title heading or an empty document.")
            }

            Section {
                Toggle("Show Note Preview", isOn: $showsNotePreview)
            } footer: {
                Text("Show each note’s first line or content preview in the notes list.")
            }

            Section {
                Stepper(
                    value: maximumAttachmentSizeBinding,
                    in: AttachmentSettings.supportedMaximumSizeRange,
                    step: AttachmentSettings.maximumSizeStep
                ) {
                    LabeledContent("Maximum Attachment Size") {
                        Text("\(maximumAttachmentSizeMB.formatted(.number)) MB")
                    }
                }
            } footer: {
                Text("Files larger than this limit cannot be added to a note.")
            }
        }
        .settingsDetailFormStyle()
        .settingsDetailNavigationTitle(SettingsCategory.general.title)
        .task(id: store.libraryURL) {
            libraryByteCount = nil
            isLoadingLibraryByteCount = true

            do {
                let byteCount = try await store.loadLibraryByteCount()
                guard !Task.isCancelled else {
                    return
                }
                libraryByteCount = byteCount
                isLoadingLibraryByteCount = false
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else {
                    return
                }
                isLoadingLibraryByteCount = false
            }
        }
    }

    private var maximumAttachmentSizeBinding: Binding<Int> {
        Binding {
            AttachmentSettings.clampedMaximumSizeMB(maximumAttachmentSizeMB)
        } set: { newValue in
            maximumAttachmentSizeMB = AttachmentSettings.clampedMaximumSizeMB(newValue)
        }
    }

    private var storageLocationBinding: Binding<NoteStorageLocation> {
        Binding {
            store.storageLocation
        } set: { location in
            Task {
                await store.changeStorageLocation(to: location)
            }
        }
    }
}
