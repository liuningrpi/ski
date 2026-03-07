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

struct WatchHeartRateCommandMessage {
    let type: WatchHeartRateBridgeType
    let sessionId: String
    let startedAt: Date?

    var dictionary: [String: Any] {
        var payload: [String: Any] = [
            WatchHeartRateBridgeKeys.type: type.rawValue,
            WatchHeartRateBridgeKeys.sessionId: sessionId
        ]
        if let startedAt {
            payload[WatchHeartRateBridgeKeys.startedAt] = startedAt.timeIntervalSince1970
        }
        return payload
    }
}

struct WatchHeartRateSampleMessage {
    let sessionId: String?
    let bpm: Double
    let timestamp: Date

    init?(dictionary: [String: Any]) {
        guard let typeRaw = dictionary[WatchHeartRateBridgeKeys.type] as? String,
              typeRaw == WatchHeartRateBridgeType.liveHeartRateSample.rawValue,
              let bpm = dictionary[WatchHeartRateBridgeKeys.bpm] as? Double,
              let ts = dictionary[WatchHeartRateBridgeKeys.timestamp] as? TimeInterval else {
            return nil
        }
        self.sessionId = dictionary[WatchHeartRateBridgeKeys.sessionId] as? String
        self.bpm = bpm
        self.timestamp = Date(timeIntervalSince1970: ts)
    }

    var dictionary: [String: Any] {
        var payload: [String: Any] = [
            WatchHeartRateBridgeKeys.type: WatchHeartRateBridgeType.liveHeartRateSample.rawValue,
            WatchHeartRateBridgeKeys.bpm: bpm,
            WatchHeartRateBridgeKeys.timestamp: timestamp.timeIntervalSince1970
        ]
        if let sessionId {
            payload[WatchHeartRateBridgeKeys.sessionId] = sessionId
        }
        return payload
    }
}
