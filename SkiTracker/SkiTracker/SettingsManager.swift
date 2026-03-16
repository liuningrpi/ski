import Foundation
import Combine

// MARK: - Language

enum AppLanguage: String, CaseIterable, Codable {
    case english = "en"
    case chinese = "zh"

    var displayName: String {
        switch self {
        case .english: return "English"
        case .chinese: return "中文"
        }
    }
}

// MARK: - Unit System

enum UnitSystem: String, CaseIterable, Codable {
    case metric = "metric"
    case imperial = "imperial"

    var displayName: String {
        switch self {
        case .metric: return "Metric (km/h, m)"
        case .imperial: return "Imperial (mph, ft)"
        }
    }

    var speedUnit: String {
        switch self {
        case .metric: return "km/h"
        case .imperial: return "mph"
        }
    }

    var distanceUnit: String {
        switch self {
        case .metric: return "km"
        case .imperial: return "mi"
        }
    }

    var altitudeUnit: String {
        switch self {
        case .metric: return "m"
        case .imperial: return "ft"
        }
    }
}

// MARK: - Localized Strings

struct LocalizedStrings {
    let language: AppLanguage

    // Navigation & Titles
    var appTitle: String {
        language == .chinese ? "滑雪追踪器" : "Ski Tracker"
    }

    var history: String {
        language == .chinese ? "历史记录" : "History"
    }

    var settings: String {
        language == .chinese ? "设置" : "Settings"
    }

    // Permissions
    var locationPermissionNeeded: String {
        language == .chinese ? "需要定位权限才能记录滑雪轨迹" : "Location permission required to track skiing"
    }

    var authorizeLocation: String {
        language == .chinese ? "授权定位" : "Authorize Location"
    }

    var goToSettings: String {
        language == .chinese ? "前往设置开启定位" : "Go to Settings to Enable Location"
    }

    var locationServicesDisabled: String {
        language == .chinese ? "系统定位服务已关闭。请在系统设置中开启定位服务。" : "Location Services are turned off. Enable them in iPhone Settings."
    }

    var locationTrackingDenied: String {
        language == .chinese ? "定位权限不可用，已停止记录。请前往系统设置开启定位权限。" : "Location access was denied and tracking has stopped. Enable location permission in Settings."
    }

    var locationBackgroundAccessRecommended: String {
        language == .chinese ? "当前仅“使用期间”允许定位。若切到后台或锁屏可能停止记录，建议在设置中开启“始终允许”。" : "Location is set to While Using. Tracking may stop in background or when locked. Enable Always access in Settings."
    }

    // Auth Status
    var authNotRequested: String {
        language == .chinese ? "未请求" : "Not Requested"
    }

    var authRestricted: String {
        language == .chinese ? "受限" : "Restricted"
    }

    var authDenied: String {
        language == .chinese ? "已拒绝" : "Denied"
    }

    var authWhenInUse: String {
        language == .chinese ? "使用时允许" : "When In Use"
    }

    var authAlways: String {
        language == .chinese ? "始终允许" : "Always"
    }

    var authUnknown: String {
        language == .chinese ? "未知" : "Unknown"
    }

    // Tracking
    var startSkiing: String {
        language == .chinese ? "开始滑雪" : "Start Skiing"
    }

    var stopRecording: String {
        language == .chinese ? "停止录制" : "Stop Recording"
    }

    var pauseRecording: String {
        language == .chinese ? "暂停录制" : "Pause Recording"
    }

    var resumeRecording: String {
        language == .chinese ? "继续录制" : "Resume Recording"
    }

    var paused: String {
        language == .chinese ? "已暂停" : "Paused"
    }

    var recording: String {
        language == .chinese ? "录制中" : "Recording"
    }

    var points: String {
        language == .chinese ? "点" : "pts"
    }

    // Stop Confirmation
    var stopConfirmTitle: String {
        language == .chinese ? "停止录制？" : "Stop Recording?"
    }

    var stopConfirmMessage: String {
        language == .chinese ? "当前轨迹将被保存，你可以在历史记录中回看。" : "Current track will be saved. You can review it in history."
    }

