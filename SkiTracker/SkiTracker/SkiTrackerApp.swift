import SwiftUI
import FirebaseCore
import GoogleSignIn
import UserNotifications

// MARK: - App Delegate for Firebase

class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        FirebaseApp.configure()
        UNUserNotificationCenter.current().delegate = self
        UIDevice.current.isBatteryMonitoringEnabled = true
        return true
    }

    func application(_ app: UIApplication,
                     open url: URL,
                     options: [UIApplication.OpenURLOptionsKey: Any]) -> Bool {
        if GIDSignIn.sharedInstance.handle(url) {
            return true
        }
        return FriendService.shared.handleIncomingURL(url)
    }

    func applicationWillTerminate(_ application: UIApplication) {
        LoggingService.shared.flush()
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
        LoggingService.shared.flush()
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}

// MARK: - Main App

@main
struct SkiTrackerApp: App {

    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate

    @StateObject private var locationTracker = LocationTracker()
    @StateObject private var sessionStore = SessionStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(locationTracker)
                .environmentObject(sessionStore)
        }
    }
}
