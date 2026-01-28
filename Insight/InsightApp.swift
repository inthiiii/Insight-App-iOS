import SwiftUI
import SwiftData

@main
struct InsightApp: App {
    // Lazy Container
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            InsightItem.self,
            InsightLink.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            print("CRITICAL ERROR: Could not create ModelContainer: \(error)")
            fatalError("Database initialization failed.")
        }
    }()
    
    @State private var isLaunching = true
    @State private var pulse = false

    var body: some Scene {
        WindowGroup {
            ZStack {
                if isLaunching {
                    // --- LOADING SCREEN ---
                    ZStack {
                        Color(hex: "0f172a").ignoresSafeArea()
                        
                        ZStack {
                            Circle()
                                .fill(Color.blue.opacity(0.3))
                                .frame(width: 120, height: 120)
                                .blur(radius: 20)
                                .scaleEffect(pulse ? 1.5 : 0.8)
                                .opacity(pulse ? 0.8 : 0.4)
                            
                            Circle()
                                .fill(LinearGradient(colors: [.white, .blue.opacity(0.5)], startPoint: .topLeading, endPoint: .bottomTrailing))
                                .frame(width: 50, height: 50)
                                .shadow(color: .blue, radius: 10)
                        }
                        
                        Text("Insight")
                            .font(.system(size: 24, weight: .light, design: .serif))
                            .foregroundStyle(.white.opacity(0.8))
                            .offset(y: 100)
                    }
                    .onAppear {
                        withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) { pulse = true }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                            withAnimation(.easeOut(duration: 0.5)) { isLaunching = false }
                        }
                    }
                } else {
                    // --- MAIN APP ---
                    ContentView()
                }
            }
        }
        .modelContainer(sharedModelContainer)
    }
}