    var continueRecording: String {
        language == .chinese ? "继续录制" : "Continue"
    }

    var stopAndSave: String {
        language == .chinese ? "停止并保存" : "Stop & Save"
    }

    // Stats
    var duration: String {
        language == .chinese ? "时长" : "Duration"
    }

    var distance: String {
        language == .chinese ? "距离" : "Distance"
    }

    var maxSpeed: String {
        language == .chinese ? "最高速度" : "Max Speed"
    }

    var avgSpeed: String {
        language == .chinese ? "平均速度" : "Avg Speed"
    }

    var maxAltitude: String {
        language == .chinese ? "最高海拔" : "Max Altitude"
    }

    var elevationDrop: String {
        language == .chinese ? "海拔落差" : "Elevation Drop"
    }

    var trackPoints: String {
        language == .chinese ? "轨迹点数" : "Track Points"
    }

    // History
    var close: String {
        language == .chinese ? "关闭" : "Close"
    }

    var noHistory: String {
        language == .chinese ? "暂无历史记录" : "No History"
    }

    var noHistoryMessage: String {
        language == .chinese ? "完成一次滑雪录制后，数据将自动保存在此处" : "Complete a skiing session to see it here"
    }

    var currentLocation: String {
        language == .chinese ? "当前位置" : "Current Location"
    }

    var deleteAll: String {
        language == .chinese ? "删除全部" : "Delete All"
    }

    var delete: String {
        language == .chinese ? "删除" : "Delete"
    }

    var deleteConfirmTitle: String {
        language == .chinese ? "删除此记录？" : "Delete this record?"
    }

    var deleteAllConfirmTitle: String {
        language == .chinese ? "删除全部记录？" : "Delete all records?"
    }

    var deleteConfirmMessage: String {
        language == .chinese ? "此操作无法撤销" : "This action cannot be undone"
    }

    var cancel: String {
        language == .chinese ? "取消" : "Cancel"
    }

    // Settings
    var languageLabel: String {
        language == .chinese ? "语言" : "Language"
    }

    var unitsLabel: String {
        language == .chinese ? "单位" : "Units"
    }

    var supportTitle: String {
        language == .chinese ? "支持开发者" : "Support the Developer"
    }

    var supportHeadline: String {
        language == .chinese ? "如果这个 App 很有用，请请我喝杯咖啡。" : "If this app made your ski day better, buy me a coffee."
    }

    var supportFootnote: String {
        language == .chinese ? "一次性打赏，无订阅。" : "One-time tip. No subscription."
    }

    var supportSmallTip: String {
        language == .chinese ? "美式咖啡" : "Black Coffee"
    }

    var supportLargeTip: String {
        language == .chinese ? "卡布奇诺" : "Cappuccino"
    }

    var supportThankYou: String {
        language == .chinese ? "感谢支持，这会帮助我继续改进这个 App。" : "Thanks for the support. It helps me keep improving the app."
    }

    var supportPending: String {
        language == .chinese ? "付款正在处理中。" : "Payment is pending."
    }

    var supportUnavailable: String {
        language == .chinese ? "打赏暂不可用。请稍后再试。" : "Tips are unavailable right now. Try again later."
    }

    var supportPurchaseFailed: String {
        language == .chinese ? "支付未完成。" : "Purchase did not complete."
    }

    // Day Summary
    var daySummary: String {
        language == .chinese ? "当日总结" : "Day Summary"
    }

    var runs: String {
        language == .chinese ? "趟数" : "Runs"
    }

    var totalDistance: String {
        language == .chinese ? "总距离" : "Total Distance"
    }

    var totalDuration: String {
        language == .chinese ? "总时长" : "Total Duration"
    }

    var totalDescent: String {
        language == .chinese ? "总下降" : "Total Descent"
    }

    var maxDescentRun: String {
        language == .chinese ? "单趟最大落差" : "Max Descent (Single Run)"
    }

    var fastestRun: String {
        language == .chinese ? "最快一趟" : "Fastest Run"
    }

