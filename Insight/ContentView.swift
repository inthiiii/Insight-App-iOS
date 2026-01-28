import SwiftUI
import SwiftData
import CoreLocation

// Enum for Tab Management
enum AppTab {
    case home
    case library
    case neural
    case ara
}

struct ContentView: View {
    @State private var currentTab: AppTab = .home
    @State private var isKeyboardVisible = false
    
    var body: some View {
        NavigationStack {
            ZStack {
                FluidBackground() // Your background component
                
                // --- MAIN CONTENT SWITCHER ---
                VStack(spacing: 0) {
                    switch currentTab {
                    case .home:
                        HomeView().transition(.opacity)
                    case .ara:
                        AraChatView().transition(.opacity)
                    case .library:
                        LibraryView().transition(.opacity)
                    case .neural:
                        NeuralWebView().transition(.opacity)
                    }
                    
                    // Spacer ensures content doesn't get hidden behind the dock
                    Spacer(minLength: 0)
                }
                .padding(.bottom, isKeyboardVisible ? 0 : 90) // Dynamic space for dock
                
                // --- THE LIQUID DOCK ---
                if !isKeyboardVisible {
                    VStack {
                        Spacer()
                        LiquidDock(selectedTab: $currentTab)
                            .padding(.bottom, 10)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
            }
            // Keyboard listeners
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
                withAnimation { isKeyboardVisible = true }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
                withAnimation { isKeyboardVisible = false }
            }
        }
    }
}

// --- SUBVIEW: THE HOME DASHBOARD ---
struct HomeView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \InsightItem.dateCreated, order: .reverse) private var items: [InsightItem]
    
    @State private var locationManager = LocationManager.shared
    @State private var audioManager = AudioManager()
    @State private var showCamera = false
    @State private var capturedImage: UIImage?
    @State private var isProcessingImage = false
    @State private var showDocPicker = false
    @State private var pdfText = ""
    @State private var pdfName = ""
    
    @State private var showTextInput = false
    @State private var manualText = ""
    @State private var showLatestInsight = true
    
    var body: some View {
        VStack(spacing: 30) {
            
            // HEADER
            HStack {
                VStack(alignment: .leading) {
                    Text("Insight").font(.system(size: 40, weight: .bold, design: .serif)).foregroundStyle(.white)
                    Text(items.isEmpty ? "Weave your knowledge." : "\(items.count) Memories Stored")
                        .font(.subheadline).foregroundStyle(.white.opacity(0.7))
                }
                Spacer()
                NavigationLink(destination: RealityView()) {
                    Image(systemName: "eye.fill").font(.title2).frame(width: 50, height: 50).foregroundStyle(.white).background(.blue.opacity(0.6)).clipShape(Circle()).shadow(color: .blue.opacity(0.5), radius: 10)
                }.simultaneousGesture(TapGesture().onEnded { UIImpactFeedbackGenerator(style: .light).impactOccurred() })
                
                NavigationLink(destination: OracleView()) {
                    Image(systemName: "magnifyingglass").font(.title2).frame(width: 50, height: 50).foregroundStyle(.white).background(.blue.opacity(0.6)).clipShape(Circle()).shadow(color: .blue.opacity(0.5), radius: 10)
                }.simultaneousGesture(TapGesture().onEnded { UIImpactFeedbackGenerator(style: .light).impactOccurred() })
            }.padding(.top, 20).padding(.horizontal)
            
            Spacer()
            
            // WIDGET
            VStack {
                if isProcessingImage {
                    ProgressView().tint(.white).scaleEffect(1.5).padding()
                    Text("Reading Vision...").foregroundStyle(.white)
                } else if audioManager.isRecording {
                    Image(systemName: "waveform").symbolEffect(.variableColor.iterative.reversing).font(.system(size: 60)).foregroundStyle(.red.opacity(0.8)).padding()
                    Text("Listening...").foregroundStyle(.white).font(.headline)
                    Text(audioManager.transcript).foregroundStyle(.white.opacity(0.8)).padding()
                } else if let latest = items.first, showLatestInsight {
                    ZStack(alignment: .topTrailing) {
                        // Content
                        VStack {
                            HStack { Text("Latest at"); Text(locationManager.currentLabel).bold().foregroundStyle(.blue) }
                                .font(.caption).foregroundStyle(.white.opacity(0.6)).padding(.top, 5)
                            
                            if latest.type == .image, let filename = latest.localFileName, let img = VisionManager.loadImageFromDisk(filename: filename) {
                                Image(uiImage: img).resizable().scaledToFit().frame(height: 120).cornerRadius(10).padding(.top)
                            } else {
                                Image(systemName: "quote.opening").font(.system(size: 40)).foregroundStyle(.white.opacity(0.8)).padding(.top)
                            }
                            
                            Text(latest.content.isEmpty ? "Image captured" : latest.content).font(.headline).foregroundStyle(.white).multilineTextAlignment(.center).padding().lineLimit(3)
                            
                            if let date = SmartActionManager.shared.detectDates(in: latest.content) {
                                Button(action: {
                                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                    SmartActionManager.shared.addEvent(title: latest.content, date: date) { success, _ in
                                        if success { let gen = UINotificationFeedbackGenerator(); gen.notificationOccurred(.success) }
                                    }
                                }) {
                                    HStack { Image(systemName: "calendar"); Text("Schedule: \(date.formatted(.dateTime.weekday().hour()))") }
                                        .font(.caption).padding(8).background(.blue.opacity(0.8)).foregroundStyle(.white).clipShape(Capsule())
                                }.padding(.top, 5)
                            }
                            
                            if let links = latest.outgoingLinks, !links.isEmpty {
                                VStack(spacing: 5) {
                                    Text("Connected to:").font(.caption2).textCase(.uppercase).foregroundStyle(.white.opacity(0.5))
                                    ForEach(links.prefix(2), id: \.targetID) { link in
                                        HStack {
                                            Image(systemName: "link").font(.caption).foregroundStyle(.blue.opacity(0.8))
                                            Text("Match (\(Int(link.strength * 100))%)").font(.caption).foregroundStyle(.white.opacity(0.8))
                                        }
                                        .padding(5).background(.white.opacity(0.1)).cornerRadius(5)
                                    }
                                }.padding(.bottom)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        
                        // Reset Button (Top Right Corner)
                        Button(action: {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            withAnimation { showLatestInsight = false }
                        }) {
                            Image(systemName: "arrow.counterclockwise")
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.6))
                                .padding(8)
                                .background(.black.opacity(0.3))
                                .clipShape(Circle())
                        }
                        .padding(8) // Padding from the edge of the card
                    }
                } else {
                    Image(systemName: "waveform.path.ecg").font(.system(size: 50)).foregroundStyle(.white.opacity(0.8)).padding()
                    Text("No Insights Yet").font(.headline).foregroundStyle(.white)
                    Text("Capture audio, text, or images.").font(.caption).foregroundStyle(.white.opacity(0.6))
                }
            }
            .frame(maxWidth: .infinity).frame(minHeight: 320)
            .padding(.vertical, 20).liquidGlass().padding(.horizontal)
            .shadow(color: .black.opacity(0.3), radius: 20, x: 0, y: 10)
            
            Spacer()
            
            // ACTIONS
            HStack(spacing: 20) {
                actionButton(icon: "pencil", action: { showTextInput = true })
                    .sheet(isPresented: $showTextInput) {
                        TextInputView(text: $manualText) {
                            saveInsight(text: manualText, type: .note)
                            manualText = ""
                        }
                    }
                
                Button(action: {
                    let impact = UIImpactFeedbackGenerator(style: .medium); impact.impactOccurred()
                    audioManager.toggleRecording { finalContext in
                        saveInsight(text: finalContext, type: .audio)
                    }
                }) {
                    Image(systemName: audioManager.isRecording ? "stop.fill" : "mic.fill").font(.title2).frame(width: 60, height: 60).foregroundStyle(.white).background(audioManager.isRecording ? .red.opacity(0.8) : .clear).clipShape(Circle()).liquidGlass(cornerRadius: 30)
                }
                
                actionButton(icon: "camera.fill", action: { showCamera = true })
                    .sheet(isPresented: $showCamera, onDismiss: processcapturedImage) {
                        CameraView(selectedImage: $capturedImage)
                    }
                
                actionButton(icon: "doc.text.fill", action: { showDocPicker = true })
                    .sheet(isPresented: $showDocPicker) {
                        DocumentPicker(fileContent: $pdfText, fileName: $pdfName) {
                            saveInsight(text: pdfText, type: .pdf, localFileName: pdfName)
                            pdfText = ""; pdfName = ""
                        }
                    }
            }
            .padding(.bottom, 20) // Bottom padding to ensure buttons don't hit the Dock
        }
        .toolbar(.hidden)
    }
    
    func processcapturedImage() {
        guard let image = capturedImage else { return }
        isProcessingImage = true
        let filename = VisionManager.saveImageToDisk(image: image)
        VisionManager.extractText(from: image) { extractedText in
            saveInsight(text: extractedText, type: .image, localFileName: filename)
            isProcessingImage = false; capturedImage = nil
        }
    }
    
    func saveInsight(text: String, type: InsightType, localFileName: String? = nil) {
        let lat = LocationManager.shared.currentLocation?.coordinate.latitude
        let long = LocationManager.shared.currentLocation?.coordinate.longitude
        let locLabel = LocationManager.shared.currentLabel
        let sentiment = SentimentManager.shared.analyzeSentiment(text: text)
        let newItem = InsightItem(type: type, content: text, localFileName: localFileName, lat: lat, long: long, locLabel: locLabel, sentiment: sentiment)
        modelContext.insert(newItem)
        withAnimation { showLatestInsight = true }
        Task {
            let descriptor = FetchDescriptor<InsightItem>()
            if let allItems = try? modelContext.fetch(descriptor) {
                BrainManager.shared.process(newItem, in: modelContext, allItems: allItems)
            }
        }
    }
    
    func actionButton(icon: String, action: @escaping () -> Void) -> some View {
        Button(action: {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        }) {
            Image(systemName: icon).font(.title2).frame(width: 60, height: 60).foregroundStyle(.white).liquidGlass(cornerRadius: 30)
        }
    }
}

