import SwiftUI
import SwiftData
import MapKit
import AVFoundation
import Photos

struct LibraryView: View {
    @Query(sort: \InsightItem.dateCreated, order: .reverse) private var items: [InsightItem]
    @Environment(\.modelContext) private var modelContext
    
    // View Mode States
    @State private var isMapView = false
    @State private var showSentiment = false
    @State private var isSelectionMode = false
    @State private var selectedItems = Set<UUID>()
    @State private var selectedCategory: String? = nil
    @State private var cameraPosition: MapCameraPosition = .userLocation(fallback: .automatic)
    
    // Ghost Writer States
    @State private var showGhostWriterSheet = false
    @State private var ghostWriterOutput = ""
    @State private var isAlchemizing = false
    @State private var selectedFormat: GhostFormat = .summary
    @State private var selectedTone: GhostTone = .formal
    
    // Fusion State
    @State private var showFusionOverlay = false
    
    let columns = [GridItem(.flexible()), GridItem(.flexible())]
    
    var categories: [String] {
        let all = Set(items.compactMap { $0.category })
        return Array(all).sorted()
    }
    
    var filteredItems: [InsightItem] {
        if let category = selectedCategory { return items.filter { $0.category == category } }
        return items
    }
    
    var body: some View {
        ZStack {
            Color(hex: "0f172a").ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Category Filter
                if !isMapView {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            CategoryPill(name: "All", isSelected: selectedCategory == nil) {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred() // HAPTIC
                                withAnimation { selectedCategory = nil }
                            }
                            ForEach(categories, id: \.self) { cat in
                                CategoryPill(name: cat, isSelected: selectedCategory == cat) {
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred() // HAPTIC
                                    withAnimation { selectedCategory = cat }
                                }
                            }
                        }
                        .padding()
                    }
                    .background(.white.opacity(0.05))
                }
                
