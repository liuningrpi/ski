//
//  WatchSkiTrackerApp.swift
//  WatchSkiTracker Watch App
//
//  Created by Ning Liu on 3/6/26.
//

import SwiftUI

@main
struct WatchSkiTracker_Watch_AppApp: App {
    init() {
        if #available(iOS 26.0, watchOS 10.0, *) {
            WatchLiveWorkoutHeartRateService.bootstrap()
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
