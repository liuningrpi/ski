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
