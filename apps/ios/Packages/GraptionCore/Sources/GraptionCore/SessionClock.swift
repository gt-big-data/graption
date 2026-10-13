import Foundation

public class SessionClock {
    private let startTime: Date

    public init() {
        self.startTime = Date()
    }

    /// Returns the number of seconds elapsed since this clock instance was initialized.
    public var secondsElapsed: TimeInterval {
        return Date().timeIntervalSince(startTime)
    }
}
