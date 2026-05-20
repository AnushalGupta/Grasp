import SwiftUI

struct ContentView: View {
    @EnvironmentObject var state: BrowserState
    @EnvironmentObject var downloadManager: DownloadManager
    
    @State private var urlInput: String = "https://www.google.com"
    @State private var showTabsGrid: Bool = false
    @State private var showDownloads: Bool = false
    @State private var showSettings: Bool = false
    @State private var showMediaGrabberList: Bool = false
    
    // Video hold popup triggers
    @State private var showLongPressPrompt: Bool = false
    @State private var promptUrl: URL? = nil
    @State private var promptTitle: String = ""
    @State private var promptType: String = ""
    @State private var customDownloadName: String = ""
    @State private var customThreadCount: Double = 8.0
    
    var body: some View {
        ZStack {
            // Sleek Background color matching dark-mode glassmorphism
            Color(red: 0.05, green: 0.05, blue: 0.08)
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // MARK: - Premium Glassmorphic Header / URL Bar
                headerBar
                
                // MARK: - Main Web Content Space
                if let activeTab = state.activeTab {
                    BrowserTabView(tab: activeTab)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .transition(.slide)
                        .onChange(of: activeTab.url) { newUrl in
                            if let newUrl = newUrl {
                                urlInput = newUrl.absoluteString
                            }
                        }
                } else {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
                
                // MARK: - Bottom Quick Navigation Toolbar
                bottomToolbar
            }
            .blur(radius: (showTabsGrid || showLongPressPrompt) ? 10 : 0)
            
            // MARK: - Floating IDM Media Grabber Notification Overlay
            if state.autoGrabMedia && !state.capturedMedia.isEmpty {
                VStack {
                    Spacer()
                    floatingMediaGrabberBar
                        .padding(.bottom, 70) // Elevate above bottom bar
                }
            }
            
            // MARK: - Safari-Style card based Tab Switcher Overlay
            if showTabsGrid {
                tabsManagerGrid
            }
            
            // MARK: - Premium Long-press Video Download Prompt Popup
            if showLongPressPrompt {
                downloadPromptOverlay
            }
        }
        // Bind incoming notifications from webview gestures
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("GraspShowDownloadPrompt"))) { notification in
            if let userInfo = notification.userInfo,
               let url = userInfo["url"] as? URL,
               let title = userInfo["title"] as? String,
               let type = userInfo["type"] as? String {
                self.promptUrl = url
                self.promptTitle = title
                self.promptType = type
                self.customDownloadName = url.lastPathComponent.isEmpty ? "downloaded_video.mp4" : url.lastPathComponent
                self.customThreadCount = Double(state.threadCountSetting)
                withAnimation(.spring()) {
                    self.showLongPressPrompt = true
                }
            }
        }
        // Sheet panels
        .sheet(isPresented: $showDownloads) {
            DownloadsListView()
                .environmentObject(state)
                .environmentObject(downloadManager)
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
                .environmentObject(state)
                .environmentObject(downloadManager)
        }
        .sheet(isPresented: $showMediaGrabberList) {
            MediaGrabberListView(onDownload: { media, threads in
                downloadManager.startDownload(url: media.url, customFileName: media.title, threadCount: threads)
                showMediaGrabberList = false
            })
            .environmentObject(state)
        }
    }
    
    // MARK: - Header component with Glassmorphic URL bar
    private var headerBar: some View {
        HStack(spacing: 12) {
            // Shield adblock status toggle
            Button(action: {
                state.adblockEnabled.toggle()
                // Force reload active rules list
                if state.adblockEnabled {
                    AdBlockerManager.shared.loadExistingRuleList()
                } else {
                    AdBlockerManager.shared.clearAllRules()
                }
            }) {
                Image(systemName: state.adblockEnabled ? "shield.fill" : "shield.slash")
                    .font(.system(size: 18))
                    .foregroundColor(state.adblockEnabled ? .green : .red)
                    .padding(10)
                    .background(Color.white.opacity(0.04))
                    .clipShape(Circle())
            }
            
            // Search / URL Input Box
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.gray)
                    .padding(.leading, 8)
                
                TextField("Search or enter web address", text: $urlInput, onCommit: {
                    var finalUrlStr = urlInput
                    if !finalUrlStr.hasPrefix("http://") && !finalUrlStr.hasPrefix("https://") {
                        if finalUrlStr.contains(".") && !finalUrlStr.contains(" ") {
                            finalUrlStr = "https://" + finalUrlStr
                        } else {
                            // Run Google Search
                            let query = finalUrlStr.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
                            finalUrlStr = "https://www.google.com/search?q=" + query
                        }
                    }
                    if let finalUrl = URL(string: finalUrlStr) {
                        state.activeTab?.url = finalUrl
                        state.activeTab?.title = "Loading..."
                    }
                })
                .font(.system(size: 14))
                .foregroundColor(.white)
                .keyboardType(.URL)
                .autocapitalization(.none)
                .disableAutocorrection(true)
                
                if let activeTab = state.activeTab, activeTab.isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .cyan))
                        .padding(.trailing, 8)
                }
            }
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.06)))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )
            
            // Settings trigger button
            Button(action: { showSettings = true }) {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 18))
                    .foregroundColor(.cyan)
                    .padding(10)
                    .background(Color.white.opacity(0.04))
                    .clipShape(Circle())
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(
            Color.black.opacity(0.2)
                .background(.ultraThinMaterial)
        )
    }
    
    // MARK: - Bottom toolbar view
    private var bottomToolbar: some View {
        HStack {
            // Back navigation
            Button(action: {
                // Natively back navigate
                NotificationCenter.default.post(name: Notification.Name("GraspWebBack"), object: nil)
            }) {
                Image(systemName: "chevron.left")
                    .foregroundColor((state.activeTab?.canGoBack ?? false) ? .white : .gray)
            }
            .disabled(!(state.activeTab?.canGoBack ?? false))
            
            Spacer()
            
            // Forward navigation
            Button(action: {
                NotificationCenter.default.post(name: Notification.Name("GraspWebForward"), object: nil)
            }) {
                Image(systemName: "chevron.right")
                    .foregroundColor((state.activeTab?.canGoForward ?? false) ? .white : .gray)
            }
            .disabled(!(state.activeTab?.canGoForward ?? false))
            
            Spacer()
            
            // Tab Switcher trigger with badge count
            Button(action: {
                withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) {
                    showTabsGrid = true
                }
            }) {
                ZStack {
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.cyan, lineWidth: 2)
                        .frame(width: 22, height: 22)
                    
                    Text("\(state.tabs.count)")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.cyan)
                }
            }
            
            Spacer()
            
            // Bookmark active webpage
            Button(action: {
                if let urlStr = state.activeTab?.url?.absoluteString {
                    if state.bookmarks.contains(urlStr) {
                        state.removeBookmark(url: urlStr)
                    } else {
                        state.addBookmark(url: urlStr)
                    }
                }
            }) {
                let isBookmarked = state.activeTab?.url != nil && state.bookmarks.contains(state.activeTab?.url?.absoluteString ?? "")
                Image(systemName: isBookmarked ? "bookmark.fill" : "bookmark")
                    .foregroundColor(isBookmarked ? .yellow : .white)
            }
            
            Spacer()
            
            // Download Manager sheet opener
            Button(action: { showDownloads = true }) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: "arrow.down.circle")
                        .font(.title3)
                        .foregroundColor(.white)
                    
                    // Show a notification badge if active downloads
                    if !downloadManager.activeTasks.isEmpty {
                        Circle()
                            .fill(Color.cyan)
                            .frame(width: 8, height: 8)
                            .shadow(color: .cyan, radius: 2)
                    }
                }
            }
        }
        .padding(.horizontal, 30)
        .padding(.top, 12)
        .padding(.bottom, 22)
        .background(
            Color.black.opacity(0.3)
                .background(.ultraThinMaterial)
        )
    }
    
    // MARK: - IDM Floating Stream Grabber
    private var floatingMediaGrabberBar: some View {
        Button(action: { showMediaGrabberList = true }) {
            HStack(spacing: 12) {
                Image(systemName: "video.fill")
                    .foregroundColor(.black)
                    .font(.system(size: 16, weight: .bold))
                    .padding(8)
                    .background(Color.cyan)
                    .clipShape(Circle())
                    .shadow(color: .cyan.opacity(0.6), radius: 4)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Media Captured")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.white)
                    Text("Grab media streams (\(state.capturedMedia.count))")
                        .font(.system(size: 10))
                        .foregroundColor(.cyan)
                }
                
                Image(systemName: "chevron.up")
                    .foregroundColor(.gray)
                    .font(.caption)
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 16)
            .background(
                Capsule()
                    .fill(Color(red: 0.1, green: 0.1, blue: 0.15).opacity(0.85))
                    .shadow(color: Color.black.opacity(0.5), radius: 10, y: 5)
            )
            .overlay(
                Capsule()
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .animation(.spring(), value: state.capturedMedia.isEmpty)
    }
    
    // MARK: - Safari Tab Cards Manager
    private var tabsManagerGrid: some View {
        ZStack {
            Color.black.opacity(0.7)
                .ignoresSafeArea()
                .onTapGesture {
                    withAnimation(.spring()) {
                        showTabsGrid = false
                    }
                }
            
            VStack(spacing: 16) {
                Text("Browser Tabs")
                    .font(.headline)
                    .bold()
                    .foregroundColor(.white)
                    .padding(.top, 20)
                
                ScrollView {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)], spacing: 14) {
                        ForEach(state.tabs.indices, id: \.self) { index in
                            let tab = state.tabs[index]
                            let isActive = index == state.activeTabIndex
                            
                            VStack(alignment: .leading) {
                                // Header card
                                HStack {
                                    Text(tab.title)
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundColor(.white)
                                        .lineLimit(1)
                                    Spacer()
                                    Button(action: { state.closeTab(at: index) }) {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundColor(.gray.opacity(0.8))
                                    }
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 8)
                                .background(Color.white.opacity(0.05))
                                
                                // Thumb representation
                                Spacer()
                                HStack {
                                    Spacer()
                                    Image(systemName: "globe")
                                        .font(.system(size: 30))
                                        .foregroundColor(.cyan.opacity(0.3))
                                    Spacer()
                                }
                                Spacer()
                            }
                            .frame(height: 140)
                            .background(Color(red: 0.1, green: 0.1, blue: 0.15))
                            .cornerRadius(14)
                            .overlay(
                                RoundedRectangle(cornerRadius: 14)
                                    .stroke(isActive ? Color.cyan : Color.white.opacity(0.08), lineWidth: isActive ? 2.5 : 1)
                            )
                            .shadow(color: isActive ? Color.cyan.opacity(0.3) : Color.black.opacity(0.3), radius: 8)
                            .onTapGesture {
                                state.activeTabIndex = index
                                withAnimation(.spring()) {
                                    showTabsGrid = false
                                }
                            }
                        }
                    }
                    .padding(.horizontal)
                }
                
                // Footer toolbar additions
                HStack {
                    Spacer()
                    Button(action: {
                        state.addTab()
                        withAnimation(.spring()) {
                            showTabsGrid = false
                        }
                    }) {
                        HStack(spacing: 8) {
                            Image(systemName: "plus")
                            Text("New Tab")
                                .bold()
                        }
                        .foregroundColor(.black)
                        .padding(.vertical, 12)
                        .padding(.horizontal, 24)
                        .background(Color.cyan)
                        .cornerRadius(20)
                        .shadow(color: .cyan.opacity(0.4), radius: 6)
                    }
                    Spacer()
                }
                .padding(.bottom, 30)
            }
        }
        .transition(.scale.combined(with: .opacity))
    }
    
    // MARK: - Dynamic IDM style Download Popup
    private var downloadPromptOverlay: some View {
        ZStack {
            Color.black.opacity(0.6)
                .ignoresSafeArea()
                .onTapGesture {
                    withAnimation(.spring()) {
                        showLongPressPrompt = false
                    }
                }
            
            VStack(spacing: 18) {
                HStack {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.title2)
                        .foregroundColor(.cyan)
                    Text("Internet Download Manager")
                        .font(.headline)
                        .foregroundColor(.white)
                    Spacer()
                }
                
                VStack(alignment: .leading, spacing: 6) {
                    Text("File Name")
                        .font(.caption2)
                        .foregroundColor(.gray)
                    TextField("custom_video_name.mp4", text: $customDownloadName)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .foregroundColor(.white)
                }
                
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Allocate Threads")
                            .font(.caption2)
                            .foregroundColor(.gray)
                        Spacer()
                        Text("\(Int(customThreadCount)) Parts")
                            .font(.caption2)
                            .bold()
                            .foregroundColor(.cyan)
                    }
                    Slider(value: $customThreadCount, in: 2...32, step: 1)
                }
                
                HStack(spacing: 12) {
                    Button(action: {
                        withAnimation(.spring()) {
                            showLongPressPrompt = false
                        }
                    }) {
                        Text("Cancel")
                            .bold()
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .foregroundColor(.white)
                            .background(Color.white.opacity(0.08))
                            .cornerRadius(12)
                    }
                    
                    Button(action: {
                        if let url = promptUrl {
                            downloadManager.startDownload(
                                url: url,
                                customFileName: customDownloadName,
                                threadCount: Int(customThreadCount)
                            )
                        }
                        withAnimation(.spring()) {
                            showLongPressPrompt = false
                        }
                    }) {
                        Text("Start Download")
                            .bold()
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .foregroundColor(.black)
                            .background(Color.cyan)
                            .cornerRadius(12)
                            .shadow(color: .cyan.opacity(0.4), radius: 6)
                    }
                }
            }
            .padding(22)
            .background(Color(red: 0.12, green: 0.12, blue: 0.18))
            .cornerRadius(20)
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )
            .padding(.horizontal, 30)
            .shadow(color: Color.black.opacity(0.8), radius: 30)
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}

