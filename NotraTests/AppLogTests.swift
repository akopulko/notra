@testable import Notra
import Testing

/// Verifies debug filtering without asserting on OSLog's external output sink.
struct AppLogTests {
    @Test func disabledDebugLogDoesNotEvaluateMessage() {
        #if DEBUG
            AppLog.minimumLevelOverride = .info
            defer {
                AppLog.minimumLevelOverride = nil
            }

            var evaluated = false
            AppLog.debug(expensiveMessage(evaluated: &evaluated))

            #expect(evaluated == false)
        #endif
    }

    private func expensiveMessage(evaluated: inout Bool) -> String {
        evaluated = true
        return "debug message"
    }
}