    var avgSpeedDay: String {
        language == .chinese ? "平均速度" : "Avg Speed"
    }

    var maxSpeedDay: String {
        language == .chinese ? "最高速度" : "Max Speed"
    }

    var longestRun: String {
        language == .chinese ? "最长一趟" : "Longest Run"
    }

    var avgRunDistance: String {
        language == .chinese ? "平均每趟距离" : "Avg Distance/Run"
    }

    var runsCount: String {
        language == .chinese ? "趟" : "runs"
    }

    // Authentication
    var signIn: String {
        language == .chinese ? "登录" : "Sign In"
    }

    var signOut: String {
        language == .chinese ? "退出登录" : "Sign Out"
    }

    var signInWithApple: String {
        language == .chinese ? "使用 Apple 登录" : "Sign in with Apple"
    }

    var signInWithGoogle: String {
        language == .chinese ? "使用 Google 登录" : "Sign in with Google"
    }

    var welcomeMessage: String {
        language == .chinese ? "登录以同步您的滑雪数据" : "Sign in to sync your ski data"
    }

    var syncData: String {
        language == .chinese ? "同步数据" : "Sync Data"
    }

    var syncing: String {
        language == .chinese ? "同步中..." : "Syncing..."
    }

    var lastSynced: String {
        language == .chinese ? "上次同步" : "Last synced"
    }

    var account: String {
        language == .chinese ? "账户" : "Account"
    }

    var signedInAs: String {
        language == .chinese ? "已登录为" : "Signed in as"
    }

    var continueAsGuest: String {
        language == .chinese ? "暂不登录" : "Continue as Guest"
    }

    var dataStoredLocally: String {
        language == .chinese ? "数据仅保存在本地" : "Data stored locally only"
    }

    var signInToSync: String {
        language == .chinese ? "登录以同步到云端" : "Sign in to sync to cloud"
    }

    // Run Segmentation
    var currentState: String {
        language == .chinese ? "当前状态" : "Current State"
    }

    var stateIdle: String {
        language == .chinese ? "空闲" : "Idle"
    }

    var stateSkiing: String {
        language == .chinese ? "滑行中" : "Skiing"
    }

    var stateLift: String {
        language == .chinese ? "缆车上行" : "On Lift"
    }

    var stateStopped: String {
        language == .chinese ? "停止" : "Stopped"
    }

    var runsCompleted: String {
        language == .chinese ? "已完成趟数" : "Runs Completed"
    }

    var liftsCompleted: String {
        language == .chinese ? "缆车次数" : "Lifts Taken"
    }

    var verticalDrop: String {
        language == .chinese ? "累计下降" : "Vertical Drop"
    }

    var runDetails: String {
        language == .chinese ? "单趟详情" : "Run Details"
    }

    var runPlayback: String {
        language == .chinese ? "滑行回放" : "Run Playback"
    }

    var dayPlayback: String {
        language == .chinese ? "全天回放" : "Day Playback"
    }

    var play: String {
        language == .chinese ? "播放" : "Play"
    }

    var pause: String {
        language == .chinese ? "暂停" : "Pause"
    }

    var reset: String {
        language == .chinese ? "重置" : "Reset"
    }

    var noTrackData: String {
        language == .chinese ? "暂无轨迹数据" : "No track data"
    }

    var segmentType: String {
        language == .chinese ? "类型" : "Type"
    }

    var deleteRunConfirmTitle: String {
        language == .chinese ? "删除此趟？" : "Delete this run?"
    }

    var deleteRunConfirmMessage: String {
        language == .chinese ? "此数据将被永久删除" : "This data will be permanently deleted"
    }

    var startAltitude: String {
        language == .chinese ? "起始海拔" : "Start Altitude"
    }

    var endAltitude: String {
        language == .chinese ? "结束海拔" : "End Altitude"
    }

    // Leaderboard
    var leaderboard: String {
        language == .chinese ? "排行榜" : "Leaderboard"
    }

    var leaderboardCategoryMax: String {
        language == .chinese ? "最高纪录" : "Max Records"
    }

