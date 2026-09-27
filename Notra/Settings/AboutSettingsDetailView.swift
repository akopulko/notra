import Foundation
import SwiftUI

#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif

/// Displays app identity, version, and open-source attribution information.
struct AboutSettingsDetailView: View {
    let info: AppAboutInfo
    let showsHeader: Bool

    var body: some View {
        Form {
            AboutHeroView(info: info)
                .settingsHeaderFormRow()

            Section {
                LabeledContent("Version", value: info.versionDisplay)
                LabeledContent("Format", value: "Markdown + TextBundle")
                LabeledContent("Platforms", value: "Mac, iPhone and iPad")
            } header: {
                Text("About Notra")
            }

            Section {
                Link(destination: info.websiteURL) {
                    Label("Website", systemImage: "safari")
                }

                Link(destination: info.sourceCodeURL) {
                    Label("Source Code", systemImage: "chevron.left.forwardslash.chevron.right")
                }
            } header: {
                Text("Project")
            }

            Section {
                AboutPrincipleRow(
                    title: "No account required",
                    subtitle: "Start writing without creating a profile.",
                    systemImage: "person.crop.circle.badge.checkmark"
                )
                AboutPrincipleRow(
                    title: "Portable notes",
                    subtitle: "Markdown and TextBundle files stay useful outside Notra.",
                    systemImage: "doc.text"
                )
                AboutPrincipleRow(
                    title: "Open source",
                    subtitle: "The project is available on GitHub.",
                    systemImage: "curlybraces"
                )
            } header: {
                Text("Principles")
            }
        }
        .settingsDetailFormStyle()
        .settingsDetailNavigationTitle(SettingsCategory.about.title)
    }
}

private struct AboutHeroView: View {
    let info: AppAboutInfo

    var body: some View {
        VStack(spacing: 14) {
            AboutAppIconView()

            Text(info.displayName)
                .font(.title2)
                .fontWeight(.semibold)

            Text("Notes that stay yours.")
                .font(.headline)

            Text("Private Markdown notes for Mac, iPhone and iPad.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24)
        .padding(.vertical, 30)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

private struct AboutAppIconView: View {
    var body: some View {
        #if os(iOS)
        if let image = primaryIcon {
            iconView(Image(uiImage: image))
        } else {
            fallbackIconView
        }
        #else
        if let image = NSApplication.shared.applicationIconImage, image.size != .zero {
            iconView(Image(nsImage: image))
        } else {
            fallbackIconView
        }
        #endif
    }

    #if os(iOS)
    private var primaryIcon: UIImage? {
        guard
            let icons = Bundle.main.object(forInfoDictionaryKey: "CFBundleIcons") as? [String: Any],
            let primaryIcon = icons["CFBundlePrimaryIcon"] as? [String: Any],
            let iconFiles = primaryIcon["CFBundleIconFiles"] as? [String],
            let iconName = iconFiles.last
        else {
            return nil
        }

        return UIImage(named: iconName)
    }
    #endif

    private func iconView(_ image: Image) -> some View {
        image
            .resizable()
            .scaledToFill()
            .frame(width: 76, height: 76)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(.white.opacity(0.24), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.16), radius: 5, y: 2)
    }

    private var fallbackIconView: some View {
        Image(systemName: "note.text")
            .font(.system(size: 34, weight: .semibold))
            .foregroundStyle(.secondary)
            .frame(width: 76, height: 76)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(.white.opacity(0.18), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.12), radius: 5, y: 2)
    }
}

private struct AboutPrincipleRow: View {
    let title: String
    let subtitle: String
    let systemImage: String

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.body)

                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } icon: {
            Image(systemName: systemImage)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.secondary)
        }
    }
}

/// Collects bundle metadata once so the About view can render missing values safely.
struct AppAboutInfo {
    let displayName: String
    let version: String
    let build: String
    let websiteURL: URL
    let sourceCodeURL: URL

    static var current: AppAboutInfo {
        let bundle = Bundle.main
        return AppAboutInfo(
            displayName: bundle.stringValue(for: "CFBundleDisplayName")
                ?? bundle.stringValue(for: "CFBundleName")
                ?? "Notra",
            version: bundle.stringValue(for: "CFBundleShortVersionString") ?? "1.0",
            build: bundle.stringValue(for: "CFBundleVersion") ?? "1",
            websiteURL: URL(string: "https://notra-app.cc/")!,
            sourceCodeURL: URL(string: "https://github.com/akopulko/notra")!
        )
    }

    var versionDisplay: String {
        "Version \(version) (\(build))"
    }
}

private extension Bundle {
    func stringValue(for key: String) -> String? {
        object(forInfoDictionaryKey: key) as? String
    }
}
