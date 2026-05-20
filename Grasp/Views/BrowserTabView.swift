import SwiftUI

struct BrowserTabView: View {
    @ObservedObject var tab: BrowserTab
    @EnvironmentObject var state: BrowserState
    
    var body: some View {
        ZStack(alignment: .top) {
            // Main Web Content
            WebView(tab: tab)
                .ignoresSafeArea(edges: .bottom)
            
            // Premium Floating Loading Progress Bar
            if tab.isLoading {
                GeometryReader { geometry in
                    VStack {
                        ZStack(alignment: .leading) {
                            Rectangle()
                                .foregroundColor(Color.white.opacity(0.1))
                                .frame(height: 3)
                            
                            Rectangle()
                                .foregroundColor(Color.cyan) // Premium accent color
                                .frame(width: geometry.size.width * CGFloat(tab.estimatedProgress), height: 3)
                                .shadow(color: Color.cyan.opacity(0.8), radius: 3, x: 0, y: 0)
                                .animation(.linear(duration: 0.15), value: tab.estimatedProgress)
                        }
                        Spacer()
                    }
                }
                .frame(height: 3)
                .transition(.opacity)
            }
        }
        .background(Color.black)
    }
}
