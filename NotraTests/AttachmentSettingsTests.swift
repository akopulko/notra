@testable import Notra
import Testing

struct AttachmentSettingsTests {
    @Test func defaultMaximumAttachmentSizeIsOneHundredMegabytes() {
        #expect(AttachmentSettings.defaultMaximumSizeMB == 100)
        #expect(AttachmentSettings.maximumSizeBytes(for: AttachmentSettings.defaultMaximumSizeMB) == 104_857_600)
    }

    @Test func maximumAttachmentSizeIsClampedToSupportedRange() {
        #expect(AttachmentSettings.clampedMaximumSizeMB(0) == 1)
        #expect(AttachmentSettings.clampedMaximumSizeMB(250) == 250)
        #expect(AttachmentSettings.clampedMaximumSizeMB(1_000) == 500)
    }
}