// MARK: - Custom List view of Captured Media streams
struct MediaGrabberListView: View {
    @EnvironmentObject var state: BrowserState
    @Environment(\.presentationMode) var presentationMode
    
    let onDownload: (CapturedMedia, Int) -> Void
    @State private var downloadThreads = 8.0
    
    var body: some View {
        NavigationView {
            ZStack {
                Color(red: 0.05, green: 0.05, blue: 0.08)
                    .ignoresSafeArea()
                
                VStack {
                    // Quick Options Thread allocation
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Default Speed Threads")
                                .font(.caption)
                                .foregroundColor(.gray)
                            Spacer()
                            Text("\(Int(downloadThreads)) concurrent segments")
                                .font(.caption)
                                .bold()
                                .foregroundColor(.cyan)
                        }
                        Slider(value: $downloadThreads, in: 2...32, step: 1)
                    }
                    .padding()
                    .background(Color.white.opacity(0.03))
                    .cornerRadius(12)
                    .padding()
                    
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(Array(state.capturedMedia), id: \.self) { media in
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(media.title)
                                            .font(.system(size: 14, weight: .semibold))
                                            .foregroundColor(.white)
                                            .lineLimit(1)
                                        Text(media.url.absoluteString)
                                            .font(.caption2)
                                            .foregroundColor(.gray)
                                            .lineLimit(1)
                                        
                                        Text(media.type)
                                            .font(.system(size: 10))
                                            .bold()
                                            .foregroundColor(.cyan)
                                    }
                                    Spacer()
                                    
                                    Button(action: {
                                        onDownload(media, Int(downloadThreads))
                                    }) {
                                        Text("Download")
                                            .font(.system(size: 12, weight: .bold))
                                            .foregroundColor(.black)
                                            .padding(.horizontal, 14)
                                            .padding(.vertical, 8)
                                            .background(Color.cyan)
                                            .cornerRadius(8)
                                    }
                                }
                                .padding(12)
                                .background(Color.white.opacity(0.04))
                                .cornerRadius(12)
                            }
                        }
                        .padding(.horizontal)
                    }
                }
            }
            .navigationTitle("Captured Media Streams")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(
                leading: Button("Clear All") {
                    state.clearCapturedMedia()
                    presentationMode.wrappedValue.dismiss()
                }.foregroundColor(.red),
                trailing: Button("Cancel") {
                    presentationMode.wrappedValue.dismiss()
                }.foregroundColor(.cyan)
            )
        }
        .preferredColorScheme(.dark)
    }
}
