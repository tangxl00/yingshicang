import Foundation
import os

/// 统一日志出口。抓包与线上排查都靠它，避免用 print 污染 stdout
/// （CI 里 stdout 会被 xcodebuild 的大量输出淹没）。
enum Log {
    private static let logger = os.Logger(subsystem: "com.yingshicang.ios", category: "app")

    static func debug(_ message: String) {
        logger.debug("\(message, privacy: .public)")
    }

    static func info(_ message: String) {
        logger.info("\(message, privacy: .public)")
    }

    static func warn(_ message: String) {
        logger.warning("\(message, privacy: .public)")
    }

    static func error(_ message: String) {
        logger.error("\(message, privacy: .public)")
    }
}
