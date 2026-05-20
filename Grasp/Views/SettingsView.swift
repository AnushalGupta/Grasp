import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var state: BrowserState
    @EnvironmentObject var downloadManager: DownloadManager
    @ObservedObject var adblockManager = AdBlockerManager.shared
    @Environment(\.presentationMode) var presentationMode
    
    @State private var tempUserAgent: String = ""
    @State private var tempDNSUrl: String = ""
    @State private var customFilterUrl: String = ""
    @State private var showsAlert = false
    @State private var alertMessage = ""
    
    let bufferSizes = [16384: "16 KB", 32768: "32 KB", 65536: "64 KB", 131072: "128 KB", 262144: "258 KB"]
    
    var body: some View {
        NavigationView {
            Form {
                // MARK: - Adblocking Section
                Section(header: Text("Shield & Adblocking")) {
                    Toggle("Adblock Engine", isOn: $state.adblockEnabled)
                        .onChange(of: state.adblockEnabled) { value in
                            if value {
                                adblockManager.loadExistingRuleList()
                            } else {
                                adblockManager.clearAllRules()
                            }
                        }
                    
                    if state.adblockEnabled {
                        HStack {
                            Text("Engine Status")
                            Spacer()
                            if adblockManager.isCompiling {
                                HStack(spacing: 8) {
                                    ProgressView()
                                    Text("Compiling...")
                                        .foregroundColor(.gray)
                                }
                            } else if adblockManager.activeRuleList != nil {
                                Text("Active & Protected")
                                    .foregroundColor(.green)
                                    .bold()
                            } else {
                                Text("Idle / Compiling Default")
                                    .foregroundColor(.orange)
                            }
                        }
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Add Custom Filter URL")
                                .font(.caption)
                                .foregroundColor(.gray)
                            
                            HStack {
                                TextField("https://example.com/easylist.txt", text: $customFilterUrl)
                                    .textFieldStyle(RoundedBorderTextFieldStyle())
                                    .autocapitalization(.none)
                                    .disableAutocorrection(true)
                                
                                Button(action: fetchAndCompileCustomList) {
                                    Text("Compile")
                                        .bold()
                                        .foregroundColor(.cyan)
                                }
                                .disabled(customFilterUrl.isEmpty || adblockManager.isCompiling)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
                
                // MARK: - Downloader Segment
                Section(header: Text("God-Tier Downloader Controls")) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Default Threads")
                            Spacer()
                            Text("\\(state.threadCountSetting) Threads")
                                .bold()
                                .foregroundColor(.cyan)
                        }
                        Slider(value: Binding(
                            get: { Double(state.threadCountSetting) },
                            set: { state.threadCountSetting = Int($0) }
                        ), in: 2...32, step: 1)
                        Text("Splits files into concurrent parts. Higher count is faster but depends on server capacity.")
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                    .padding(.vertical, 4)
                    
                    Picker("Downloader Buffer", selection: Binding(
                        get: { downloadManager.bufferSizeSetting },
                        set: { downloadManager.bufferSizeSetting = $0 }
                    )) {
                        ForEach(bufferSizes.sorted(by: { $0.key < $1.key }), id: \\.key) { key, value in
                            Text(value).tag(key)
                        }
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Custom Downloader User Agent")
                            .font(.caption)
                            .foregroundColor(.gray)
                        TextField("User Agent", text: $tempUserAgent)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .onChange(of: tempUserAgent) { newValue in
                                downloadManager.userAgent = newValue
                            }
                    }
                    .padding(.vertical, 4)
                    
                    Toggle("Auto-Grab Playlists & Media", isOn: $state.autoGrabMedia)
                    Toggle("Long-Press Video Menu", isOn: $state.longPressGestureEnabled)
                }
                
                // MARK: - Advanced Networking Section
                Section(header: Text("Custom DNS Configurations")) {
                    Picker("DNS Resolution", selection: $state.selectedDNSProvider) {
                        ForEach(state.dnsProviders, id: \\.self) { provider in
                            Text(provider).tag(provider)
                        }
                    }
                    
                    if state.selectedDNSProvider != "Default" {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Custom DNS Endpoint (DoH URL)")
                                .font(.caption)
                                .foregroundColor(.gray)
                            TextField("https://dns.nextdns.io/xxxxxx", text: $tempDNSUrl)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                                .autocapitalization(.none)
                                .disableAutocorrection(true)
                                .onChange(of: tempDNSUrl) { newValue in
                                    state.customDNS = newValue
                                }
                        }
                        .padding(.vertical, 4)
                    }
                }
                
                // MARK: - Browser Cache & Clear Data
                Section(header: Text("Data Privacy")) {
                    Button(action: {
                        state.clearHistory()
                        WKWebsiteDataStore.default().removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: Date(timeIntervalSince1970: 0)) {
                            DispatchQueue.main.async {
                                alertMessage = "Browser history, caches, and web storage have been cleared."
                                showsAlert = true
                            }
                        }
                    }) {
                        Text("Clear Browsing History & Cache")
                            .foregroundColor(.red)
                    }
                }
            }
            .navigationTitle("Advanced Settings")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(trailing: Button("Done") {
                presentationMode.wrappedValue.dismiss()
            }.foregroundColor(.cyan))
            .onAppear {
                tempUserAgent = downloadManager.userAgent
                tempDNSUrl = state.customDNS
            }
            .alert(isPresented: $showsAlert) {
                Alert(title: Text("System Notification"), message: Text(alertMessage), dismissButton: .default(Text("OK")))
            }
        }
        .preferredColorScheme(.dark)
    }
    
    /// Fetches a custom remote EasyList file and compiles it
    private func fetchAndCompileCustomList() {
        guard let url = URL(string: customFilterUrl) else { return }
        
        adblockManager.isCompiling = true
        
        let session = URLSession(configuration: .ephemeral)
        session.dataTask(with: url) { data, response, error in
            if let error = error {
                DispatchQueue.main.async {
                    adblockManager.isCompiling = false
                    alertMessage = "Failed to fetch filters: \\(error.localizedDescription)"
                    showsAlert = true
                }
                return
            }
            
            guard let data = data, let text = String(data: data, encoding: .utf8) else {
                DispatchQueue.main.async {
                    adblockManager.isCompiling = false
                    alertMessage = "Filter response data is invalid."
                    showsAlert = true
                }
                return
            }
            
            adblockManager.compile(filterRulesText: text) { success in
                DispatchQueue.main.async {
                    if success {
                        alertMessage = "Custom filter list successfully compiled and applied!"
                    } else {
                        alertMessage = "Compilation failed. Ensure the format matches Adblock Plus/EasyList guidelines."
                    }
                    showsAlert = true
                }
            }
        }.resume()
    }
}