    var leaderboardCategoryMost: String {
        language == .chinese ? "最多纪录" : "Most Records"
    }

    var leaderboardOlympicBoard: String {
        language == .chinese ? "奥运榜单" : "Olympic Board"
    }

    var leaderboardFullRank: String {
        language == .chinese ? "完整排名" : "Full Ranking"
    }

    var rankBy: String {
        language == .chinese ? "排名指标" : "Rank By"
    }

    var leaderboardNoData: String {
        language == .chinese ? "暂无排行榜数据" : "No leaderboard data yet"
    }

    var leaderboardSingleUserHint: String {
        language == .chinese ? "当前没有好友，排行榜仅显示你自己。" : "No friends yet, so the leaderboard currently shows only you."
    }

    var leaderboardFriendsOnlyHint: String {
        language == .chinese ? "仅显示已互加好友的用户。" : "Only mutual friends are shown."
    }

    var leaderboardSyncTimeout: String {
        language == .chinese ? "排行榜同步超时，已显示本地数据。" : "Leaderboard sync timed out. Showing local data."
    }

    var leaderboardMetricTopSpeed: String {
        language == .chinese ? "最高速度" : "Top Speed"
    }

    var leaderboardMetricTopRunDescent: String {
        language == .chinese ? "单趟最大落差" : "Top Run Descent"
    }

    var leaderboardMetricMaxAltitude: String {
        language == .chinese ? "最高海拔" : "Max Altitude"
    }

    var leaderboardMetricLongestRun: String {
        language == .chinese ? "最长单趟距离" : "Longest Run"
    }

    var leaderboardMetricTotalDistance: String {
        language == .chinese ? "总滑行距离" : "Total Distance"
    }

    var leaderboardMetricRunCount: String {
        language == .chinese ? "总趟数" : "Run Count"
    }

    var leaderboardMetricTotalVerticalDrop: String {
        language == .chinese ? "总下降" : "Total Vertical Drop"
    }

    var leaderboardMetricTotalDuration: String {
        language == .chinese ? "总时长" : "Total Duration"
    }

    var youLabel: String {
        language == .chinese ? "我" : "You"
    }

    // Friends
    var friends: String {
        language == .chinese ? "好友" : "Friends"
    }

    var myFriendQR: String {
        language == .chinese ? "我的好友二维码" : "My Friend QR Code"
    }

    var addFriend: String {
        language == .chinese ? "添加好友" : "Add Friend"
    }

    var enterFriendCodeOrLink: String {
        language == .chinese ? "输入好友邀请码或链接" : "Enter friend code or invite link"
    }

    var addByCodeOrLink: String {
        language == .chinese ? "通过邀请码/链接添加" : "Add by Code/Link"
    }

    var scanFriendQRCode: String {
        language == .chinese ? "扫描好友二维码" : "Scan Friend QR"
    }

    var shareInviteLink: String {
        language == .chinese ? "分享邀请链接" : "Share Invite Link"
    }

    var copyInviteLink: String {
        language == .chinese ? "复制邀请链接" : "Copy Invite Link"
    }

    var inviteLinkCopied: String {
        language == .chinese ? "邀请链接已复制" : "Invite link copied"
    }

    var loadingFriends: String {
        language == .chinese ? "加载好友中..." : "Loading friends..."
    }

    var noFriendsYet: String {
        language == .chinese ? "还没有好友，先分享你的二维码吧。" : "No friends yet. Share your QR to add friends."
    }

    var signInToManageFriends: String {
        language == .chinese ? "请先登录后管理好友。" : "Please sign in to manage friends."
    }

    var friendInviteSavedSignInNeeded: String {
        language == .chinese ? "已收到好友邀请，登录后会自动添加。" : "Friend invite received. Sign in to add automatically."
    }

    var friendInvalidInvite: String {
        language == .chinese ? "无效的好友邀请码或链接" : "Invalid friend invite code or link"
    }

    var friendCannotAddSelf: String {
        language == .chinese ? "不能添加自己为好友" : "You cannot add yourself as a friend"
    }

    var friendAccountNotFound: String {
        language == .chinese ? "未找到该账号" : "That account was not found"
    }

