#if os(iOS)
import SwiftUI

struct ShareCaptureLifecycleModifier: ViewModifier {
    @Environment(\.scenePhase) private var scenePhase
    @Binding var selectedTagIDs: Set<String>
    let store: NotesStore
    let availableTagIDs: Set<String>
    let onStorageChanged: () -> Void
    func body(content: Content) -> some View {
        content
            .onChange(of: availableTagIDs) { _, tagIDs in
                guard !store.isLoading else { return }
                selectedTagIDs.formIntersection(tagIDs)
            }
            .onChange(of: scenePhase) {
                guard scenePhase == .active else { return }
                Task { await store.importSharedCaptures() }
            }
            .onChange(of: store.isLoading) { wasLoading, isLoading in
                guard wasLoading, !isLoading else { return }
                Task { await store.importSharedCaptures() }
            }
            .onChange(of: store.isChangingStorage) { wasChanging, isChanging in
                guard wasChanging, !isChanging else { return }
                Task { await store.importSharedCaptures() }
            }
            .onChange(of: store.storageLocation) {
                onStorageChanged()
            }
    }
}
#endif
