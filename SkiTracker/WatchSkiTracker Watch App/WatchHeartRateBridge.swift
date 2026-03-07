import Foundation

// Shared watch/iPhone payload keys for live heart-rate sync.
enum WatchHeartRateBridgeKeys {
    static let type = "type"
    static let sessionId = "sessionId"
    static let startedAt = "startedAt"
    static let bpm = "bpm"
    static let timestamp = "timestamp"
}

enum WatchHeartRateBridgeType: String {
    case startLiveHeartRate = "start_live_heart_rate"
    case stopLiveHeartRate = "stop_live_heart_rate"
    case liveHeartRateSample = "live_heart_rate_sample"
}
