import SwiftUI
import AVKit

struct DownloadsListView: View {
    @EnvironmentObject var state: BrowserState
    @EnvironmentObject var downloadManager: DownloadManager
    @Environment(\.presentationMode) var presentationMode
    
    @State private var selectedSegment = 0 // 0: Active, 1: Completed
    @State private var activePlayerUrl: URL? = nil
    
    var body: some View {
        NavigationView {
            ZStack {
                // Sleek Premium Dark Background
                LinearGradient(gradient: Gradient(colors: [Color(red: 0.05, green: 0.05, blue: 0.08), Color(red: 0.1, green: 0.08, blue: 0.15)]), startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea()
                
                VStack(spacing: 16) {
                    // Segment Picker (Active vs Completed)
                    Picker("", selection: $selectedSegment) {
                        Text("Active (\(downloadManager.activeTasks.count))").tag(0)
                        Text("Completed (\(downloadManager.completedFiles.count))").tag(1)
                    }
                    .pickerStyle(SegmentedPickerStyle())
                    .padding(.horizontal)
                    .accentColor(.cyan)
                    
                    if selectedSegment == 0 {
                        // Active Tasks View
                        activeTasksList
                    } else {
                        // Completed Files View
                        completedFilesList
                    }
                }
                .padding(.top, 10)
            }
            .navigationTitle("Download Manager")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(trailing: Button(action: {
                presentationMode.wrappedValue.dismiss()
            }) {
                Text("Done")
                    .bold()
                    .foregroundColor(.cyan)
            })
            // Video Player Sheet
            .sheet(item: $activePlayerUrl) { url in
                VideoPlayerView(url: url)
            }
        }
        .preferredColorScheme(.dark)
    }
    
    // MARK: - Active Tasks Section
    private var activeTasksList: some View {
        Group {
            if downloadManager.activeTasks.isEmpty {
                VStack(spacing: 15) {
                    Image(systemName: "arrow.down.circle")
                        .font(.system(size: 60))
                        .foregroundColor(.gray)
                    Text("No active downloads")
                        .font(.headline)
                        .foregroundColor(.gray)
                    Text("Media links captured from websites will show up here.")
                        .font(.subheadline)
                        .foregroundColor(.gray.opacity(0.7))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                }
                .frame(maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(downloadManager.activeTasks) { task in
                            ActiveTaskRow(task: task)
                        }
                    }
                    .padding()
                }
            }
        }
    }
    
    // MARK: - Completed Files Section
    private var completedFilesList: some View {
        Group {
            if downloadManager.completedFiles.isEmpty {
                VStack(spacing: 15) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 60))
                        .foregroundColor(.gray.opacity(0.5))
                    Text("No completed downloads")
                        .font(.headline)
                        .foregroundColor(.gray)
                }
                .frame(maxHeight: .infinity)
            } else {
                List {
                    ForEach(downloadManager.completedFiles, id: \.self) { fileUrl in
                        CompletedFileRow(fileUrl: fileUrl, onPlay: {
                            self.activePlayerUrl = fileUrl
                        }, onDelete: {
                            downloadManager.deleteCompletedFile(at: fileUrl)
                        })
                        .listRowBackground(Color.white.opacity(0.03))
                    }
                }
                .listStyle(PlainListStyle())
            }
        }
    }
}

// MARK: - Active Task Row Component
struct ActiveTaskRow: View {
    @ObservedObject var task: DownloadTask
    @EnvironmentObject var downloadManager: DownloadManager
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header Info
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(task.fileName)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                    
                    HStack(spacing: 12) {
                        Text(task.status.rawValue)
                            .font(.caption)
                            .bold()
                            .foregroundColor(statusColor)
                        
                        Text("\(task.threadCount) Threads")
                            .font(.caption2)
                            .foregroundColor(.gray)
                    }
                }
                Spacer()
                
                // Action Buttons
                HStack(spacing: 12) {
                    if task.status == .downloading {
                        Button(action: { downloadManager.pauseDownload(task: task) }) {
                            Image(systemName: "pause.fill")
                                .foregroundColor(.orange)
                                .padding(8)
                                .background(Color.orange.opacity(0.15))
                                .clipShape(Circle())
                        }
                    } else if task.status == .paused {
                        Button(action: { downloadManager.resumeDownload(task: task) }) {
                            Image(systemName: "play.fill")
                                .foregroundColor(.green)
                                .padding(8)
                                .background(Color.green.opacity(0.15))
                                .clipShape(Circle())
                        }
                    }
                    
                    Button(action: { downloadManager.cancelDownload(task: task) }) {
                        Image(systemName: "xmark")
                            .foregroundColor(.red)
                            .padding(8)
                            .background(Color.red.opacity(0.15))
                            .clipShape(Circle())
                    }
                }
            }
            
            // Progress Bar
            ZStack(alignment: .leading) {
                Rectangle()
                    .foregroundColor(Color.white.opacity(0.1))
                    .frame(height: 6)
                    .cornerRadius(3)
                
                Rectangle()
                    .foregroundColor(Color.cyan)
                    .frame(width: max(0, min(CGFloat(task.progress) * 280, 280)), height: 6) // Dynamic bounds
                    .cornerRadius(3)
                    .shadow(color: Color.cyan.opacity(0.5), radius: 3, x: 0, y: 0)
            }
            
            // Stats Footer
            HStack {
                let sizeStr = formatBytes(task.totalBytes)
                let downloadedStr = formatBytes(task.downloadedBytes)
                Text("\(downloadedStr) of \(sizeStr)")
                    .font(.caption2)
                    .foregroundColor(.gray)
                
                Spacer()
                
                if task.status == .downloading {
                    HStack(spacing: 8) {
                        Text(formatSpeed(task.speedBytesPerSecond))
                            .font(.caption2)
                            .bold()
                            .foregroundColor(.cyan)
                        
                        if let eta = task.etaInterval {
                            Text(formatETA(eta))
                                .font(.caption2)
                                .foregroundColor(.gray)
                        }
                    }
                }
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.04)))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
        )
    }
    
    private var statusColor: Color {
        switch task.status {
        case .pending, .connecting: return .gray
        case .downloading: return .cyan
        case .paused: return .orange
        case .merging: return .purple
        case .completed: return .green
        case .failed: return .red
        }
    }
    
    private func formatBytes(_ bytes: Int64) -> String {
        guard bytes > 0 else { return "Unknown Size" }
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB, .useKB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
    
    private func formatSpeed(_ speed: Double) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useKB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(speed)) + "/s"
    }
    
    private func formatETA(_ seconds: TimeInterval) -> String {
        if seconds < 60 {
            return String(format: "%.0fs left", seconds)
        } else {
            let mins = Int(seconds) / 60
            let secs = Int(seconds) % 60
            return String(format: "%dm %ds left", mins, secs)
        }
    }
}