                // Content
                if isMapView {
                    Map(position: $cameraPosition) {
                        ForEach(filteredItems) { item in
                            if let lat = item.latitude, let long = item.longitude {
                                Annotation(item.title ?? "Note", coordinate: CLLocationCoordinate2D(latitude: lat, longitude: long)) {
                                    NavigationLink(destination: InsightDetailView(item: item)) {
                                        Image(systemName: iconFor(type: item.type))
                                            .padding(8).background(SentimentManager.shared.colorForScore(item.sentimentScore))
                                            .clipShape(Circle()).foregroundStyle(.white).shadow(radius: 5)
                                    }
                                    .simultaneousGesture(TapGesture().onEnded { UIImpactFeedbackGenerator(style: .light).impactOccurred() }) // HAPTIC
                                }
                            }
                        }
                    }
                    .mapStyle(.hybrid(elevation: .realistic))
                } else {
                    if filteredItems.isEmpty {
                        ContentUnavailableView("No Items", systemImage: "tray").frame(maxHeight: .infinity)
                    } else {
                        ScrollView {
                            LazyVGrid(columns: columns, spacing: 15) {
                                ForEach(filteredItems) { item in
                                    if isSelectionMode {
                                        InsightCard(item: item, isSelected: selectedItems.contains(item.id), isSelectionMode: true, showSentiment: showSentiment)
                                            .onTapGesture {
                                                UIImpactFeedbackGenerator(style: .light).impactOccurred() // HAPTIC
                                                if selectedItems.contains(item.id) { selectedItems.remove(item.id) }
                                                else { selectedItems.insert(item.id) }
                                            }
                                    } else {
                                        NavigationLink(destination: InsightDetailView(item: item)) {
                                            InsightCard(item: item, isSelected: false, isSelectionMode: false, showSentiment: showSentiment)
                                        }
                                        .simultaneousGesture(TapGesture().onEnded { UIImpactFeedbackGenerator(style: .light).impactOccurred() }) // HAPTIC
                                    }
                                }
                            }
                            .padding()
                            .padding(.bottom, 80)
                        }
                    }
                }
            }
            
            // Overlays
            if isAlchemizing { AlchemyView().transition(.opacity).zIndex(100) }
            
            if showFusionOverlay {
                FusionView(
                    items: items.filter { selectedItems.contains($0.id) },
                    onDismiss: { withAnimation { showFusionOverlay = false } },
                    onSave: { result in
                        let newItem = InsightItem(type: .note, content: result, title: "Fused Insight", category: "Fusion")
                        modelContext.insert(newItem)
                        try? modelContext.save()
                        selectedItems.removeAll()
                        isSelectionMode = false
                    }
                )
                .transition(.opacity).zIndex(200)
            }
        }
        .navigationTitle("Library")
        .toolbar {
            // LEFT SIDE: CANVAS, SENTIMENT, MAP
            ToolbarItem(placement: .topBarLeading) {
                HStack(spacing: 8) {
                    // 1. CANVAS / STUDIO BUTTON (Moved here)
                    NavigationLink(destination: StudioView()) {
                        Image(systemName: "paintpalette.fill").foregroundStyle(.blue)
                    }
                    .simultaneousGesture(TapGesture().onEnded { UIImpactFeedbackGenerator(style: .medium).impactOccurred() }) // HAPTIC
                    
                    // 2. SENTIMENT
                    Button(action: {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred() // HAPTIC
                        withAnimation { showSentiment.toggle() }
                    }) {
                        Image(systemName: showSentiment ? "sparkles" : "sparkles.rectangle.stack").foregroundStyle(showSentiment ? .yellow : .gray)
                    }
                    
                    // 3. MAP
                    Button(action: {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred() // HAPTIC
                        withAnimation { isMapView.toggle() }
                    }) { Image(systemName: isMapView ? "square.grid.2x2" : "map") }
                }
            }
            
            // RIGHT SIDE: SELECT
            ToolbarItem(placement: .topBarTrailing) {
                Button(isSelectionMode ? "Done" : "Select") {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred() // HAPTIC
                    withAnimation { isSelectionMode.toggle(); selectedItems.removeAll() }
                }
            }
            
            // --- BOTTOM TOOLBAR ---
            if isSelectionMode && !selectedItems.isEmpty {
                ToolbarItem(placement: .bottomBar) {
                    HStack {
                        Button(role: .destructive, action: deleteSelected) {
                            Label("Delete", systemImage: "trash").foregroundStyle(.red)
                        }
                        
                        Spacer()
                        
                        // FUSE BUTTON
                        if selectedItems.count >= 2 {
                            Button(action: {
                                UIImpactFeedbackGenerator(style: .heavy).impactOccurred() // HAPTIC
                                withAnimation { showFusionOverlay = true }
                            }) {
                                VStack(spacing: 0) {
                                    Image(systemName: "atom").font(.title2)
                                }
                                .foregroundStyle(.yellow)
                            }
                            Spacer()
                        }
                        
                        // TONE SELECTOR
                        Menu {
                            Picker("Tone", selection: $selectedTone) {
                                ForEach(GhostTone.allCases, id: \.self) { tone in Text(tone.rawValue).tag(tone) }
                            }
                        } label: {
                            HStack { Image(systemName: "dial.low.fill"); Text(selectedTone.rawValue) }
                                .font(.caption).foregroundStyle(.white).padding(8).background(Color.white.opacity(0.1)).clipShape(Capsule())
                        }
                        .simultaneousGesture(TapGesture().onEnded { UIImpactFeedbackGenerator(style: .light).impactOccurred() }) // HAPTIC
                        
                        Spacer()
                        
                        // GENERATE BUTTON
                        Menu {
                            Button("Draft Email", action: { triggerGhostWriter(format: .email) })
                            Button("LinkedIn Post", action: { triggerGhostWriter(format: .linkedin) })
                            Button("Executive Summary", action: { triggerGhostWriter(format: .summary) })
                        } label: {
                            Label("Generate", systemImage: "wand.and.stars")
                                .font(.headline).foregroundStyle(.white).padding(.horizontal, 16).padding(.vertical, 8)
                                .background(LinearGradient(colors: [.purple, .blue], startPoint: .leading, endPoint: .trailing)).clipShape(Capsule())
                        }
                        .simultaneousGesture(TapGesture().onEnded { UIImpactFeedbackGenerator(style: .medium).impactOccurred() }) // HAPTIC
                    }
                }
            }
        }
        .sheet(isPresented: $showGhostWriterSheet) {
            GhostResultView(content: ghostWriterOutput, format: selectedFormat)
        }
    }
    
    // ... (Helpers: triggerGhostWriter, deleteSelected, iconFor same as before)
    func triggerGhostWriter(format: GhostFormat) {
        selectedFormat = format; withAnimation { isAlchemizing = true }; UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        let selectedObjects = items.filter { selectedItems.contains($0.id) }
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 2.0) {
            let result = AraEngine().ghostWrite(items: selectedObjects, format: format, tone: selectedTone)
            DispatchQueue.main.async { self.ghostWriterOutput = result; withAnimation { isAlchemizing = false }; self.showGhostWriterSheet = true }
        }
    }
    func deleteSelected() {
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred() // HAPTIC
        withAnimation { for id in selectedItems { if let item = items.first(where: { $0.id == id }) { modelContext.delete(item) } }; selectedItems.removeAll(); isSelectionMode = false }
    }
    func iconFor(type: InsightType) -> String { switch type { case .audio: return "mic.fill"; case .image: return "camera.fill"; case .note: return "doc.text.fill"; case .pdf: return "doc.fill" } }
}

