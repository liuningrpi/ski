import SwiftUI

@main
struct SkiTrackerApp: App {

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