// LIQUID DOCK & ITEM
struct LiquidDock: View {
    @Binding var selectedTab: AppTab
    var body: some View {
        HStack(spacing: 40) {
            DockItem(icon: "house.fill", tab: .home, selected: selectedTab) { withAnimation(.spring()) { selectedTab = .home } }
            DockItem(icon: "square.grid.2x2.fill", tab: .library, selected: selectedTab) { withAnimation(.spring()) { selectedTab = .library } }
            
            // ARA Special Icon
            Button(action: {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                withAnimation(.spring()) { selectedTab = .ara }
            }) {
                ZStack {
                    if selectedTab == .ara {
                        Circle()
                            .fill(LinearGradient(colors: [.purple, .blue], startPoint: .topLeading, endPoint: .bottomTrailing))
                            .frame(width: 45, height: 45)
                            .shadow(color: .purple.opacity(0.5), radius: 10)
                            .matchedGeometryEffect(id: "araBg", in: Namespace().wrappedValue)
                    } else {
                        Circle().stroke(LinearGradient(colors: [.purple.opacity(0.5), .blue.opacity(0.5)], startPoint: .top, endPoint: .bottom), lineWidth: 2)
                            .frame(width: 40, height: 40)
                    }
                    Image(systemName: "sparkles")
                        .font(.title3)
                        .foregroundStyle(.white)
                }
            }
            
            DockItem(icon: "dot.radiowaves.left.and.right", tab: .neural, selected: selectedTab) { withAnimation(.spring()) { selectedTab = .neural } }
        }
        .padding(.vertical, 15).padding(.horizontal, 30).background(.ultraThinMaterial).clipShape(Capsule())
        .overlay(Capsule().stroke(LinearGradient(colors: [.white.opacity(0.5), .white.opacity(0.1)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1))
        .shadow(color: .black.opacity(0.2), radius: 15, x: 0, y: 10)
    }
}

struct DockItem: View {
    let icon: String
    let tab: AppTab
    let selected: AppTab
    let action: () -> Void
    var isSelected: Bool { selected == tab }
    var body: some View {
        Button(action: {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        }) {
            VStack(spacing: 4) {
                Image(systemName: icon).font(.title2).foregroundStyle(isSelected ? .white : .white.opacity(0.5)).scaleEffect(isSelected ? 1.2 : 1.0)
                if isSelected { Circle().fill(.white).frame(width: 5, height: 5).matchedGeometryEffect(id: "dockDot", in: Namespace().wrappedValue) }
                else { Circle().fill(.clear).frame(width: 5, height: 5) }
            }
        }
    }
}