// MARK: - Completed File Row Component
struct CompletedFileRow: View {
    let fileUrl: URL
    let onPlay: () -> Void
    let onDelete: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: fileIcon)
                .font(.title2)
                .foregroundColor(fileColor)
                .padding(10)
                .background(fileColor.opacity(0.12))
                .cornerRadius(10)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(fileUrl.lastPathComponent)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white)
                    .lineLimit(1)
                
                Text(fileSize)
                    .font(.caption2)
                    .foregroundColor(.gray)
            }
            
            Spacer()
            
            HStack(spacing: 16) {
                if isVideo {
                    Button(action: onPlay) {
                        Image(systemName: "play.circle.fill")
                            .font(.title2)
                            .foregroundColor(.cyan)
                    }
                }
                
                // Share Sheet opener
                Button(action: shareFile) {
                    Image(systemName: "square.and.arrow.up")
                        .foregroundColor(.gray)
                }
                
                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .foregroundColor(.red.opacity(0.8))
                }
            }
        }
        .padding(.vertical, 4)
    }
    
    private var isVideo: Bool {
        let ext = fileUrl.pathExtension.lowercased()
        return ["mp4", "m4v", "mov", "mkv", "webm"].contains(ext)
    }
    
    private var fileIcon: String {
        let ext = fileUrl.pathExtension.lowercased()
        if ["mp4", "m4v", "mov", "mkv"].contains(ext) { return "video" }
        if ["mp3", "wav", "m4a", "aac"].contains(ext) { return "music.note" }
        if ["png", "jpg", "jpeg", "gif"].contains(ext) { return "photo" }
        if ["pdf"].contains(ext) { return "doc.richtext" }
        if ["zip", "rar", "tar"].contains(ext) { return "doc.zipp" }
        return "doc"
    }
    
    private var fileColor: Color {
        let ext = fileUrl.pathExtension.lowercased()
        if ["mp4", "m4v", "mov", "mkv"].contains(ext) { return .cyan }
        if ["mp3", "wav", "m4a", "aac"].contains(ext) { return .pink }
        if ["png", "jpg", "jpeg", "gif"].contains(ext) { return .purple }
        return .green
    }
    
    private var fileSize: String {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: fileUrl.path),
              let size = attrs[.size] as? Int64 else {
            return "Unknown Size"
        }
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useKB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: size)
    }
    
    private func shareFile() {
        let av = UIActivityViewController(activityItems: [fileUrl], applicationActivities: nil)
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootVC = windowScene.windows.first?.rootViewController {
            rootVC.present(av, animated: true, completion: nil)
        }
    }
}

// MARK: - Native Video Player Wrapper Sheet
struct VideoPlayerView: View {
    let url: URL
    @Environment(\.presentationMode) var presentationMode
    
    var body: some View {
        ZStack(alignment: .topLeading) {
            VideoPlayer(player: AVPlayer(url: url))
                .ignoresSafeArea()
            
            Button(action: {
                presentationMode.wrappedValue.dismiss()
            }) {
                Image(systemName: "xmark")
                    .font(.headline)
                    .foregroundColor(.white)
                    .padding()
                    .background(Color.black.opacity(0.6))
                    .clipShape(Circle())
            }
            .padding()
        }
    }
}

// Identifiable URL extension to present in sheet
extension URL: Identifiable {
    public var id: String { self.absoluteString }
}
