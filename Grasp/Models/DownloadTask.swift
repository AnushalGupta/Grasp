import Foundation

class DownloadTask: Identifiable, ObservableObject {
    enum Status: String, Codable {
        case pending = "Pending"
        case connecting = "Connecting"
        case downloading = "Downloading"
        case paused = "Paused"
        case merging = "Assembling Parts"
        case completed = "Completed"
        case failed = "Failed"
    }
    
    struct ThreadInfo: Identifiable, Codable {
        let id: Int
        let startByte: Int64
        let endByte: Int64
        var downloadedBytes: Int64
        var isCompleted: Bool
        var error: String?
        
        var progress: Double {
            let total = Double(endByte - startByte + 1)
            guard total > 0 else { return 0.0 }
            return Double(downloadedBytes) / total
        }
    }
    
    let id: UUID
    let url: URL
    @Published var fileName: String
    @Published var totalBytes: Int64 = 0
    @Published var downloadedBytes: Int64 = 0
    @Published var speedBytesPerSecond: Double = 0.0
    @Published var etaInterval: TimeInterval? = nil
    @Published var status: Status = .pending
    @Published var threadCount: Int = 8
    @Published var threads: [ThreadInfo] = []
    @Published var errorMessage: String? = nil
    @Published var progress: Double = 0.0
    
    // User Tunable Settings for "God-Tier" downloads
    var customUserAgent: String? = nil
    var bufferSize: Int = 1024 * 64 // 64KB default buffer
    var maxRetryAttempts: Int = 3
    var retryCount: Int = 0
    
    // Track timing for speed calculation
    var lastCalcTime: Date = Date()
    var lastCalcBytes: Int64 = 0
    private var speedRollingWindow: [Double] = []
    
    init(url: URL, fileName: String, threadCount: Int = 8) {
        self.id = UUID()
        self.url = url
        self.fileName = fileName
        self.threadCount = threadCount
    }
    
    func updateProgress() {
        if status == .completed {
            self.progress = 1.0
            return
        }
        
        if totalBytes > 0 {
            self.progress = Double(downloadedBytes) / Double(totalBytes)
        } else {
            self.progress = 0.0
        }
    }
    
    /// Calculate current throughput and rolling ETA
    func calculateMetrics(currentDownloadedBytes: Int64) {
        let now = Date()
        let elapsed = now.timeIntervalSince(lastCalcTime)
        
        // Update metrics every 0.5s or more to avoid extreme fluctuations
        if elapsed >= 0.5 {
            let bytesDownloadedInInterval = currentDownloadedBytes - lastCalcBytes
            let currentSpeed = Double(bytesDownloadedInInterval) / elapsed
            
            // Add to rolling window of size 5
            speedRollingWindow.append(currentSpeed)
            if speedRollingWindow.count > 5 {
                speedRollingWindow.removeFirst()
            }
            
            // Smooth speed using average
            let avgSpeed = speedRollingWindow.reduce(0, +) / Double(speedRollingWindow.count)
            
            DispatchQueue.main.async {
                self.downloadedBytes = currentDownloadedBytes
                self.speedBytesPerSecond = avgSpeed
                
                if self.totalBytes > 0 && avgSpeed > 0 {
                    let remainingBytes = self.totalBytes - currentDownloadedBytes
                    self.etaInterval = TimeInterval(Double(remainingBytes) / avgSpeed)
                } else {
                    self.etaInterval = nil
                }
                
                self.updateProgress()
            }
            
            lastCalcTime = now
            lastCalcBytes = currentDownloadedBytes
        }
    }
}
