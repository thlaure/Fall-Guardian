@main
enum WatchAlertDeadlineExecutableTests {
    static func main() {
        assert(!WatchAlertDeadline.isActive(timestamp: 0, now: 1_000))
        assert(!WatchAlertDeadline.isActive(timestamp: 2_000, now: 1_000))
        assert(WatchAlertDeadline.isActive(timestamp: 1_000, now: 1_000))
        assert(WatchAlertDeadline.isActive(timestamp: 1_000, now: 30_999))
        assert(!WatchAlertDeadline.isActive(timestamp: 1_000, now: 31_000))
        assert(
            WatchAlertDeadline.remainingMilliseconds(
                timestamp: 1_000,
                now: 11_000
            ) == 20_000
        )
        assert(
            WatchAlertDeadline.remainingMilliseconds(
                timestamp: 1_000,
                now: 31_000
            ) == 0
        )
    }
}
