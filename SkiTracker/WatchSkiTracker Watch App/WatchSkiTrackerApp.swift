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
        WatchLiveWorkoutHeartRateService.bootstrap()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
