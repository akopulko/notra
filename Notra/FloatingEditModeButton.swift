import SwiftUI

struct FloatingEditModeButton: View {
    let isEditing: Bool
    let action: () -> Void

    private var title: String {
        isEditing ? "Done" : "Edit"
    }

    private var systemImage: String {
        isEditing ? "checkmark" : "pencil"
    }

    var body: some View {
        GlassEffectContainer {
            Button(action: action) {
                Image(systemName: systemImage)
                    .font(.system(size: 22, weight: .semibold))
                    .frame(width: 56, height: 56)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.primary)
            .contentShape(.circle)
            .glassEffect(.regular.interactive(), in: .circle)
            .help(title)
            .accessibilityLabel(title)
        }
    }
}
