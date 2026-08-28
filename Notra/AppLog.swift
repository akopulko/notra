import Foundation
import OSLog

enum AppLog {
    enum Level: Int {
        case debug
        case info
        case warning
        case error
    }

    #if DEBUG
    private static let minimumLevelLock = OSAllocatedUnfairLock(initialState: Level?.none)

    static var minimumLevelOverride: Level? {
        get { minimumLevelLock.withLock { $0 } }
        set { minimumLevelLock.withLock { $0 = newValue } }
    }
    #endif

    static func debug(
        _ message: @autoclosure () -> String,
        function: StaticString = #function
    ) {
        write(level: .debug, message: message, function: function)
    }

    static func info(
        _ message: @autoclosure () -> String,
        function: StaticString = #function
    ) {
        write(level: .info, message: message, function: function)
    }

    static func warning(
        _ message: @autoclosure () -> String,
        function: StaticString = #function
    ) {
        write(level: .warning, message: message, function: function)
    }

    static func error(
        _ message: @autoclosure () -> String,
        function: StaticString = #function
    ) {
        write(level: .error, message: message, function: function)
    }

    private static func write(
        level: Level,
        message: () -> String,
        function: StaticString
    ) {
        guard isEnabled(level) else {
            return
        }

        let line = "\(timestamp()) [\(level.label)] \(function) - \(message())"
        print(line)
        logger.log(level: osLogType(for: level), "\(line, privacy: .public)")
    }

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "app.notra.Notra",
        category: "App"
    )

    private static func osLogType(for level: Level) -> OSLogType {
        switch level {
        case .debug:
            .debug
        case .info:
            .info
        case .warning:
            .default
        case .error:
            .error
        }
    }

    private static func isEnabled(_ level: Level) -> Bool {
        level.rawValue >= minimumLevel.rawValue
    }

    private static var minimumLevel: Level {
        #if DEBUG
        if let minimumLevelOverride {
            return minimumLevelOverride
        }
        #endif

        let environmentLevel = ProcessInfo.processInfo.environment["NOTRA_LOG_LEVEL"]
            .flatMap(Level.init(rawValue:))
        if let environmentLevel {
            return environmentLevel
        }

        #if DEBUG
        return .debug
        #else
        return .info
        #endif
    }

    private static func timestamp() -> String {
        Date.now.formatted(
            .dateTime
                .year(.twoDigits)
                .month(.twoDigits)
                .day(.twoDigits)
                .hour()
                .minute()
                .second()
        )
    }
}

extension AppLog.Level {
    nonisolated init?(rawValue: String) {
        switch rawValue.lowercased() {
        case "debug":
            self = .debug
        case "info":
            self = .info
        case "warn", "warning":
            self = .warning
        case "error":
            self = .error
        default:
            return nil
        }
    }

    nonisolated var label: String {
        switch self {
        case .debug:
            "DEBUG"
        case .info:
            "INFO"
        case .warning:
            "WARN"
        case .error:
            "ERROR"
        }
    }
}
