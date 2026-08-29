//
//  mankaiApp.swift
//  mankai
//
//  Created by Travis XU on 20/6/2025.
//

import SwiftUI

@main struct mankai: App {
    init() {
        // Initialize SyncService to start periodic syncing
        _ = SyncService.shared

        // Observe when app becomes active
        NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { _ in Task { await Self.checkAndUpdate() } }
    }

    private static func checkAndUpdate() async {
        if let lastUpdateTime = UpdateService.shared.lastUpdateTime {
            let timeInterval = Date().timeIntervalSince(lastUpdateTime)
            if timeInterval > 300 {  // 5 minutes in seconds
                try? await UpdateService.shared.update()
            }
        } else {
            // No update has been performed yet
            try? await UpdateService.shared.update()
        }
    }

    var body: some Scene { WindowGroup { MainScreen() } }
}
