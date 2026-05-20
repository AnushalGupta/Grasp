import SwiftUI

@main
struct GraspApp: App {
    @StateObject private var browserState = BrowserState.shared
    @StateObject private var downloadManager = DownloadManager.shared
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(browserState)
                .environmentObject(downloadManager)
                .preferredColorScheme(.dark) // Sleek Dark Mode standard for premium aesthetics
        }
    }
}
