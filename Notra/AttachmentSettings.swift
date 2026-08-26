import Foundation

enum AttachmentSettingKey {
    static let maximumSizeMB = "attachments.maximumSizeMB"
}

enum AttachmentSettings {
    static let defaultMaximumSizeMB = 100
    static let supportedMaximumSizeRange = 1...500
    static let maximumSizeStep = 10

    static func clampedMaximumSizeMB(_ value: Int) -> Int {
        min(max(value, supportedMaximumSizeRange.lowerBound), supportedMaximumSizeRange.upperBound)
    }

    static func maximumSizeBytes(for megabytes: Int) -> Int64 {
        Int64(clampedMaximumSizeMB(megabytes)) * 1024 * 1024
    }
}
