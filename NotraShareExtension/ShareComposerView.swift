import SwiftUI

struct ShareComposerView: View {
    @State private var model: ShareComposerModel

    init(model: ShareComposerModel) {
        _model = State(initialValue: model)
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text(.shareCaptureLibraryNotice)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                TextEditor(text: $model.body)
                    .accessibilityLabel("Note content")
                    .disabled(!model.isBodyEditable)
                if !model.assets.isEmpty {
                    ScrollView(.horizontal) {
                        HStack {
                            ForEach(model.thumbnails.indices, id: \.self) { index in
                                Image(decorative: model.thumbnails[index], scale: 1)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(maxWidth: 100, maxHeight: 100)
                                    .accessibilityHidden(true)
                            }
                        }
                    }
                }
                if case let .error(message) = model.state {
                    Text(message).foregroundStyle(.red)
                }
                Spacer()
            }
            .padding()
            .navigationTitle("New Note")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: model.cancel).disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: model.save).disabled(!model.canSave)
                }
            }
            .overlay {
                if isLoading {
                    ProgressView()
                }
            }
        }
    }

    private var isLoading: Bool {
        if case .loading = model.state {
            return true
        }
        return false
    }

    private var isSaving: Bool {
        if case .saving = model.state {
            return true
        }
        return false
    }
}
