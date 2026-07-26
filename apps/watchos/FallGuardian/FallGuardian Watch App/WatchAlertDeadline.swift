enum WatchAlertDeadline {
    static let windowMilliseconds: Int64 = 30_000

    static func isActive(timestamp: Int64, now: Int64) -> Bool {
        guard timestamp > 0, now >= timestamp else { return false }
        return now - timestamp < windowMilliseconds
    }

    static func remainingMilliseconds(timestamp: Int64, now: Int64) -> Int64 {
        guard isActive(timestamp: timestamp, now: now) else { return 0 }
        return windowMilliseconds - (now - timestamp)
    }
}
