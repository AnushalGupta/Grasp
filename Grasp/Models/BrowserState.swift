import Foundation
import Combine
import WebKit

class BrowserTab: Identifiable, ObservableObject {
    let id: UUID = UUID()
    @Published var url: URL? = nil
    @Published var title: String = "New Tab"
    @Published var isLoading: Bool = false
    @Published var canGoBack: Bool = false
    @Published var canGoForward: Bool = false
    @Published var estimatedProgress: Double = 0.0
    
    init(url: URL? = nil) {
        self.url = url
        if let url = url {
            self.title = url.host ?? "Loading..."
        }
    }
}

struct CapturedMedia: Identifiable, Hashable {
    let id = UUID()
    let url: URL
    let title: String
    let type: String
    let timestamp: Date
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(url)
        hasher.combine(type)
    }
    
    static func == (lhs: CapturedMedia, rhs: CapturedMedia) -> Bool {
        return lhs.url == rhs.url && lhs.type == rhs.type
    }
}

class BrowserState: ObservableObject {
    static let shared = BrowserState()
    
    @Published var tabs: [BrowserTab] = []
    @Published var activeTabIndex: Int = 0
    @Published var bookmarks: [String] = []
    @Published var history: [String] = []
    @Published var capturedMedia: Set<CapturedMedia> = []
    
    // Advanced Settings
    @Published var adblockEnabled: Bool = true
    @Published var threadCountSetting: Int = 8
    @Published var customDNS: String = ""
    @Published var selectedDNSProvider: String = "Default"
    @Published var autoGrabMedia: Bool = true
    @Published var longPressGestureEnabled: Bool = true
    @Published var extractAudioOnly: Bool = false
    
    let dnsProviders = ["Default", "Cloudflare (1.1.1.1)", "Google (8.8.8.8)", "AdGuard DNS", "NextDNS"]
    
    private var cancellables = Set<AnyCancellable>()
    
    private init() {
        // Load defaults or add initial tab
        addTab(url: URL(string: "https://www.google.com"))
        loadSavedSettings()
        
        // Sync setting changes with DownloadManager configuration
        $threadCountSetting
            .sink { DownloadManager.shared.defaultThreadCount = $0 }
            .store(in: &cancellables)
    }
    
    var activeTab: BrowserTab? {
        guard activeTabIndex >= 0 && activeTabIndex < tabs.count else { return nil }
        return tabs[activeTabIndex]
    }
    
    func addTab(url: URL? = nil) {
        let newTab = BrowserTab(url: url)
        DispatchQueue.main.async {
            self.tabs.append(newTab)
            self.activeTabIndex = self.tabs.count - 1
        }
    }
    
    func closeTab(at index: Int) {
        guard tabs.count > 1 else {
            // Keep at least one blank tab open
            tabs[0].url = nil
            tabs[0].title = "New Tab"
            return
        }
        
        DispatchQueue.main.async {
            self.tabs.remove(at: index)
            if self.activeTabIndex >= self.tabs.count {
                self.activeTabIndex = self.tabs.count - 1
            }
        }
    }
    
    func addBookmark(url: String) {
        guard !bookmarks.contains(url) else { return }
        DispatchQueue.main.async {
            self.bookmarks.append(url)
            self.saveSettings()
        }
    }
    
    func removeBookmark(url: String) {
        DispatchQueue.main.async {
            self.bookmarks.removeAll { $0 == url }
            self.saveSettings()
        }
    }
    
    func addHistory(url: String) {
        DispatchQueue.main.async {
            // Remove duplicates and put at top
            self.history.removeAll { $0 == url }
            self.history.insert(url, at: 0)
            
            // Limit history count
            if self.history.count > 100 {
                self.history.removeLast()
            }
            self.saveSettings()
        }
    }
    
    func clearHistory() {
        DispatchQueue.main.async {
            self.history.removeAll()
            self.saveSettings()
        }
    }
    
    func addCapturedMedia(url: URL, title: String, type: String) {
        guard autoGrabMedia else { return }
        
        let media = CapturedMedia(
            url: url,
            title: title,
            type: type,
            timestamp: Date()
        )
        
        DispatchQueue.main.async {
            self.capturedMedia.insert(media)
        }
    }
    
    func clearCapturedMedia() {
        DispatchQueue.main.async {
            self.capturedMedia.removeAll()
        }
    }
    
    // MARK: - Save/Load Settings
    private func saveSettings() {
        let defaults = UserDefaults.standard
        defaults.set(bookmarks, forKey: "GraspBookmarks")
        defaults.set(history, forKey: "GraspHistory")
        defaults.set(adblockEnabled, forKey: "GraspAdblockEnabled")
        defaults.set(threadCountSetting, forKey: "GraspThreadCount")
        defaults.set(customDNS, forKey: "GraspCustomDNS")
        defaults.set(selectedDNSProvider, forKey: "GraspSelectedDNSProvider")
        defaults.set(autoGrabMedia, forKey: "GraspAutoGrabMedia")
        defaults.set(longPressGestureEnabled, forKey: "GraspLongPressGesture")
    }
    
    private func loadSavedSettings() {
        let defaults = UserDefaults.standard
        self.bookmarks = defaults.stringArray(forKey: "GraspBookmarks") ?? []
        self.history = defaults.stringArray(forKey: "GraspHistory") ?? []
        
        if defaults.object(forKey: "GraspAdblockEnabled") != nil {
            self.adblockEnabled = defaults.bool(forKey: "GraspAdblockEnabled")
        }
        if defaults.object(forKey: "GraspThreadCount") != nil {
            self.threadCountSetting = defaults.integer(forKey: "GraspThreadCount")
        }
        self.customDNS = defaults.string(forKey: "GraspCustomDNS") ?? ""
        self.selectedDNSProvider = defaults.string(forKey: "GraspSelectedDNSProvider") ?? "Default"
        
        if defaults.object(forKey: "GraspAutoGrabMedia") != nil {
            self.autoGrabMedia = defaults.bool(forKey: "GraspAutoGrabMedia")
        }
        if defaults.object(forKey: "GraspLongPressGesture") != nil {
            self.longPressGestureEnabled = defaults.bool(forKey: "GraspLongPressGesture")
        }
    }
}