    var friendAdded: String {
        language == .chinese ? "已添加好友" : "Friend added"
    }

    var cameraPermissionRequired: String {
        language == .chinese ? "需要相机权限以扫描二维码。请在系统设置中开启。" : "Camera permission is required to scan QR codes. Enable it in Settings."
    }

    // Heart Rate (local only)
    var maxHeartRate: String {
        language == .chinese ? "最高心率" : "Max Heart Rate"
    }

    var avgHeartRate: String {
        language == .chinese ? "平均心率" : "Avg Heart Rate"
    }

    var heartRateUnit: String {
        "bpm"
    }

    var waitingHeartRateData: String {
        language == .chinese
            ? "正在等待 Apple Watch 心率同步，请确认手表佩戴正常，并已在 iPhone 的「健康」里允许本应用读取心率。"
            : "Waiting for Apple Watch heart-rate sync. Confirm watch is worn and Health permissions allow heart-rate read for this app."
    }

    // Feedback
    var feedbackTitle: String {
        language == .chinese ? "意见反馈" : "Feedback"
    }

    var feedbackButton: String {
        language == .chinese ? "发送反馈" : "Send Feedback"
    }

    var feedbackDescription: String {
        language == .chinese ? "告诉我们您的建议或遇到的问题" : "Share your suggestions or report issues"
    }

    var feedbackPlaceholder: String {
        language == .chinese ? "请输入您的意见或建议..." : "Enter your feedback here..."
    }

    var feedbackSending: String {
        language == .chinese ? "发送中..." : "Sending..."
    }

    var feedbackSent: String {
        language == .chinese ? "感谢您的反馈！" : "Thank you for your feedback!"
    }

    var feedbackFailed: String {
        language == .chinese ? "发送失败，请稍后重试" : "Failed to send. Please try again later."
    }

    var feedbackEmpty: String {
        language == .chinese ? "请输入反馈内容" : "Please enter your feedback"
    }
}

// MARK: - Settings Manager

final class SettingsManager: ObservableObject {

    static let shared = SettingsManager()

    @Published var language: AppLanguage {
        didSet {
            UserDefaults.standard.set(language.rawValue, forKey: "app_language")
        }
    }

    @Published var unitSystem: UnitSystem {
        didSet {
            UserDefaults.standard.set(unitSystem.rawValue, forKey: "unit_system")
        }
    }

    var strings: LocalizedStrings {
        LocalizedStrings(language: language)
    }

    private init() {
        // Load saved preferences
        if let langRaw = UserDefaults.standard.string(forKey: "app_language"),
           let lang = AppLanguage(rawValue: langRaw) {
            self.language = lang
        } else {
            // Default based on system locale
            let systemLang = Locale.current.language.languageCode?.identifier ?? "en"
            self.language = systemLang.starts(with: "zh") ? .chinese : .english
        }

        if let unitRaw = UserDefaults.standard.string(forKey: "unit_system"),
           let unit = UnitSystem(rawValue: unitRaw) {
            self.unitSystem = unit
        } else {
            // Default based on system locale (US uses imperial)
            let region = Locale.current.region?.identifier ?? ""
            self.unitSystem = (region == "US") ? .imperial : .metric
        }
    }

    // MARK: - Unit Conversions

    /// Convert km/h to current unit
    func formatSpeed(_ kmh: Double) -> String {
        switch unitSystem {
        case .metric:
            return String(format: "%.1f", kmh)
        case .imperial:
            return String(format: "%.1f", kmh * 0.621371)
        }
    }

    /// Convert km to current unit
    func formatDistance(_ km: Double) -> String {
        switch unitSystem {
        case .metric:
            return String(format: "%.2f", km)
        case .imperial:
            return String(format: "%.2f", km * 0.621371)
        }
    }

    /// Convert meters to current unit
    func formatAltitude(_ meters: Double) -> String {
        switch unitSystem {
        case .metric:
            return String(format: "%.0f", meters)
        case .imperial:
            return String(format: "%.0f", meters * 3.28084)
        }
    }
}