// ... (Subviews InsightCard, etc. same as provided) ...
struct InsightCard: View {
    let item: InsightItem; let isSelected: Bool; let isSelectionMode: Bool; let showSentiment: Bool
    var body: some View { VStack(alignment: .leading, spacing: 8) { HStack { Image(systemName: item.isLocked ? "lock.fill" : iconFor(type: item.type)).foregroundStyle(item.isLocked ? .red : .white); Spacer(); if isSelectionMode { Image(systemName: isSelected ? "checkmark.circle.fill" : "circle").foregroundStyle(isSelected ? .blue : .gray).font(.title2) } }; if item.isLocked { Text(item.title?.isEmpty == false ? item.title! : "Encrypted Note").font(.headline).foregroundStyle(.white).lineLimit(1); Text("Content hidden via biometric shield.").font(.caption).foregroundStyle(.white.opacity(0.3)).italic().lineLimit(3).frame(maxWidth: .infinity, alignment: .leading).blur(radius: 2) } else { if let title = item.title, !title.isEmpty { Text(title).font(.headline).foregroundStyle(.white).lineLimit(1) }; Text(item.content).font(.caption).foregroundStyle(.white.opacity(0.7)).lineLimit(3).frame(maxWidth: .infinity, alignment: .leading) }; Spacer(); if !item.isLocked, let loc = item.locationLabel { HStack(spacing: 4) { Image(systemName: "location.fill").font(.caption2); Text(loc).font(.caption2) }.foregroundStyle(.white.opacity(0.6)).padding(.bottom, 2) }; HStack { if let cat = item.category, !item.isLocked { Text(cat).font(.caption2).bold().padding(4).background(.blue.opacity(0.5)).cornerRadius(4).foregroundStyle(.white) }; Spacer(); Text(item.dateCreated.formatted(date: .numeric, time: .omitted)).font(.caption2).foregroundStyle(.gray) } }.padding().frame(height: 170).background(.ultraThinMaterial).cornerRadius(15).overlay(RoundedRectangle(cornerRadius: 15).stroke(isSelected ? .blue : (showSentiment && !item.isLocked ? SentimentManager.shared.colorForScore(item.sentimentScore).opacity(0.6) : .white.opacity(0.1)), lineWidth: isSelected ? 3 : (showSentiment ? 2 : 1)).shadow(color: (showSentiment && !item.isLocked) ? SentimentManager.shared.colorForScore(item.sentimentScore).opacity(0.5) : .clear, radius: showSentiment ? 8 : 0)) }
    func iconFor(type: InsightType) -> String { switch type { case .audio: return "mic.fill"; case .image: return "camera.fill"; case .note: return "doc.text.fill"; case .pdf: return "doc.fill" } }
}
struct CategoryPill: View { let name: String; let isSelected: Bool; let action: () -> Void; var body: some View { Text(name).font(.caption).bold().padding(.horizontal, 16).padding(.vertical, 8).background(isSelected ? .blue : .white.opacity(0.1)).foregroundStyle(.white).clipShape(Capsule()).onTapGesture(perform: action) } }
struct AlchemyView: View { @State private var rotation: Double = 0; var body: some View { ZStack { Color.black.opacity(0.8).ignoresSafeArea(); VStack(spacing: 30) { ZStack { ForEach(0..<3) { i in Circle().strokeBorder(AngularGradient(colors: [.purple, .blue, .clear], center: .center), lineWidth: 4).frame(width: 100 + CGFloat(i * 40), height: 100 + CGFloat(i * 40)).rotationEffect(.degrees(rotation * (i % 2 == 0 ? 1 : -1))) } }.onAppear { withAnimation(.linear(duration: 2).repeatForever(autoreverses: false)) { rotation = 360 } }; Text("Synthesizing Knowledge...").font(.headline).foregroundStyle(.white) } } } }
struct GhostResultView: View { let content: String; let format: GhostFormat; @Environment(\.dismiss) var dismiss; @State private var synthesizer = AVSpeechSynthesizer(); @State private var isSpeaking = false; @State private var showCrystalCard = false; @State private var saveStatus = ""; var body: some View { NavigationStack { ScrollView { VStack(spacing: 20) { Text(content).font(.body).padding().textSelection(.enabled); if showCrystalCard { VStack { CrystalCardView(text: content).frame(width: 300, height: 400).cornerRadius(20).shadow(radius: 10); Button("Save to Photos") { saveCrystalCard() }.buttonStyle(.borderedProminent).padding(.top); if !saveStatus.isEmpty { Text(saveStatus).font(.caption).foregroundStyle(.gray) } }.padding().transition(.scale) } } }.navigationTitle(format.rawValue).navigationBarTitleDisplayMode(.inline).toolbar { ToolbarItem(placement: .topBarLeading) { Button("Close") { dismiss() } }; ToolbarItem(placement: .topBarTrailing) { HStack { Button(action: toggleSpeech) { Image(systemName: isSpeaking ? "stop.circle.fill" : "play.circle") }; if format != .email { Button(action: { withAnimation { showCrystalCard.toggle() } }) { Image(systemName: "photo.artframe") } }; ShareLink(item: content) { Image(systemName: "square.and.arrow.up") } } } }.onDisappear { synthesizer.stopSpeaking(at: .immediate) } } }; func toggleSpeech() { if isSpeaking { synthesizer.stopSpeaking(at: .immediate); isSpeaking = false } else { let utterance = AVSpeechUtterance(string: content); utterance.voice = AVSpeechSynthesisVoice(language: "en-US"); utterance.rate = 0.5; synthesizer.speak(utterance); isSpeaking = true } }; @MainActor func saveCrystalCard() { let renderer = ImageRenderer(content: CrystalCardView(text: content).frame(width: 1080, height: 1350)); renderer.scale = 2.0; if let image = renderer.uiImage { let status = PHPhotoLibrary.authorizationStatus(for: .addOnly); if status == .authorized || status == .notDetermined { UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil); UINotificationFeedbackGenerator().notificationOccurred(.success); saveStatus = "Saved!" } else { saveStatus = "Permission Denied." } } } }
struct CrystalCardView: View { let text: String; var body: some View { ZStack { LinearGradient(colors: [.purple, .blue, .black], startPoint: .topLeading, endPoint: .bottomTrailing); Rectangle().fill(.ultraThinMaterial).opacity(0.3); VStack(alignment: .leading, spacing: 20) { Image(systemName: "quote.opening").font(.largeTitle).foregroundStyle(.white.opacity(0.8)); Text(text).font(.system(size: 24, weight: .medium, design: .serif)).foregroundStyle(.white).multilineTextAlignment(.leading).minimumScaleFactor(0.4); Spacer(); HStack { Text("Generated by Insight").font(.caption).textCase(.uppercase).foregroundStyle(.white.opacity(0.6)); Spacer(); Image(systemName: "sparkles").foregroundStyle(.white) } }.padding(40) } } }
